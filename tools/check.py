#!/usr/bin/env python3
"""Offline consistency check for this agentbox OMP profile.

Reads nothing but this repository: no network, no `ab`, no OMP, no live
profile. Every problem is printed as `path: problem` on stdout, one per line,
in discovery order. Warnings are printed as `path: warning: problem`. Exit
status is 1 if there is at least one error, 0 otherwise.

The rules enforced here come from the vendored OMP docs in `reference/omp/`
(at the commit in `reference/omp/SOURCE_COMMIT`) and from the fixed contract
agentbox has with a profile. Each check names its source in a comment.

Frontmatter is parsed by the small parser below rather than PyYAML, so the
check behaves identically on every machine and needs no dependencies. It
accepts the subset OMP profiles actually use: top-level `key: value`, quoted
scalars, flow lists, block lists, and `>` / `|` block scalars.
"""

from __future__ import annotations

import argparse
import os
import re
import sys
import tomllib
from pathlib import Path

# --- layout -----------------------------------------------------------------

# The profile layout is fixed. agentbox mounts skills/, rules/, prompts/,
# agents/ and commands/ read-only into every session and folds AGENTS.md into
# the per-session instructions; everything else here is build machinery.
ALLOWED_TOP_LEVEL = {
    "AGENTS.md",
    "README.md",
    "THIRD_PARTY.md",
    # The documentation for each load directory, one file per directory. It
    # cannot live inside the directory it documents: those are mounted onto
    # discovery paths and anything in them is loaded.
    "docs",
    "plugins.toml",
    "Containerfile",
    "build.sh",
    "skills",
    "rules",
    "prompts",
    "agents",
    "commands",
    "tools",
    "tests",
    "reference",
    # Keyless copies of what agentbox reads from ~/.config/agentbox/omp/; build.sh deploy installs them.
    "seed",
    ".git",
    ".gitignore",
    # Gitignored scratch directory: EGM artifacts (.dev/docs, see AGENTS.md)
    # and show-me's HTML files (.dev/show-me). Allowed at the top level so a
    # run that produced artifacts is not failed for it, as in the Claude
    # profile repo. .dev/ is skipped by the symlink and size rules because it
    # is gitignored and never deployed, but the secret-name rule still applies
    # inside it.
    ".dev",
}

# reference/omp/skills.md, "Practical authoring guidance tied to discovery
# logic": a skill name may not contain a path separator, and Agent Skills
# validation requires this shape.
SKILL_NAME_RE = re.compile(r"^[a-z0-9][a-z0-9-]{0,63}$")

# Frontmatter keys documented for a skill, normalized to camelCase.
#
# reference/omp/skills.md, "`SKILL.md` frontmatter" lists the OMP skill type's
# supported fields: name, description, globs, alwaysApply, hide,
# disableModelInvocation (normalized from kebab-case `disable-model-invocation`)
# and `enabled: false`. license, allowed-tools and model come from the Claude
# Code / Agent Skills frontmatter that OMP's claude-dialect providers read.
#
# An unknown key is a warning, not an error: conventional scanners (the native
# `.omp` provider included) preserve extra keys as unknown metadata, so a typo
# is silently ignored at runtime rather than rejected. Only Agent Plugins
# packages validate against a closed field set, and this profile is not one.
KNOWN_SKILL_KEYS = {
    "name",
    "description",
    "license",
    "allowedTools",
    "model",
    "disableModelInvocation",
    "hide",
    "globs",
    "alwaysApply",
    "enabled",
}

# The directories agentbox mounts onto an OMP discovery path. They hold only
# loadable items, and all but skills/ are optional (same rule as the Claude
# profile repo).
LOAD_DIRECTORIES = ("skills", "rules", "prompts", "agents", "commands")

# Documentation that must not sit in a load directory, at any depth.
# Case-insensitive, so `readme.md` is caught as well as `README.md` — a
# lowercase one is still a `.md` file and would otherwise load.
README_RE = re.compile(r"^readme", re.IGNORECASE)

# reference/omp/marketplace.md, "Naming rules".
PLUGIN_NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9.-]*$")
SHA1_RE = re.compile(r"^[0-9a-f]{40}$")

# The other two ways an OMP plugin arrives (agentbox's plugins.py, which installs this file): an npm package
# pinned to an exact version, and a git checkout pinned to a commit. Same rules as the launcher's, so that
# `check` fails here rather than at `ab profile install`.
NPM_NAME_RE = re.compile(r"^(?:@[a-z0-9][a-z0-9._-]*/)?[a-z0-9][a-z0-9._-]*$")
NPM_VERSION_RE = re.compile(r"^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$")
REPO_NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")
PLUGIN_SECTIONS = {"plugin": ("id", "marketplace", "source", "ref"),
                   "npm": ("name", "version"),
                   "repo": ("name", "url", "ref", "extension_dir")}
