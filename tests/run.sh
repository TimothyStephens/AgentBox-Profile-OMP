#!/usr/bin/env bash
#
# Tests for tools/check.py and build.sh.
#
#   ./tests/run.sh
#
# Each case builds a known-good profile fixture in a temp directory, applies one
# mutation, and asserts that check passes with no output, fails with a specific
# message, or warns with a specific message.
#
# Every rule shared with agentbox-profile-claude has a pass case and a fail
# case here, under the same name as in that repo. So:
#
#   shared: ...   a rule both profile repos enforce. Same name in both.
#   omp:    ...   a rule this harness forces. Has no sibling.
#
# Exits 0 only if every case passes.
#
set -uo pipefail

TESTS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname -- "$TESTS_DIR")"
CHECK="$REPO_DIR/tools/check.py"
BUILD="$REPO_DIR/build.sh"
SIBLING="$REPO_DIR/../agentbox-profile-claude/tests/run.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PASSED=0
FAILED=0

pass() {
	PASSED=$((PASSED + 1))
	printf 'ok    %s\n' "$1"
}

fail() {
	FAILED=$((FAILED + 1))
	printf 'FAIL  %s\n' "$1"
	printf '%s\n' "$2" | sed 's/^/        /'
}

# --- the known-good fixture -------------------------------------------------

make_good() {
	local fx="$1"
	mkdir -p "$fx"/skills/good-skill "$fx"/rules "$fx"/prompts "$fx"/agents \
		"$fx"/commands "$fx"/tools "$fx"/tests "$fx"/docs

	# The load directories' documentation lives here, never inside them.
	for dir in skills rules prompts agents commands; do
		printf '# %s\n' "$dir" >"$fx/docs/$dir.md"
	done

	printf '# Working rules\n\nShort enough.\n' >"$fx/AGENTS.md"
	printf '# profile\n' >"$fx/README.md"
	printf '# third party\n' >"$fx/THIRD_PARTY.md"
	printf '#!/usr/bin/env bash\ntrue\n' >"$fx/build.sh"
	chmod +x "$fx/build.sh"
	printf '# placeholder\n' >"$fx/tools/check.py"
	printf '# placeholder\n' >"$fx/tests/run.sh"

	cat >"$fx/plugins.toml" <<'TOML'
[[plugin]]
id = "egm@egm"
marketplace = "egm"
source = "google/elephant-goldfish-model"
ref = "464db031e7dd1b9a79803ac8ea45f55c7c20c5bc"
TOML

	cat >"$fx/Containerfile" <<'DOCKER'
ARG BASE
FROM ${BASE}
RUN set -eux; \
    url='https://example.invalid/thing.tar.gz'; \
    sha256='0000000000000000000000000000000000000000000000000000000000000000'; \
    curl -fsSL -o /tmp/thing "$url"; \
    printf '%s  %s\n' "$sha256" /tmp/thing | sha256sum -c -
ENV EDITOR=nvim
ENV VISUAL=nvim
DOCKER

	cat >"$fx/skills/good-skill/SKILL.md" <<'MD'
---
name: good-skill
description: Use when the fixture needs a discoverable skill.
---

Body.
MD

	cat >"$fx/rules/example.md" <<'MD'
---
description: An addressable rulebook rule.
---

Body.
MD

	cat >"$fx/agents/example.md" <<'MD'
---
name: example
description: A valid task agent definition.
---

Body.
MD

	cat >"$fx/commands/example.md" <<'MD'
---
description: A valid slash command.
---

Body with $ARGUMENTS.
MD

	cat >"$fx/prompts/example.md" <<'MD'
---
description: A prompt template.
---

Body.
MD
}

# --- the harness ------------------------------------------------------------

CASE_NUMBER=0

# run_case <label> <ok|fail|warn> <expected substring> <mutation shell code>
run_case() {
	local label="$1" mode="$2" expected="$3" mutation="$4"
	CASE_NUMBER=$((CASE_NUMBER + 1))
	local fx="$WORK/case-$CASE_NUMBER"
	make_good "$fx"
	if ! (cd "$fx" && eval "$mutation") >/dev/null 2>&1; then
		fail "$label" "the mutation itself failed: $mutation"
		return
	fi

	local out rc
	out="$(python3 "$CHECK" --root "$fx" 2>&1)"
	rc=$?

	case "$mode" in
	ok)
		if [[ $rc -eq 0 && -z "$out" ]]; then
			pass "$label"
		else
			fail "$label" "expected exit 0 and no output, got exit $rc:
$out"
		fi
		;;
	fail)
		if [[ $rc -eq 1 ]] && grep -qF -- "$expected" <<<"$out"; then
			pass "$label"
		elif [[ $rc -ne 1 ]]; then
			fail "$label" "expected exit 1, got exit $rc:
$out"
		else
			fail "$label" "exit 1 but no message matching: $expected
