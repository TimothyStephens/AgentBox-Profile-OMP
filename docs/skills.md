# skills/

Agent Skills for every OMP session. agentbox mounts this directory read-only at
`~/.omp/agent/skills`, so OMP's **native** provider (priority 100) discovers
everything here as *user* skills.

Reference: [`reference/omp/skills.md`](../reference/omp/skills.md).

## Layout

```text
skills/
  <skill-name>/
    SKILL.md        # required
    LICENSE         # for vendored skills
    <assets>        # read with skill://<skill-name>/<path>
```

Discovery is **one level deep and non-recursive**: `skills/<name>/SKILL.md` is
found, `skills/group/<name>/SKILL.md` is not
(`reference/omp/skills.md`, "Required layout and SKILL.md expectations").

## Required frontmatter

| Key | Required | Notes |
| --- | --- | --- |
| `name` | yes | Must equal the directory name. Must match `^[a-z0-9][a-z0-9-]{0,63}$`. May not contain `/` or `\`. |
| `description` | yes | The native `.omp` provider discovers with `requireDescription: true`; a skill without one is dropped. It is also the only text the model sees before reading the skill, so write it as a trigger ("Use when …"). |

## Optional frontmatter

| Key | Effect |
| --- | --- |
| `hide: true` | Keeps the skill out of the system-prompt listing. Still reachable via `skill://<name>` and `/skill:<name>`. |
| `disable-model-invocation: true` | Agent-Skills spelling of `hide`; normalized to `disableModelInvocation` and read as `hide`. This is how `show-me` stays unlisted while remaining invocable as `/skill:show-me`. |
| `enabled: false` | Skips the skill entirely. |
| `globs`, `alwaysApply` | Carried as metadata only. They do **not** auto-invoke a skill. |
| `license` | SPDX identifier, for vendored skills. Claude Code / Agent Skills frontmatter. |
| `allowed-tools` | Tool allowlist, read by OMP's claude-dialect providers. |
| `model` | Model selector, read by OMP's claude-dialect providers. |

Any other key is **kept as unknown metadata and ignored** by conventional
scanners, the native `.omp` provider included — a misspelled key fails silently
at runtime rather than erroring. `./build.sh check` therefore *warns* on a key
outside the list above instead of failing.

## Invoking

- Model-selected from the system-prompt listing (unless hidden).
- `/skill:<name> [args]` when `skills.enableSkillCommands` is on.
- `read skill://<name>` / `read skill://<name>/<relative-path>`.

## Authoring notes

- Keep every asset inside the skill directory; `skill://` rejects absolute
  paths, `..` traversal, and anything resolving outside the skill base dir.
- Do not rely on OMP auto-learn: it writes only to
  `~/.omp/agent/managed-skills`, which agentbox makes per-session and drains to
  a review inbox at teardown. Nothing in this repo may depend on it.
- Vendored (third-party) skills must be listed in
  [`../THIRD_PARTY.md`](../THIRD_PARTY.md) with source, commit, license and
  local changes.