PLUGIN_REQUIRED = {"plugin": PLUGIN_SECTIONS["plugin"], "npm": PLUGIN_SECTIONS["npm"], "repo": ("name", "url", "ref")}

# reference/omp/rulebook-matching-pipeline.md, §6 `interruptMode`.
INTERRUPT_MODES = {"never", "prose-only", "tool-only", "always"}

MAX_FILE_BYTES = 1024 * 1024
AGENTS_MD_WARN_LINES = 150

SECRET_PATTERNS = (".env*", "*.pem", "id_*")


# --- reporting --------------------------------------------------------------


class Report:
    def __init__(self) -> None:
        self.problems: list[tuple[str, str, bool]] = []

    def error(self, path: object, msg: str) -> None:
        self.problems.append((str(path), msg, True))

    def warn(self, path: object, msg: str) -> None:
        self.problems.append((str(path), msg, False))

    @property
    def errors(self) -> int:
        return sum(1 for _, _, is_error in self.problems if is_error)

    @property
    def warnings(self) -> int:
        return len(self.problems) - self.errors

    def emit(self) -> None:
        for path, msg, is_error in self.problems:
            if is_error:
                print(f"{path}: {msg}")
            else:
                print(f"{path}: warning: {msg}")


# --- frontmatter ------------------------------------------------------------


class FrontmatterError(Exception):
    pass


KEY_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_-]*):(.*)$")
BLOCK_SCALAR_RE = re.compile(r"^[|>][+-]?$")


def _normkey(key: str) -> str:
    """Kebab-case to camelCase, as OMP's frontmatter parser normalizes keys."""
    return re.sub(r"-(\w)", lambda m: m.group(1).upper(), key)


def _scalar(text: str):
    text = text.strip()
    if not text:
        return ""
    if text[0] in "\"'":
        quote = text[0]
        end = text.find(quote, 1)
        if end == -1:
            raise FrontmatterError("unterminated quoted value")
        return text[1:end]
    # Strip a trailing YAML comment (" #" only, as YAML requires).
    cut = text.find(" #")
    if cut != -1:
        text = text[:cut].rstrip()
    if text.startswith("[") and text.endswith("]"):
        inner = text[1:-1].strip()
        if not inner:
            return []
        return [_scalar(part) for part in inner.split(",")]
    low = text.lower()
    if low in ("true", "yes", "on"):
        return True
    if low in ("false", "no", "off"):
        return False
    if low in ("null", "~"):
        return None
    if re.fullmatch(r"-?\d+", text):
        return int(text)
    return text


def _take_indented(lines: list[str], start: int) -> tuple[list[str], int]:
    out: list[str] = []
    i = start
    while i < len(lines):
        line = lines[i]
        if line.strip() == "":
            out.append("")
            i += 1
            continue
        if line[0] in " \t":
            out.append(line.strip())
            i += 1
            continue
        break
    while out and out[-1] == "":
        out.pop()
    return out, i


class Frontmatter:
    def __init__(self, values: dict[str, object]) -> None:
        self.raw = values
        self.norm = {_normkey(k): v for k, v in values.items()}

    def get(self, name: str, default=None):
        return self.norm.get(_normkey(name), default)

    def has(self, name: str) -> bool:
        return _normkey(name) in self.norm

    def nonempty_str(self, name: str) -> str | None:
        value = self.get(name)
        if isinstance(value, str) and value.strip():
            return value.strip()
        return None


def split_frontmatter(text: str) -> tuple[str | None, str]:
    """Return (raw frontmatter block, body). Frontmatter is None if absent.

    reference/omp/rulebook-matching-pipeline.md §3: frontmatter is parsed only
    when the content starts with `---` and has a closing `\\n---`.
    """
    lines = text.split("\n")
    if not lines or lines[0].strip() != "---":
        return None, text
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            return "\n".join(lines[1:i]), "\n".join(lines[i + 1 :])
    raise FrontmatterError("opens with '---' but the frontmatter is never closed")