$out"
		fi
		;;
	warn)
		if [[ $rc -eq 0 ]] && grep -qF -- "$expected" <<<"$out"; then
			pass "$label"
		elif [[ $rc -ne 0 ]]; then
			fail "$label" "expected exit 0 (warning only), got exit $rc:
$out"
		else
			fail "$label" "exit 0 but no warning matching: $expected
$out"
		fi
		;;
	esac
}

# ===========================================================================
# shared rules. Same names in agentbox-profile-claude.
# ===========================================================================

# --- only the documented top-level entries ---------------------------------

run_case "shared: only documented top-level entries — pass" ok "" "true"

run_case "shared: only documented top-level entries — fail" fail \
	"notes.md: unexpected top-level entry" \
	"printf 'x\n' > notes.md"

# --- the instruction file ---------------------------------------------------
# The filename is an allowed difference: AGENTS.md here, CLAUDE.md in the
# sibling. The rule is the same.

run_case "shared: instruction file present — pass" ok "" \
	"printf '# Working rules\n\nRules.\n' > AGENTS.md"

run_case "shared: instruction file present — fail" fail \
	"AGENTS.md: missing" \
	"rm AGENTS.md"

run_case "shared: instruction file under 150 lines — pass" ok "" \
	"seq 140 > AGENTS.md"

run_case "shared: instruction file under 150 lines — fail" warn \
	"lines, over 150" \
	"seq 200 > AGENTS.md"

# --- skills one level deep -------------------------------------------------

run_case "shared: skills one level deep — pass" ok "" \
	"mkdir -p skills/second-skill && printf -- '---\nname: second-skill\ndescription: A second skill beside the first.\n---\n\nBody.\n' > skills/second-skill/SKILL.md"

run_case "shared: skills one level deep — fail" fail \
	"nested skill directory" \
	"mkdir -p skills/good-skill/inner && cp skills/good-skill/SKILL.md skills/good-skill/inner/SKILL.md"

run_case "shared: skill directory holds SKILL.md — pass" ok "" \
	"printf 'Supporting asset.\n' > skills/good-skill/reference.md"

run_case "shared: skill directory holds SKILL.md — fail" fail \
	"skills/good-skill/SKILL.md: missing" \
	"rm skills/good-skill/SKILL.md"

run_case "shared: no loose files in skills/ — pass" ok "" \
	"printf 'x\n' > skills/good-skill/notes.txt"

run_case "shared: no loose files in skills/ — fail" fail \
	"unexpected file in skills/" \
	"printf 'x\n' > skills/stray.md"

# --- load directories hold only loadable items -----------------------------
# agentbox mounts these directories onto discovery paths, so documentation in
# one is loaded as content: a commands/README.md becomes a /README command.

run_case "shared: load directories hold only loadable items — pass" ok "" \
	"printf '# skills\n' > docs/skills.md && printf '# more\n' > docs/notes.md"

run_case "shared: README in skills/ — fail" fail \
	"skills/README.md: load directories hold only loadable items" \
	"printf '# skills\n' > skills/README.md"

run_case "shared: README in agents/ — fail" fail \
	"agents/README.md: load directories hold only loadable items" \
	"printf '# agents\n' > agents/README.md"

run_case "shared: README in commands/ — fail" fail \
	"commands/README.md: load directories hold only loadable items" \
	"printf '# commands\n' > commands/README.md"

run_case "shared: README inside a skill directory — fail" fail \
	"skills/good-skill/README.md: load directories hold only loadable items" \
	"printf '# the skill\n' > skills/good-skill/README.md"

run_case "shared: nested README in a load directory — fail" fail \
	"commands/x/README.md: load directories hold only loadable items" \
	"mkdir commands/x && printf '# commands\n' > commands/x/README.md"

run_case "shared: lowercase readme in skills/ — fail" fail \
	"skills/readme.md: load directories hold only loadable items" \
	"printf '# skills\n' > skills/readme.md"

run_case "shared: lowercase readme in agents/ — fail" fail \
	"agents/readme.md: load directories hold only loadable items" \
	"printf '# agents\n' > agents/readme.md"

run_case "shared: lowercase readme in commands/ — fail" fail \
	"commands/readme.md: load directories hold only loadable items" \
	"printf '# commands\n' > commands/readme.md"

run_case "shared: load directories other than skills/ are optional — pass" ok "" \
	"rm -rf rules prompts agents commands"

run_case "shared: load directories other than skills/ are optional — fail" fail \
	"skills: missing" \
	"rm -rf skills"

run_case "shared: non-loadable file in a load directory — pass" ok "" \
	"printf -- '---\ndescription: A second command.\n---\n\nBody.\n' > commands/second.md"

run_case "shared: non-loadable file in a load directory — fail" fail \
	"agents/notes.txt: unexpected file in agents/" \
	"printf 'x\n' > agents/notes.txt"

# --- skill name == dir name ------------------------------------------------

run_case "shared: skill name == dir name — pass" ok "" \
	"mv skills/good-skill skills/renamed-skill && sed -i 's/^name: .*/name: renamed-skill/' skills/renamed-skill/SKILL.md"

