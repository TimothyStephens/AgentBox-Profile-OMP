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
# Case names are the parity surface. Per PARITY.md every shared rule has a pass
# case and a fail case, and those names must be identical in
# agentbox-profile-claude. So:
#
#   shared: ...   a rule PARITY.md calls shared. Same name in both repos.
#   omp:    ...   a rule this harness forces. Has no sibling.
#
# Exits 0 only if every case passes.
#
set -uo pipefail

TESTS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname -- "$TESTS_DIR")"
CHECK="$REPO_DIR/tools/check.py"
BUILD="$REPO_DIR/build.sh"

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

	printf '# Working with Tim\n\nShort enough.\n' >"$fx/AGENTS.md"
	printf '# profile\n' >"$fx/README.md"
	printf '# parity\n' >"$fx/PARITY.md"
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
# shared rules (PARITY.md). Same names in agentbox-profile-claude.
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
	"printf '# Working with Tim\n\nRules.\n' > AGENTS.md"

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

run_case "shared: plugin id matches its marketplace — fail" fail \
	"but the id says 'egm'" \
	"sed -i 's/^marketplace = .*/marketplace = \"other\"/' plugins.toml"

run_case "shared: plugin name charset — fail" fail \
	"invalid plugin name 'bad_name'" \
	"sed -i 's/^id = .*/id = \"bad_name@egm\"/' plugins.toml"

run_case "shared: plugin keys required — fail" fail \
	"missing required key 'source'" \
	"sed -i '/^source = /d' plugins.toml"

# --- the Containerfile -----------------------------------------------------

run_case "shared: Containerfile ARG BASE then FROM \${BASE} — pass" ok "" \
	"true"

run_case "shared: Containerfile ARG BASE then FROM \${BASE} — fail" fail \
	"first instruction must be 'ARG BASE'" \
	"sed -i '1s/.*/ARG OTHER/' Containerfile"

run_case "shared: Containerfile FROM is pinned to \${BASE} — fail" fail \
	"second instruction must be 'FROM \${BASE}'" \
	"sed -i '2s|.*|FROM debian:bookworm|' Containerfile"

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

check_repo() {
	local out rc
	out="$("$BUILD" check 2>&1)"
	rc=$?
	if [[ $rc -eq 0 && -z "$out" ]]; then
		pass "shared: build.sh check exits 0 on this repository — pass"
	else
		fail "shared: build.sh check exits 0 on this repository — pass" "exit $rc:
$out"
	fi
}
check_repo

# build.sh check execs the checker, so the checker's exit 1 is build.sh's.
exit_code_case "shared: build.sh check exits 1 when check fails — fail" 1 \
	"unexpected top-level entry" \
	env "BROKEN=1" bash -c 'fx="$1"; mkdir -p "$fx" && cp -a "$2"/. "$fx"/ && printf "x\n" > "$fx/notes.md" && python3 "$fx/tools/check.py" --root "$fx"' _ "$WORK/repo-copy" "$REPO_DIR"

status_runs() {
	local out rc
	out="$("$BUILD" status 2>&1)"
	rc=$?
	if [[ $rc -eq 0 ]] && grep -qF "plugin pins:" <<<"$out"; then
		pass "shared: build.sh status exits 0 — pass"
	else
		fail "shared: build.sh status exits 0 — pass" "exit $rc:
$out"
	fi
}
status_runs

# NOT COVERED: exit 3 (ab lacks the command). install refuses with exit 2
# before it looks for ab whenever /run/agentbox exists, so this path is only
# reachable from a host shell. Reported, not excused.

# --- summary ----------------------------------------------------------------

printf '\n%d passed, %d failed\n' "$PASSED" "$FAILED"
[[ $FAILED -eq 0 ]]