def parse_frontmatter(raw: str) -> Frontmatter:
    values: dict[str, object] = {}
    lines = raw.split("\n")
    i = 0
    while i < len(lines):
        line = lines[i]
        if line.strip() == "" or line.lstrip().startswith("#"):
            i += 1
            continue
        if line[0] in " \t":
            raise FrontmatterError(f"unexpected indentation on frontmatter line {i + 1}")
        match = KEY_RE.match(line)
        if not match:
            raise FrontmatterError(f"frontmatter line {i + 1} is not 'key: value'")
        key, rest = match.group(1), match.group(2).strip()
        if key in values:
            raise FrontmatterError(f"duplicate frontmatter key '{key}'")
        if BLOCK_SCALAR_RE.match(rest):
            block, i = _take_indented(lines, i + 1)
            if rest[0] == ">":
                values[key] = " ".join(part for part in block if part)
            else:
                values[key] = "\n".join(block)
            continue
        if rest == "":
            block, nxt = _take_indented(lines, i + 1)
            body = [part for part in block if part]
            if body and all(part.startswith("- ") or part == "-" for part in body):
                values[key] = [_scalar(part[1:]) for part in body]
            elif body:
                # A nested mapping. Recorded as present, contents unused.
                values[key] = {"_nested": body}
            else:
                values[key] = None
            i = nxt
            continue
        values[key] = _scalar(rest)
        i += 1
    return Frontmatter(values)


def read_frontmatter(path: Path, rel: str, rep: Report, required: bool) -> Frontmatter | None:
    """Read and parse a file's frontmatter, reporting problems against `rel`."""
    try:
        text = path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as exc:
        rep.error(rel, f"cannot read as UTF-8 text: {exc}")
        return None
    try:
        raw, _body = split_frontmatter(text)
    except FrontmatterError as exc:
        rep.error(rel, str(exc))
        return None
    if raw is None:
        if required:
            rep.error(rel, "no frontmatter (a '---' delimited block is required)")
        return None
    try:
        return parse_frontmatter(raw)
    except FrontmatterError as exc:
        rep.error(rel, f"frontmatter does not parse: {exc}")
        return None


# --- helpers ----------------------------------------------------------------


def rel_of(root: Path, path: Path) -> str:
    try:
        return str(path.relative_to(root))
    except ValueError:
        return str(path)


def listdir_sorted(path: Path) -> list[Path]:
    return sorted(path.iterdir(), key=lambda p: p.name)


def check_load_directories(root: Path, rep: Report) -> None:
    """Load directories hold only loadable items — no README*
    file at any depth (case-insensitive) — and all but skills/ are optional.

    agentbox mounts these directories straight onto a discovery path, so OMP
    loads whatever is in them: a `commands/README.md` becomes a `/README`
    command in every session, and a `prompts/README.md` becomes a prompt
    template. Documentation lives in `docs/<dirname>.md` instead. This is the
    one place a README* is reported; the per-directory checks skip them so one
    misplaced file does not produce two errors.
    """
    for dirname in LOAD_DIRECTORIES:
        directory = root / dirname
        if not directory.is_dir():
            if dirname == "skills":
                rep.error(dirname, "missing (skills/ is the one load directory that is not optional)")
            continue
        for dirpath, dirnames, filenames in os.walk(directory, followlinks=False):
            dirnames.sort()
            for name in sorted(filenames):
                if README_RE.match(name):
                    rep.error(
                        rel_of(root, Path(dirpath) / name),
                        f"load directories hold only loadable items: {dirname}/ is a discovery path, "
                        f"so OMP would load this as content. Move it to docs/{dirname}.md",
                    )


def flat_md_dir(root: Path, dirname: str, rep: Report, extensions: tuple[str, ...]) -> list[Path]:
    """Validate a flat, non-recursive load directory and return its files.

    Every load directory agentbox mounts is scanned non-recursively, so a
    subdirectory is never discovered and is therefore dead weight, not a
    feature.
    """
    directory = root / dirname
    files: list[Path] = []
    if not directory.is_dir():
        return files
    for entry in listdir_sorted(directory):
        rel = rel_of(root, entry)
        if entry.is_symlink():
            continue  # reported by check_hygiene
        if entry.is_dir():
            rep.error(rel, f"unexpected directory in {dirname}/ (discovery is non-recursive, so nothing here is found)")
            continue
        if README_RE.match(entry.name):
            continue  # reported by check_load_directories
        if entry.suffix not in extensions:
            allowed = " or ".join(f"*{ext}" for ext in extensions)
            rep.error(rel, f"unexpected file in {dirname}/ (only {allowed} is discovered)")
            continue
        files.append(entry)
    return files


# --- checks -----------------------------------------------------------------