run_case "shared: skill name == dir name — fail" fail \
	"frontmatter 'name' is 'other-name' but the directory is 'good-skill'" \
	"sed -i 's/^name: .*/name: other-name/' skills/good-skill/SKILL.md"

# --- skill name pattern ----------------------------------------------------

run_case "shared: skill name pattern — pass" ok "" \
	"mv skills/good-skill skills/a9-b-c && sed -i 's/^name: .*/name: a9-b-c/' skills/a9-b-c/SKILL.md"

run_case "shared: skill name pattern — fail" fail \
	"invalid skill directory name" \
	"mv skills/good-skill skills/Bad_Name && sed -i 's/^name: .*/name: Bad_Name/' skills/Bad_Name/SKILL.md"

# --- documented frontmatter keys pass, unknown keys warn -------------------
# The key set itself is an allowed difference; that documented keys pass and
# unknown keys warn is shared.

run_case "shared: documented frontmatter keys — pass" ok "" \
	"printf -- '---\nname: good-skill\ndescription: Uses every documented key.\nlicense: MIT\nallowed-tools: Read, Bash\nmodel: claude-opus-5\ndisable-model-invocation: true\nhide: true\nglobs: [\"*.ts\"]\nalwaysApply: false\nenabled: true\n---\n\nBody.\n' > skills/good-skill/SKILL.md"

run_case "shared: unknown frontmatter key warns — fail" warn \
	"unknown frontmatter key 'descriptionn'" \
	"printf -- '---\nname: good-skill\ndescription: A valid skill.\ndescriptionn: typo\n---\n\nBody.\n' > skills/good-skill/SKILL.md"

run_case "shared: skill frontmatter required keys — pass" ok "" \
	"printf -- '---\nname: good-skill\ndescription: Has both required keys.\n---\n\nBody.\n' > skills/good-skill/SKILL.md"

run_case "shared: skill frontmatter required keys — fail" fail \
	"missing required key 'description'" \
	"printf -- '---\nname: good-skill\n---\n\nBody.\n' > skills/good-skill/SKILL.md"

run_case "shared: skill frontmatter present — fail" fail \
	"no frontmatter (a '---' delimited block is required)" \
	"printf '# no frontmatter\n' > skills/good-skill/SKILL.md"

run_case "shared: frontmatter parses — pass" ok "" \
	"printf -- '---\nname: good-skill\ndescription: >\n  A folded block scalar.\n---\n\nBody.\n' > skills/good-skill/SKILL.md"

run_case "shared: frontmatter parses — fail" fail \
	"the frontmatter is never closed" \
	"printf -- '---\nname: good-skill\ndescription: Unclosed.\n\nBody.\n' > skills/good-skill/SKILL.md"

# --- no symlinks in tracked paths ------------------------------------------

run_case "shared: no symlinks in tracked paths — pass" ok "" \
	"cp AGENTS.md skills/good-skill/ref.md"

run_case "shared: no symlinks in tracked paths — fail" fail \
	"skills/good-skill/ref.md: symlink" \
	"ln -s ../../AGENTS.md skills/good-skill/ref.md"

# --- no files over 1 MB in tracked paths -----------------------------------

run_case "shared: no files over 1 MB in tracked paths — pass" ok "" \
	"dd if=/dev/zero of=tools/at-limit.bin bs=1024 count=1024"

run_case "shared: no files over 1 MB in tracked paths — fail" fail \
	"over the 1048576-byte limit" \
	"dd if=/dev/zero of=tools/big.bin bs=1024 count=1100"

# --- .env*, *.pem, id_* are errors anywhere, .dev/ included ----------------

run_case "shared: .env* is an error anywhere — pass" ok "" \
	"printf 'x\n' > tools/envrc && printf 'x\n' > tools/dotenv.md"

run_case "shared: .env* is an error anywhere — fail" fail \
	"name matches '.env*'" \
	"touch tools/.env.local"

run_case "shared: .env* is an error in .dev — fail" fail \
	".dev/docs/.env: name matches '.env*'" \
	"mkdir -p .dev/docs && touch .dev/docs/.env"

run_case "shared: *.pem is an error anywhere — pass" ok "" \
	"printf 'x\n' > tools/pem-notes.md"

run_case "shared: *.pem is an error anywhere — fail" fail \
	"name matches '*.pem'" \
	"touch tools/cert.pem"

run_case "shared: *.pem is an error in .dev — fail" fail \
	".dev/key.pem: name matches '*.pem'" \
	"mkdir -p .dev && touch .dev/key.pem"

run_case "shared: id_* is an error anywhere — pass" ok "" \
	"printf 'x\n' > tools/identity.md"

run_case "shared: id_* is an error anywhere — fail" fail \
	"name matches 'id_*'" \
	"touch tools/id_rsa"

run_case "shared: id_* is an error in .dev — fail" fail \
	".dev/id_ed25519: name matches 'id_*'" \
	"mkdir -p .dev && touch .dev/id_ed25519"