def check_top_level(root: Path, rep: Report) -> None:
    for entry in listdir_sorted(root):
        if entry.name in ALLOWED_TOP_LEVEL:
            continue
        rep.error(
            entry.name,
            "unexpected top-level entry (the profile layout is fixed; see README.md)",
        )

    agents_md = root / "AGENTS.md"
    if not agents_md.is_file():
        rep.error("AGENTS.md", "missing (agentbox folds it into every session's instructions)")
    else:
        lines = agents_md.read_text(encoding="utf-8", errors="replace").count("\n") + 1
        if lines > AGENTS_MD_WARN_LINES:
            rep.warn("AGENTS.md", f"{lines} lines, over {AGENTS_MD_WARN_LINES}: it rides on every request")

    if not (root / "README.md").is_file():
        rep.warn("README.md", "missing")

    build = root / "build.sh"
    if build.is_file() and not os.access(build, os.X_OK):
        rep.warn("build.sh", "not executable")


def check_skills(root: Path, rep: Report) -> None:
    """reference/omp/skills.md: skills/<name>/SKILL.md, one level, name and
    description both required (the native `.omp` provider discovers with
    requireDescription: true)."""
    directory = root / "skills"
    if not directory.is_dir():
        return
    for entry in listdir_sorted(directory):
        rel = rel_of(root, entry)
        if entry.is_symlink():
            continue  # reported by check_hygiene
        if not entry.is_dir():
            if README_RE.match(entry.name):
                continue  # reported by check_load_directories
            rep.error(rel, "unexpected file in skills/ (every skill is a directory holding SKILL.md)")
            continue

        if not SKILL_NAME_RE.match(entry.name):
            rep.error(rel, "invalid skill directory name (must match ^[a-z0-9][a-z0-9-]{0,63}$)")

        skill_md = entry / "SKILL.md"
        skill_rel = f"{rel}/SKILL.md"
        if not skill_md.is_file():
            rep.error(skill_rel, "missing (a skill directory without SKILL.md is not discovered)")
        else:
            fm = read_frontmatter(skill_md, skill_rel, rep, required=True)
            if fm is not None:
                name = fm.nonempty_str("name")
                if name is None:
                    rep.error(skill_rel, "frontmatter is missing required key 'name'")
                else:
                    if "/" in name or "\\" in name:
                        rep.error(skill_rel, "frontmatter 'name' may not contain '/' or '\\' (reserved for namespaced skills)")
                    elif name != entry.name:
                        rep.error(skill_rel, f"frontmatter 'name' is '{name}' but the directory is '{entry.name}'")
                if fm.nonempty_str("description") is None:
                    rep.error(
                        skill_rel,
                        "frontmatter is missing required key 'description' (OMP's native loader requires it)",
                    )
                if fm.get("enabled") is False:
                    rep.warn(skill_rel, "'enabled: false' — this skill is not discovered")
                for key in fm.raw:
                    if _normkey(key) not in KNOWN_SKILL_KEYS:
                        rep.warn(
                            skill_rel,
                            f"unknown frontmatter key '{key}': OMP keeps it as metadata and ignores it, so check the spelling",
                        )

        # One level only: reference/omp/skills.md, "Directory layout".
        for dirpath, dirnames, filenames in os.walk(entry, followlinks=False):
            if Path(dirpath) == entry:
                continue
            if "SKILL.md" in filenames:
                nested = Path(dirpath) / "SKILL.md"
                rep.error(
                    rel_of(root, nested),
                    "nested skill directory (OMP discovers skills one level under skills/ only)",
                )


def check_rules(root: Path, rep: Report) -> None:
    """reference/omp/rulebook-matching-pipeline.md: rules/<name>.{md,mdc}, name
    from the filename, and §5/§9.3 — a rule with no description, no
    alwaysApply and no accepted trigger joins no bucket and is unreachable."""
    for path in flat_md_dir(root, "rules", rep, (".md", ".mdc")):
        rel = rel_of(root, path)
        stem = path.stem
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", stem):
            rep.warn(rel, f"rule name '{stem}' comes from the filename; keep it to letters, digits, '.', '_' and '-'")

        fm = read_frontmatter(path, rel, rep, required=False)
        if fm is None:
            rep.error(rel, "no description, alwaysApply or TTSR trigger: the rule joins no bucket and is not addressable via rule://")
            continue

        if fm.get("enabled") is False:
            rep.warn(rel, "'enabled: false' — this rule is excluded before deduplication")
            continue

        has_description = fm.nonempty_str("description") is not None
        always = fm.get("alwaysApply") is True
        triggers = any(
            fm.get(key) not in (None, "", [], False) for key in ("condition", "astCondition", "question")
        )
        if not (has_description or always or triggers):
            rep.error(
                rel,
                "no description, alwaysApply or TTSR trigger: the rule joins no bucket and is not addressable via rule://",
            )

        mode = fm.get("interruptMode")
        if mode is not None and mode not in INTERRUPT_MODES:
            rep.error(rel, f"invalid interruptMode '{mode}' (expected one of {', '.join(sorted(INTERRUPT_MODES))})")

        for key in ("globs", "agents", "scope"):
            value = fm.get(key)
            if value is not None and not isinstance(value, (str, list)):
                rep.warn(rel, f"'{key}' should be a string or a list, not {type(value).__name__}")


def check_agents(root: Path, rep: Report) -> None:
    """reference/omp/task-agent-discovery.md: name and description are required
    and 'main'/'sub' are reserved; the name comes from frontmatter."""
    for path in flat_md_dir(root, "agents", rep, (".md",)):
        rel = rel_of(root, path)
        fm = read_frontmatter(path, rel, rep, required=True)
        if fm is None:
            continue
        name = fm.nonempty_str("name")
        if name is None:
            rep.error(rel, "frontmatter is missing required key 'name' (the definition is invalid without it)")
        else:
            if name.strip().lower() in ("main", "sub"):
                rep.error(rel, f"frontmatter 'name' is '{name}', which is reserved ('main' and 'sub' are rejected)")
            elif name != path.stem:
                rep.warn(rel, f"frontmatter 'name' is '{name}' but the file is '{path.stem}.md'; keep them equal")
        if fm.nonempty_str("description") is None:
            rep.error(rel, "frontmatter is missing required key 'description' (the definition is invalid without it)")


def check_commands(root: Path, rep: Report) -> None:
    """reference/omp/slash-command-internals.md: commands/<name>.md, the name is
    the filename, the description falls back to the first body line."""
    for path in flat_md_dir(root, "commands", rep, (".md",)):
        rel = rel_of(root, path)
        if re.search(r"\s", path.stem):
            rep.error(rel, "command name comes from the filename and is split at the first space, so it cannot contain whitespace")
        fm = read_frontmatter(path, rel, rep, required=False)
        if fm is None:
            rep.warn(rel, "no frontmatter 'description': autocomplete falls back to the first body line, truncated to 60 chars")
            continue
        if fm.nonempty_str("description") is None:
            rep.warn(rel, "no frontmatter 'description': autocomplete falls back to the first body line, truncated to 60 chars")
        side = fm.get("side")
        if side is not None and side is not True:
            rep.warn(rel, f"'side' must be the boolean true to route as a /btw side question; '{side}' does not count")


def check_prompts(root: Path, rep: Report) -> None:
    """The vendored OMP docs do not specify the prompt-template format (see
    docs/prompts.md), so only structural rules are enforced here."""
    for path in flat_md_dir(root, "prompts", rep, (".md",)):
        rel = rel_of(root, path)
        fm = read_frontmatter(path, rel, rep, required=False)
        if fm is None or fm.nonempty_str("description") is None:
            rep.warn(rel, "no frontmatter 'description' (the prompt-template format is not specified; see docs/prompts.md)")