run_case "shared: *.key is an error anywhere — pass" ok "" \
	"printf 'x\n' > tools/keyring.md"

run_case "shared: *.key is an error anywhere — fail" fail \
	"name matches '*.key'" \
	"touch tools/server.key"

run_case "shared: *.key is an error in .dev — fail" fail \
	".dev/server.key: name matches '*.key'" \
	"mkdir -p .dev && touch .dev/server.key"

# A path component named secrets is masked whole by agentbox; a name that only contains it is fine.
run_case "shared: secrets/ is an error anywhere — pass" ok "" \
	"mkdir -p tools/my-secrets && printf 'x\n' > tools/my-secrets/notes.md"

run_case "shared: secrets/ is an error anywhere — fail" fail \
	"tools/secrets: a directory named secrets/" \
	"mkdir -p tools/secrets && printf 'x\n' > tools/secrets/notes.md"

run_case "shared: secrets/ is an error in .dev — fail" fail \
	".dev/secrets: a directory named secrets/" \
	"mkdir -p .dev/secrets"

# --- .dev/ is otherwise skipped --------------------------------------------

run_case "shared: .dev/ is otherwise skipped — pass" ok "" \
	"mkdir -p .dev/docs .dev/show-me && printf 'x\n' > .dev/docs/note.md && dd if=/dev/zero of=.dev/big.bin bs=1024 count=4096 && ln -s ../AGENTS.md .dev/link.md"

run_case "shared: .dev/ is otherwise skipped — fail" fail \
	"dev-notes: unexpected top-level entry" \
	"mkdir dev-notes && printf 'x\n' > dev-notes/note.md"

# --- plugins.toml format ---------------------------------------------------

run_case "shared: plugins.toml format — pass" ok "" \
	"printf '[[plugin]]\nid = \"egm@egm\"\nmarketplace = \"egm\"\nsource = \"google/elephant-goldfish-model\"\nref = \"464db031e7dd1b9a79803ac8ea45f55c7c20c5bc\"\n' > plugins.toml"

run_case "shared: plugins.toml format — fail" fail \
	"does not parse as TOML" \
	"printf 'this is not toml =\n' > plugins.toml"

run_case "shared: plugins.toml present — fail" fail \
	"plugins.toml: missing" \
	"rm plugins.toml"

run_case "shared: plugin ref is a pinned sha — pass" ok "" \
	"sed -i 's/^ref = .*/ref = \"0123456789abcdef0123456789abcdef01234567\"/' plugins.toml"

run_case "shared: plugin ref is a pinned sha — fail" fail \
	"must be a 40-character lowercase commit sha" \
	"sed -i 's/^ref = .*/ref = \"main\"/' plugins.toml"

run_case "shared: plugin id is name@marketplace — fail" fail \
	"id must be '<name>@<marketplace>'" \
	"sed -i 's/^id = .*/id = \"egm\"/' plugins.toml"

run_case "shared: plugin id is unique — fail" fail \
	"duplicate id" \
	"cat plugins.toml plugins.toml > p.tmp && mv p.tmp plugins.toml"

run_case "shared: plugin id matches its marketplace — fail" fail \
	"but the id says 'egm'" \
	"sed -i 's/^marketplace = .*/marketplace = \"other\"/' plugins.toml"

run_case "shared: plugin name charset — fail" fail \
	"invalid plugin name 'bad_name'" \
	"sed -i 's/^id = .*/id = \"bad_name@egm\"/' plugins.toml"

run_case "shared: plugin keys required — fail" fail \
	"missing required key 'source'" \
	"sed -i '/^source = /d' plugins.toml"

# Unknown keys and sections are errors, as for the launcher (plugins.py _check_keys, parse): a typo'd key
# is an entry with a value missing, and a misspelt section is a set of entries nothing installs.
run_case "shared: plugin keys known — fail" fail \
	"plugin 'egm@egm': unknown key 'name' (allowed: id, marketplace, source, ref)" \
	"printf 'name = \"egm@egm\"\n' >> plugins.toml"

run_case "shared: plugins.toml unknown section — fail" fail \
	"unknown section [[plugins]]" \
	"sed -i 's/^\[\[plugin\]\]/[[plugins]]/' plugins.toml"

# source: GitHub shorthand or a plain https URL, never a local path or a URL with credentials (the
# launcher's SHORTHAND and _check_https rules).
run_case "shared: plugin source is shorthand or https — pass" ok "" \
	"sed -i 's|^source = .*|source = \"https://github.com/google/elephant-goldfish-model.git\"|' plugins.toml"

run_case "shared: plugin source is shorthand or https — fail" fail \
	"source '/tmp/egm' is neither GitHub shorthand" \
	"sed -i 's|^source = .*|source = \"/tmp/egm\"|' plugins.toml"

run_case "shared: plugin source is shorthand or https — fail (credentials)" fail \
	"carries credentials" \
	"sed -i 's|^source = .*|source = \"https://user:pw@github.com/google/egm.git\"|' plugins.toml"

run_case "shared: plugin source is shorthand or https — fail (dot-dot)" fail \
	"is not a plain https URL" \
	"sed -i 's|^source = .*|source = \"https://github.com/google/../egm.git\"|' plugins.toml"

# [[npm]] and [[repo]]: the two other ways an OMP plugin arrives (agentbox's plugins.py). Accepted
# silently when they follow the launcher's rules, so this repo's own plugins.toml checks clean.
NPM_OK='[[npm]]\nname = "@scope/pi-thing"\nversion = "1.2.3"\n'
REPO_OK='[[repo]]\nname = "mags-codedev"\nurl = "https://github.com/x/y.git"\nref = "0123456789abcdef0123456789abcdef01234567"\nextension_dir = "ext"\n'

run_case "omp: [[npm]] and [[repo]] are read, not unknown — pass" ok "" \
	"printf '$NPM_OK$REPO_OK' >> plugins.toml"

run_case "omp: npm version is exact — fail" fail \
	"version '^1.2.3' must be exact" \
	"printf '$NPM_OK' | sed 's/1.2.3/^1.2.3/' >> plugins.toml"

run_case "omp: npm name is a package name — fail" fail \
	"is not an npm package name" \
	"printf '$NPM_OK' | sed 's/@scope\/pi-thing/Bad Name/' >> plugins.toml"

run_case "omp: npm keys required — fail" fail \
	"missing required key 'version'" \
	"printf '$NPM_OK' | sed '/^version/d' >> plugins.toml"

run_case "omp: repo ref is a pinned sha — fail" fail \
	"ref 'main' must be a 40-character" \
	"printf '$REPO_OK' | sed 's/^ref = .*/ref = \"main\"/' >> plugins.toml"

run_case "omp: repo url is https — fail" fail \
	"must be a plain https:// URL" \
	"printf '$REPO_OK' | sed 's#https://#git://#' >> plugins.toml"

run_case "omp: repo url without credentials — fail" fail \
	"carries credentials" \
	"printf '$REPO_OK' | sed 's#https://#https://user:pw@#' >> plugins.toml"

run_case "omp: repo name is a plain directory name — fail" fail \
	"not 'node_modules'" \
	"printf '$REPO_OK' | sed 's/^name = .*/name = \"node_modules\"/' >> plugins.toml"

run_case "omp: npm and repo names are unique — fail" fail \
	"duplicate name" \
	"printf '$NPM_OK$REPO_OK' | sed 's/^name = \"mags-codedev\"/name = \"@scope\/pi-thing\"/' >> plugins.toml"

run_case "omp: unknown key in [[repo]] — fail" fail \
	"unknown key 'branch' (allowed: name, url, ref, extension_dir)" \
	"printf '$REPO_OK' | sed 's/^extension_dir = .*/branch = \"main\"/' >> plugins.toml"

run_case "omp: unknown key in [[npm]] — fail" fail \
	"unknown key 'verison' (allowed: name, version)" \
	"printf '$NPM_OK' | sed 's/^version = /verison = /' >> plugins.toml"

# extension_dir accepts what the launcher's _repo accepts: "." (the default) and nested relative paths;
# refuses absolute paths, a leading `..` and anything normpath would rewrite.
run_case "omp: repo extension_dir is a relative path inside the checkout — pass" ok "" \
	"printf '$REPO_OK' | sed 's|^extension_dir = .*|extension_dir = \".\"|' >> plugins.toml"

run_case "omp: repo extension_dir is a relative path inside the checkout — pass (nested)" ok "" \
	"printf '$REPO_OK' | sed 's|^extension_dir = .*|extension_dir = \"packages/ext\"|' >> plugins.toml"

run_case "omp: repo extension_dir is a relative path inside the checkout — fail (absolute)" fail \
	"extension_dir '/ext' must be a plain relative path inside the repo" \
	"printf '$REPO_OK' | sed 's|^extension_dir = .*|extension_dir = \"/ext\"|' >> plugins.toml"

run_case "omp: repo extension_dir is a relative path inside the checkout — fail (dot-dot)" fail \
	"extension_dir '../ext' must be a plain relative path inside the repo" \
	"printf '$REPO_OK' | sed 's|^extension_dir = .*|extension_dir = \"../ext\"|' >> plugins.toml"

run_case "omp: repo extension_dir is a relative path inside the checkout — fail (not normalised)" fail \
	"extension_dir 'a/../..' must be a plain relative path inside the repo" \
	"printf '$REPO_OK' | sed 's|^extension_dir = .*|extension_dir = \"a/../..\"|' >> plugins.toml"

run_case "omp: repo extension_dir is a relative path inside the checkout — fail (empty)" fail \
	"extension_dir must be a non-empty string" \
	"printf '$REPO_OK' | sed 's|^extension_dir = .*|extension_dir = \"\"|' >> plugins.toml"

# --- the Containerfile -----------------------------------------------------

run_case "shared: Containerfile ARG BASE then FROM \${BASE} — pass" ok "" \
	"true"