def _check_npm_and_repo(data: dict, rel: str, rep: Report) -> None:
    """[[npm]] and [[repo]] entries, by the launcher's rules: every key known, the required ones present,
    an exact npm version, an https URL without credentials, a 40-character ref, and names that are unique
    across both kinds (each repo is checked out into a directory of that name, beside node_modules/)."""
    seen: dict[str, str] = {}
    for kind in ("npm", "repo"):
        entries = data.get(kind, [])
        if not isinstance(entries, list):
            rep.error(rel, f"'{kind}' must be a list of [[{kind}]] tables")
            continue
        for index, entry in enumerate(entries, start=1):
            label = f"{kind} #{index}"
            if not isinstance(entry, dict):
                rep.error(rel, f"{label}: not a table")
                continue
            name = entry.get("name")
            if isinstance(name, str) and name:
                label = f"{kind} '{name}'"
            for key in PLUGIN_REQUIRED[kind]:
                value = entry.get(key)
                if not isinstance(value, str) or not value.strip():
                    rep.error(rel, f"{label}: missing required key '{key}'")
            for key in entry:
                if key not in PLUGIN_SECTIONS[kind]:
                    rep.warn(rel, f"{label}: unknown key '{key}'")
            if not isinstance(name, str) or not name:
                continue
            if name in seen:
                rep.error(rel, f"{label}: duplicate name (already a {seen[name]} entry)")
            seen[name] = kind
            if kind == "npm":
                if not NPM_NAME_RE.match(name):
                    rep.error(rel, f"{label}: '{name}' is not an npm package name ('pkg' or '@scope/pkg')")
                version = entry.get("version")
                if isinstance(version, str) and version and not NPM_VERSION_RE.match(version):
                    rep.error(rel, f"{label}: version '{version}' must be exact (1.2.3), not a range or a tag")
                continue
            if name == "node_modules" or not REPO_NAME_RE.match(name):
                rep.error(rel, f"{label}: name must be a plain directory name (letters, digits, '.', '_', '-'), "
                               "and not 'node_modules'")
            url = entry.get("url")
            if isinstance(url, str) and url:
                host = url[len("https://"):].split("/", 1)[0] if url.startswith("https://") else ""
                if not url.startswith("https://") or not host or host.startswith(".") or ".." in url:
                    rep.error(rel, f"{label}: url '{url}' must be a plain https:// URL (no git://, http:// or ssh)")
                elif "@" in host:
                    rep.error(rel, f"{label}: url carries credentials; a credential never enters a sandbox")
            ref = entry.get("ref")
            if isinstance(ref, str) and ref and not SHA1_RE.match(ref):
                rep.error(rel, f"{label}: ref '{ref}' must be a 40-character lowercase commit sha, not a branch or tag")
            ext = entry.get("extension_dir")
            if ext is not None and (not isinstance(ext, str) or not REPO_NAME_RE.match(ext)):
                rep.error(rel, f"{label}: extension_dir must be a plain directory name inside the checkout")


def check_plugins(root: Path, rep: Report) -> None:
    """plugins.toml is declarative only: agentbox installs these. Names and ids
    follow reference/omp/marketplace.md, "Naming rules"; a ref must be a pinned
    commit sha because marketplace catalogs are mutable."""
    path = root / "plugins.toml"
    rel = "plugins.toml"
    if not path.is_file():
        rep.error(rel, "missing (declare plugins here even if the list is empty)")
        return
    try:
        with path.open("rb") as handle:
            data = tomllib.load(handle)
    except (OSError, tomllib.TOMLDecodeError) as exc:
        rep.error(rel, f"does not parse as TOML: {exc}")
        return

    for key in data:
        if key not in PLUGIN_SECTIONS:
            rep.warn(rel, f"unknown top-level key '{key}' (only [[plugin]], [[npm]] and [[repo]] tables are read)")

    _check_npm_and_repo(data, rel, rep)

    entries = data.get("plugin", [])
    if not isinstance(entries, list):
        rep.error(rel, "'plugin' must be a list of [[plugin]] tables")
        return

    seen: set[str] = set()
    for index, entry in enumerate(entries, start=1):
        label = f"plugin #{index}"
        if not isinstance(entry, dict):
            rep.error(rel, f"{label}: not a table")
            continue
        plugin_id = entry.get("id")
        if isinstance(plugin_id, str) and plugin_id:
            label = f"plugin '{plugin_id}'"
        for key in ("id", "marketplace", "source", "ref"):
            value = entry.get(key)
            if not isinstance(value, str) or not value.strip():
                rep.error(rel, f"{label}: missing required key '{key}'")
        for key in entry:
            if key not in ("id", "marketplace", "source", "ref"):
                rep.warn(rel, f"{label}: unknown key '{key}'")

        if not isinstance(plugin_id, str) or "@" not in plugin_id:
            if isinstance(plugin_id, str) and plugin_id:
                rep.error(rel, f"{label}: id must be '<name>@<marketplace>'")
            continue
        if plugin_id in seen:
            rep.error(rel, f"{label}: duplicate id")
        seen.add(plugin_id)

        name, _, marketplace = plugin_id.partition("@")
        if len(plugin_id) > 128:
            rep.error(rel, f"{label}: id is {len(plugin_id)} characters, over the 128-character limit")
        for part, what in ((name, "plugin name"), (marketplace, "marketplace name")):
            if not PLUGIN_NAME_RE.match(part) or not re.match(r"[A-Za-z0-9]$", part[-1:]):
                rep.error(
                    rel,
                    f"{label}: invalid {what} '{part}' (ASCII letters, digits, '-' and '.', starting and ending with a letter or digit)",
                )
            elif len(part) > 64:
                rep.error(rel, f"{label}: {what} '{part}' is {len(part)} characters, over the 64-character limit")

        declared = entry.get("marketplace")
        if isinstance(declared, str) and declared and declared != marketplace:
            rep.error(rel, f"{label}: marketplace is '{declared}' but the id says '{marketplace}'")

        ref = entry.get("ref")
        if isinstance(ref, str) and ref and not SHA1_RE.match(ref):
            rep.error(rel, f"{label}: ref '{ref}' must be a 40-character lowercase commit sha, not a branch or tag")


def _containerfile_instructions(text: str) -> list[tuple[int, str]]:
    """Comment-stripped logical instructions as (1-based line number, text)."""
    instructions: list[tuple[int, str]] = []
    pending: list[str] = []
    start = 0
    for number, line in enumerate(text.split("\n"), start=1):
        stripped = line.strip()
        if not pending and (not stripped or stripped.startswith("#")):
            continue
        if not pending:
            start = number
        if stripped.endswith("\\"):
            pending.append(stripped[:-1])
            continue
        pending.append(stripped)
        instructions.append((start, " ".join(pending).strip()))
        pending = []
    if pending:
        instructions.append((start, " ".join(pending).strip()))
    return instructions


def check_containerfile(root: Path, rep: Report) -> None:
    """The agentbox contract: start `ARG BASE` then `FROM ${BASE}` (ab passes
    the current agentbox-omp tag), no USER/ENTRYPOINT/CMD, and every download
    checksum-verified."""
    path = root / "Containerfile"
    rel = "Containerfile"
    if not path.is_file():
        return  # optional
    text = path.read_text(encoding="utf-8", errors="replace")
    instructions = _containerfile_instructions(text)
    if not instructions:
        rep.error(rel, "has no instructions")
        return

    first_line, first = instructions[0]
    if not re.fullmatch(r"ARG\s+BASE", first, re.IGNORECASE):
        rep.error(rel, f"line {first_line}: first instruction must be 'ARG BASE' (ab passes the current agentbox-omp tag)")
    if len(instructions) < 2:
        rep.error(rel, "second instruction must be 'FROM ${BASE}'")
    else:
        second_line, second = instructions[1]
        if not re.fullmatch(r"FROM\s+\$\{BASE\}(\s+AS\s+\S+)?", second, re.IGNORECASE):
            rep.error(rel, f"line {second_line}: second instruction must be 'FROM ${{BASE}}'")

    for number, instruction in instructions:
        verb = instruction.split(None, 1)[0].upper() if instruction.split() else ""
        if verb in ("USER", "ENTRYPOINT", "CMD"):
            rep.error(rel, f"line {number}: must not set {verb} (the agentbox base image owns it)")

        urls = re.findall(r"https?://[^\s'\"`;)]+", instruction)
        if not urls:
            continue
        has_digest = re.search(r"\b[0-9a-f]{64}\b", instruction)
        has_verify = re.search(r"sha256sum|shasum\s+-a\s*256|sha256\s+-c", instruction)
        if not (has_digest and has_verify):
            rep.error(rel, f"line {number}: download is not checksum-verified ({urls[0]})")


def check_hygiene(root: Path, rep: Report) -> None:
    """No symlinks (they would not survive a read-only mount and
    can escape the profile) and nothing over 1 MB in tracked paths; a name
    matching .env*, *.pem or id_* is an error anywhere, .dev/ included; .dev/ is
    otherwise skipped, because it is gitignored and never deployed."""
    import fnmatch

    dev_dir = root / ".dev"

    for dirpath, dirnames, filenames in os.walk(root, topdown=True, followlinks=False):
        here = Path(dirpath)
        if here == root:
            dirnames[:] = [d for d in dirnames if d != ".git"]
        dirnames.sort()
        # os.walk(followlinks=False) does not descend into symlinked
        # directories, so reporting one is enough.
        in_dev = here == dev_dir or dev_dir in here.parents
        for name in dirnames:
            entry = here / name
            if entry == dev_dir or in_dev:
                continue
            if entry.is_symlink():
                rep.error(rel_of(root, entry), "symlink (the profile is mounted read-only; keep real directories)")
        for name in sorted(filenames):
            entry = here / name
            rel = rel_of(root, entry)

            # Secret-looking names are an error anywhere, .dev/ included.
            secret = next((p for p in SECRET_PATTERNS if fnmatch.fnmatch(name, p)), None)
            if secret is not None:
                rep.error(rel, f"name matches '{secret}': secrets and keys never live in the profile")
                continue
            if in_dev:
                continue

            if entry.is_symlink():
                rep.error(rel, "symlink (the profile is mounted read-only; keep real files)")
                continue
            try:
                size = entry.stat().st_size
            except OSError as exc:
                rep.error(rel, f"cannot stat: {exc}")
                continue
            if size > MAX_FILE_BYTES:
                rep.error(rel, f"{size} bytes, over the {MAX_FILE_BYTES}-byte limit")