run_case "shared: Containerfile ARG BASE then FROM \${BASE} — fail" fail \
	"first instruction must be 'ARG BASE'" \
	"sed -i '1s/.*/ARG OTHER/' Containerfile"

run_case "shared: Containerfile FROM is pinned to \${BASE} — fail" fail \
	"second instruction must be 'FROM \${BASE}'" \
	"sed -i '2s|.*|FROM debian:bookworm|' Containerfile"

# Case-sensitive, as the launcher is: `ARG base` declares an argument FROM ${BASE} never reads.
run_case "shared: Containerfile ARG BASE then FROM \${BASE} — fail (lowercase arg base)" fail \
	"first instruction must be 'ARG BASE'" \
	"sed -i '1s/.*/ARG base/' Containerfile"

run_case "shared: Containerfile FROM is pinned to \${BASE} — fail (lowercase base)" fail \
	"second instruction must be 'FROM \${BASE}'" \
	"sed -i '2s|.*|FROM \${base}|' Containerfile"

run_case "shared: Containerfile sets no USER/ENTRYPOINT/CMD — pass" ok "" \
	"printf 'ENV PAGER=less\n' >> Containerfile"

run_case "shared: Containerfile sets no USER/ENTRYPOINT/CMD — fail" fail \
	"must not set USER" \
	"printf 'USER root\n' >> Containerfile"

run_case "shared: Containerfile sets no ENTRYPOINT — fail" fail \
	"must not set ENTRYPOINT" \
	"printf 'ENTRYPOINT [\"/bin/sh\"]\n' >> Containerfile"

run_case "shared: Containerfile sets no CMD — fail" fail \
	"must not set CMD" \
	"printf 'CMD [\"/bin/sh\"]\n' >> Containerfile"

run_case "shared: Containerfile downloads are checksum-verified — pass" ok "" \
	"printf 'RUN set -eux; curl -fsSL -o /tmp/x https://example.invalid/x.tar.gz; printf %%s 0000000000000000000000000000000000000000000000000000000000000000 | sha256sum -c -\n' >> Containerfile"

run_case "shared: Containerfile downloads are checksum-verified — fail" fail \
	"download is not checksum-verified" \
	"printf 'RUN curl -fsSL -o /tmp/x https://example.invalid/x.tar.gz\n' >> Containerfile"

run_case "shared: Containerfile downloads are checksum-verified — fail (ADD)" fail \
	"download is not checksum-verified" \
	"printf 'ADD https://example.invalid/x.tar.gz /tmp/x\n' >> Containerfile"

# Only RUN and ADD fetch: a URL in ENV or LABEL downloads nothing.
run_case "shared: Containerfile downloads are checksum-verified — pass (URL in ENV)" ok "" \
	"printf 'ENV DOCS_URL=https://example.invalid/docs\nLABEL org.opencontainers.image.source=https://example.invalid/repo\n' >> Containerfile"

run_case "shared: Containerfile is optional — pass" ok "" \
	"rm Containerfile"

# ===========================================================================
# omp-only rules: rules/ and prompts/ are harness directories, and the agent
# and command contracts are OMP's. No sibling case.
# ===========================================================================

run_case "omp: rules are *.md or *.mdc — pass" ok "" \
	"mv rules/example.md rules/example.mdc"

run_case "omp: rules are *.md or *.mdc — fail" fail \
	"unexpected file in rules/" \
	"printf 'x\n' > rules/notes.txt"

run_case "omp: rules/ is not recursive — fail" fail \
	"unexpected directory in rules/" \
	"mkdir rules/group && cp rules/example.md rules/group/nested.md"

run_case "omp: rule joins a bucket — pass" ok "" \
	"printf -- '---\nalwaysApply: true\n---\n\nBody.\n' > rules/example.md"

run_case "omp: rule joins a bucket — fail" fail \
	"joins no bucket" \
	"printf 'Just a body, no frontmatter.\n' > rules/example.md"

run_case "omp: rule interruptMode is valid — pass" ok "" \
	"printf -- '---\ndescription: A rule.\ninterruptMode: tool-only\n---\n\nBody.\n' > rules/example.md"

run_case "omp: rule interruptMode is valid — fail" fail \
	"invalid interruptMode 'sometimes'" \
	"printf -- '---\ndescription: A rule.\ninterruptMode: sometimes\n---\n\nBody.\n' > rules/example.md"

run_case "omp: agent name and description required — pass" ok "" \
	"printf -- '---\nname: example\ndescription: Has both.\n---\n\nBody.\n' > agents/example.md"

run_case "omp: agent name and description required — fail" fail \
	"agents/example.md: frontmatter is missing required key 'description'" \
	"printf -- '---\nname: example\n---\n\nBody.\n' > agents/example.md"

run_case "omp: agent name main and sub reserved — fail" fail \
	"which is reserved" \
	"sed -i 's/^name: .*/name: main/' agents/example.md"

run_case "omp: agent name matches its filename — fail" warn \
	"keep them equal" \
	"sed -i 's/^name: .*/name: other/' agents/example.md"