# --- seed/ -----------------------------------------------------------------

# A credential-shaped line: `apiKey: sk-...`, `"token": "..."`, `password = ...`.
CREDENTIAL_LINE = re.compile(
    r"""^\s*["']?(?P<key>apiKey|api_key|apikey|token|secret|password|authorization)["']?\s*[:=]\s*["']?(?P<value>[^\s"',]*)""",
    re.IGNORECASE)
SEED_DIR = "seed"


def check_seed(root: Path, rep) -> None:
    """`seed/`: keyless copies of the files agentbox reads from ~/.config/agentbox/<agent>/ (OMP: models.yml,
    config.yml, mcp.json), which `build.sh deploy` installs when the live one is missing.
    Files only, and never a credential: agentbox refuses any `apiKey` in the model seed outright, and the
    rest are mounted read-only into every session, where the agent can read them. A `$VAR` reference and an
    empty or `none` value are not credentials."""
    seed = root / SEED_DIR
    if not seed.exists():
        return
    if not seed.is_dir():
        rep.error(SEED_DIR, "must be a directory of seed files")
        return
    for entry in sorted(seed.iterdir(), key=lambda p: p.name):
        rel = f"{SEED_DIR}/{entry.name}"
        if entry.is_dir():
            rep.error(rel, "seed/ holds files only: agentbox reads flat files from ~/.config/agentbox/<agent>/")
            continue
        try:
            text = entry.read_text(encoding="utf-8", errors="replace")
        except OSError as exc:
            rep.error(rel, f"cannot read: {exc}")
            continue
        for n, line in enumerate(text.splitlines(), 1):
            m = CREDENTIAL_LINE.match(line)
            if not m:
                continue
            key, value = m.group("key"), m.group("value")
            if entry.name == "models.yml" and key.lower() == "apikey":
                rep.error(rel, f"line {n}: `apiKey` is refused in the model seed by agentbox itself; remove "
                               "it, keys live in ~/.config/agentbox/keys/ (`ab keys set <provider>`)")
                continue
            if value.lower() in ("", "none", "null", "~") or value.startswith("$"):
                continue
            rep.error(rel, f"line {n} looks like a credential ({key}: ...); seeds are keyless, keys go "
                           "through `ab keys set <provider>`")


# --- entry point ------------------------------------------------------------


def list_plugins(root: Path) -> int:
    """`build.sh status` reads this: one 'name source ref' line per entry of every kind, so the list is what
    agentbox installs: [[plugin]] as 'id source sha', [[npm]] as 'name npm version', [[repo]] as 'name url sha'."""
    path = root / "plugins.toml"
    if not path.is_file():
        return 0
    try:
        with path.open("rb") as handle:
            data = tomllib.load(handle)
    except (OSError, tomllib.TOMLDecodeError) as exc:
        print(f"plugins.toml: does not parse as TOML: {exc}", file=sys.stderr)
        return 1
    columns = {"plugin": ("id", "source", "ref"), "npm": ("name", None, "version"), "repo": ("name", "url", "ref")}
    for kind, (first, second, third) in columns.items():
        entries = data.get(kind, [])
        if not isinstance(entries, list):
            continue
        for entry in entries:
            if isinstance(entry, dict):
                print(entry.get(first, "?"), entry.get(second, "?") if second else "npm", entry.get(third, "?"))
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument(
        "--root",
        default=str(Path(__file__).resolve().parent.parent),
        help="profile directory to check (default: this repository)",
    )
    parser.add_argument(
        "--list-plugins",
        action="store_true",
        help="print 'id source ref' for each declared plugin instead of checking",
    )
    args = parser.parse_args(argv)

    root = Path(args.root).resolve()
    if not root.is_dir():
        print(f"{args.root}: not a directory", file=sys.stderr)
        return 1

    if args.list_plugins:
        return list_plugins(root)

    rep = Report()
    check_top_level(root, rep)
    check_load_directories(root, rep)
    check_skills(root, rep)
    check_rules(root, rep)
    check_prompts(root, rep)
    check_agents(root, rep)
    check_commands(root, rep)
    check_plugins(root, rep)
    check_containerfile(root, rep)
    check_seed(root, rep)
    check_hygiene(root, rep)

    rep.emit()
    sys.stdout.flush()
    if rep.errors or rep.warnings:
        print(f"{rep.errors} error(s), {rep.warnings} warning(s)", file=sys.stderr)
    return 1 if rep.errors else 0


if __name__ == "__main__":
    sys.exit(main())