run_case "omp: commands/ is not recursive — fail" fail \
	"unexpected directory in commands/" \
	"mkdir commands/group && cp commands/example.md commands/group/nested.md"

run_case "omp: command has a description — fail" warn \
	"autocomplete falls back to the first body line" \
	"printf 'Body only.\n' > commands/example.md"

run_case "omp: prompts are *.md — fail" fail \
	"unexpected file in prompts/" \
	"printf 'x\n' > prompts/example.yaml"

run_case "omp: README in rules/ — fail" fail \
	"rules/README.md: load directories hold only loadable items" \
	"printf '# rules\n' > rules/README.md"

run_case "omp: README in prompts/ — fail" fail \
	"prompts/README.md: load directories hold only loadable items" \
	"printf '# prompts\n' > prompts/README.md"

run_case "omp: lowercase readme in rules/ — fail" fail \
	"rules/readme.md: load directories hold only loadable items" \
	"printf '# rules\n' > rules/readme.md"

run_case "omp: lowercase readme in prompts/ — fail" fail \
	"prompts/readme.md: load directories hold only loadable items" \
	"printf '# prompts\n' > prompts/readme.md"

run_case "omp: build.sh is executable — fail" warn \
	"build.sh: warning: not executable" \
	"chmod -x build.sh"

# ===========================================================================
# seed/ (shared): keyless copies of what agentbox reads from ~/.config/agentbox/<agent>/
# ===========================================================================

run_case "shared: seed/ holds keyless config — pass" ok "" \
	"mkdir seed && printf 'providers:\n  llama-cpp:\n    baseUrl: http://10.0.0.2:8080/v1\n' > seed/models.yml"

run_case "shared: seed/ with a subdirectory — fail" fail \
	"seed/ holds files only" \
	"mkdir -p seed/sub"

run_case "shared: seed/ file holding a credential — fail" fail \
	"looks like a credential" \
	"mkdir seed && printf 'mcp:\n  token: ghp_realvalue\n' > seed/config.yml"

run_case "shared: seed/ models.yml with any apiKey — fail" fail \
	"apiKey\` is refused in the model seed" \
	"mkdir seed && printf 'providers:\n  openai:\n    apiKey: none\n' > seed/models.yml"

run_case "shared: seed/ env reference is not a credential — pass" ok "" \
	"mkdir seed && printf '{\"env\": {\"TOKEN\": \"\${X}\"}}\n' > seed/mcp.json"

# ===========================================================================
# build.sh exit codes (shared)
# ===========================================================================

host_only_refuses() {
	local sub="$1" out rc
	out="$(AGENTBOX_SESSION=1 "$BUILD" "$sub" 2>&1)"
	rc=$?
	if [[ $rc -eq 2 ]] && grep -qF "is host only" <<<"$out"; then
		pass "shared: build.sh $sub exits 2 inside a session — fail"
	else
		fail "shared: build.sh $sub exits 2 inside a session — fail" "expected exit 2 and a refusal, got exit $rc:
$out"
	fi
}

host_only_refuses deploy
host_only_refuses install
host_only_refuses all

exit_code_case() {
	local label="$1" want="$2" needle="$3"
	shift 3
	local out rc
	out="$("$@" 2>&1)"
	rc=$?
	if [[ $rc -eq $want ]] && grep -qF -- "$needle" <<<"$out"; then
		pass "$label"
	else
		fail "$label" "expected exit $want containing '$needle', got exit $rc:
$out"
	fi
}

exit_code_case "shared: build.sh check exits 0 on this repository — pass" 0 \
	"check: ok" \
	"$BUILD" check

# build.sh check returns the checker's exit status, so the checker's 1 is build.sh's.
exit_code_case "shared: build.sh check exits 1 when check fails — fail" 1 \
	"unexpected top-level entry" \
	env "BROKEN=1" bash -c 'fx="$1"; mkdir -p "$fx" && cp -a "$2"/. "$fx"/ && printf "x\n" > "$fx/notes.md" && python3 "$fx/tools/check.py" --root "$fx"' _ "$WORK/repo-copy" "$REPO_DIR"

exit_code_case "shared: build.sh status exits 0 — pass" 0 \
	"plugins:" \
	"$BUILD" status

# status lists every kind agentbox installs, not only the marketplace ones (this repo has one of each).
exit_code_case "omp: build.sh status lists [[npm]] entries — pass" 0 \
	"  pi-rules  npm  0.1.1" \
	"$BUILD" status

exit_code_case "omp: build.sh status lists [[repo]] entries — pass" 0 \
	"  pi-session-stats  https://github.com/TimothyStephens/pi-session-stats.git  9c7a0c2dd190" \
	"$BUILD" status

exit_code_case "shared: build.sh status reports a missing live profile as clonable — pass" 0 \
	"does not exist yet; ./build.sh deploy will clone" \
	env AGENTBOX_OMP_PROFILE="$WORK/no-such-profile" "$BUILD" status

exit_code_case "shared: build.sh status lists the seeds — pass" 0 \
	"seeds:" \
	env AGENTBOX_OMP_PROFILE="$WORK/no-such/profile" "$BUILD" status

# Against a copy of the repo with no seed/: seed/ is gitignored, so the real checkout may hold a local
# models.yml (the host's keyless copy), which would make this a test of the host rather than of status.
exit_code_case "omp: build.sh status names a seed agentbox expects and nobody has — pass" 0 \
	"models.yml: MISSING" \
	bash -c 'mkdir -p "$2" && cp -a "$1"/. "$2"/ && rm -rf "$2/seed" && AGENTBOX_OMP_PROFILE="$2/no-such/profile" "$2/build.sh" status' _ "$REPO_DIR" "$WORK/no-seed-repo"

exit_code_case "shared: build.sh exits 2 on an unknown command — fail" 2 \
	"unknown command" \
	"$BUILD" frobnicate

# A plugins.toml that does not parse must not leave status reading as fine.
exit_code_case "shared: build.sh status fails when plugins.toml does not parse — fail" 1 \
	"(plugins.toml does not parse)" \
	bash -c 'mkdir -p "$2" && cp -a "$1"/. "$2"/ && rm -rf "$2/.git" && printf "name = [[\n" > "$2/plugins.toml" && AGENTBOX_OMP_PROFILE="$2/no-such/profile" "$2/build.sh" status' _ "$REPO_DIR" "$WORK/broken-plugins-repo"

# deploy itself is host only, so scratch repositories stand in for origin, the live clone and this checkout
# and the functions are called directly from a sourced build.sh.
git_q() { git -c user.name=t -c user.email=t@t.invalid -c init.defaultBranch=main "$@" >/dev/null 2>&1; }
deploy_scratch() {  # deploy_scratch DIR -> DIR/origin.git, DIR/repo and DIR/live, all at the same commit
	local d="$1"
	mkdir -p "$d" && git_q init --bare "$d/origin.git" && git_q clone "$d/origin.git" "$d/repo" \
		&& printf 'one\n' > "$d/repo/f" && git_q -C "$d/repo" add f && git_q -C "$d/repo" commit -m one \
		&& git_q -C "$d/repo" push origin HEAD && git_q clone "$d/origin.git" "$d/live"
}
d="$WORK/deploy-ok"; deploy_scratch "$d"
exit_code_case "shared: build.sh deploy accepts a live clone at this repo's HEAD — pass" 0 "" \
	bash -c 'source "$1"; live_matches_repo "$2" "$3"' _ "$BUILD" "$d/live" "$d/repo"
d="$WORK/deploy-unpushed"; deploy_scratch "$d"
printf 'two\n' > "$d/repo/f"; git_q -C "$d/repo" commit -am two
exit_code_case "shared: build.sh deploy refuses when this repo is unpushed — fail" 1 "push this repo first" \
	bash -c 'source "$1"; git -C "$2" pull --ff-only -q && live_matches_repo "$2" "$3"' _ \
	"$BUILD" "$d/live" "$d/repo"
d="$WORK/deploy-diverged"; deploy_scratch "$d"
printf 'live\n' > "$d/live/f"; git_q -C "$d/live" commit -am live-edit
exit_code_case "shared: build.sh deploy treats a live clone with its own commits as diverged — fail" 1 "diverged" \
	bash -c 'source "$1"; LIVE="$2"; REPO="$3"; live_is_clean_clone || { printf "%s\n" "$REASON"; exit 1; }' _ \
	"$BUILD" "$d/live" "$d/repo"

# NOT COVERED: exit 3 (ab lacks the command). install refuses with exit 2
# before it looks for ab whenever /run/agentbox exists, so this path is only
# reachable from a host shell. Reported, not excused.

# --- the parity promise ------------------------------------------------------
# Every "shared:" label in this file exists in the sibling repo's run.sh, compared without a trailing
# "(detail)". This run checks this file against the sibling; the sibling's own run checks the other way.

sibling_labels() {
	local label="shared: every shared case label exists in the sibling repo — pass"
	local missing=() stem
	if [[ ! -f "$SIBLING" ]]; then
		printf 'skip  %s (no sibling checkout at %s)\n' "$label" "$SIBLING"
		return 0
	fi
	while IFS= read -r stem; do
		grep -qF -- "$stem" "$SIBLING" || missing+=("$stem")
	done < <(grep -o '"shared:[[:space:]][^"]*"' "$TESTS_DIR/run.sh" \
		| sed -e 's/^"//' -e 's/"$//' -e 's/ ([^()]*)$//' | sort -u)
	if (( ${#missing[@]} == 0 )); then
		pass "$label"
	else
		fail "$label" "missing in $SIBLING:
$(printf '%s\n' "${missing[@]}")"
	fi
}
sibling_labels

# --- summary ----------------------------------------------------------------

printf '\n%d passed, %d failed\n' "$PASSED" "$FAILED"
[[ $FAILED -eq 0 ]]
