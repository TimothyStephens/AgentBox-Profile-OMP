#!/usr/bin/env bash
#
# Tests for tools/check.py and build.sh.
#
#   ./tests/run.sh
#
# Each case builds a known-good profile fixture in a temp directory, applies
# one mutation, and asserts that check either passes, fails with a specific
# message, or warns with a specific message. The last cases assert that the
# HOST ONLY build.sh commands refuse inside an agentbox session, and that
# `./build.sh check` passes on this repository.
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
		"$fx"/commands "$fx"/tools "$fx"/tests

	printf '# Standing rules\n\nShort enough.\n' >"$fx/AGENTS.md"
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

# --- layout -----------------------------------------------------------------

run_case "good fixture passes with no output" ok "" "true"

run_case "unexpected top-level entry is rejected" fail \
	"notes.md: unexpected top-level entry" \
	"printf 'x\n' > notes.md"

run_case "missing AGENTS.md is rejected" fail \
	"AGENTS.md: missing" \
	"rm AGENTS.md"

run_case "long AGENTS.md warns" warn \
	"lines, over 150" \
	"seq 200 > AGENTS.md"

run_case "non-executable build.sh warns" warn \
	"build.sh: warning: not executable" \
	"chmod -x build.sh"

# --- skills -----------------------------------------------------------------

run_case "skill directory name outside the charset is rejected" fail \
	"invalid skill directory name" \
	"mv skills/good-skill skills/Bad_Name && sed -i 's/^name: .*/name: Bad_Name/' skills/Bad_Name/SKILL.md"

run_case "skill directory without SKILL.md is rejected" fail \
	"skills/good-skill/SKILL.md: missing" \
	"rm skills/good-skill/SKILL.md"

run_case "skill without a description is rejected" fail \
	"missing required key 'description'" \
	"printf -- '---\nname: good-skill\n---\n\nBody.\n' > skills/good-skill/SKILL.md"

run_case "skill without a name is rejected" fail \
	"missing required key 'name'" \
	"printf -- '---\ndescription: Has no name.\n---\n\nBody.\n' > skills/good-skill/SKILL.md"

run_case "skill name disagreeing with its directory is rejected" fail \
	"frontmatter 'name' is 'other-name' but the directory is 'good-skill'" \
	"sed -i 's/^name: .*/name: other-name/' skills/good-skill/SKILL.md"

run_case "nested skill directory is rejected" fail \
	"nested skill directory" \
	"mkdir -p skills/good-skill/inner && cp skills/good-skill/SKILL.md skills/good-skill/inner/SKILL.md"

run_case "loose file in skills/ is rejected" fail \
	"unexpected file in skills/" \
	"printf 'x\n' > skills/stray.md"

run_case "documented skill frontmatter keys are accepted" ok "" \
	"printf -- '---\nname: good-skill\ndescription: Uses every documented key.\nlicense: MIT\nallowed-tools: Read, Bash\nmodel: claude-opus-5\ndisable-model-invocation: true\nhide: true\nglobs: [\"*.ts\"]\nalwaysApply: false\nenabled: true\n---\n\nBody.\n' > skills/good-skill/SKILL.md"

run_case "unknown skill frontmatter key warns but does not fail" warn \
	"unknown frontmatter key 'descriptionn'" \
	"printf -- '---\nname: good-skill\ndescription: A valid skill.\ndescriptionn: typo\n---\n\nBody.\n' > skills/good-skill/SKILL.md"

run_case "unclosed frontmatter is rejected" fail \
	"the frontmatter is never closed" \
	"printf -- '---\nname: good-skill\ndescription: Unclosed.\n\nBody.\n' > skills/good-skill/SKILL.md"

# --- rules ------------------------------------------------------------------

run_case "non-markdown file in rules/ is rejected" fail \
	"unexpected file in rules/" \
	"printf 'x\n' > rules/notes.txt"

run_case "rule in a subdirectory is rejected" fail \
	"unexpected directory in rules/" \
	"mkdir rules/group && cp rules/example.md rules/group/nested.md"

run_case "unaddressable rule is rejected" fail \
	"joins no bucket" \
	"printf 'Just a body, no frontmatter.\n' > rules/example.md"

run_case "invalid interruptMode is rejected" fail \
	"invalid interruptMode 'sometimes'" \
	"printf -- '---\ndescription: A rule.\ninterruptMode: sometimes\n---\n\nBody.\n' > rules/example.md"

run_case "mdc rules are accepted" ok "" \
	"mv rules/example.md rules/example.mdc"

run_case "always-apply rule with no description is accepted" ok "" \
	"printf -- '---\nalwaysApply: true\n---\n\nBody.\n' > rules/example.md"

# --- agents -----------------------------------------------------------------

run_case "agent without a description is rejected" fail \
	"agents/example.md: frontmatter is missing required key 'description'" \
	"printf -- '---\nname: example\n---\n\nBody.\n' > agents/example.md"

run_case "agent using the reserved name main is rejected" fail \
	"which is reserved" \
	"sed -i 's/^name: .*/name: main/' agents/example.md"

run_case "agent name disagreeing with its filename warns" warn \
	"keep them equal" \
	"sed -i 's/^name: .*/name: other/' agents/example.md"

# --- commands and prompts ---------------------------------------------------

run_case "command in a subdirectory is rejected" fail \
	"unexpected directory in commands/" \
	"mkdir commands/group && cp commands/example.md commands/group/nested.md"

run_case "command without a description warns" warn \
	"autocomplete falls back to the first body line" \
	"printf 'Body only.\n' > commands/example.md"

run_case "non-markdown file in prompts/ is rejected" fail \
	"unexpected file in prompts/" \
	"printf 'x\n' > prompts/example.yaml"

# --- plugins.toml -----------------------------------------------------------

run_case "missing plugins.toml is rejected" fail \
	"plugins.toml: missing" \
	"rm plugins.toml"

run_case "unparseable plugins.toml is rejected" fail \
	"does not parse as TOML" \
	"printf 'this is not toml =\n' > plugins.toml"

run_case "unpinned plugin ref is rejected" fail \
	"must be a 40-character lowercase commit sha" \
	"sed -i 's/^ref = .*/ref = \"main\"/' plugins.toml"

run_case "plugin marketplace disagreeing with its id is rejected" fail \
	"but the id says 'egm'" \
	"sed -i 's/^marketplace = .*/marketplace = \"other\"/' plugins.toml"

run_case "plugin name outside the charset is rejected" fail \
	"invalid plugin name 'bad_name'" \
	"sed -i 's/^id = .*/id = \"bad_name@egm\"/' plugins.toml"

run_case "plugin missing its source is rejected" fail \
	"missing required key 'source'" \
	"sed -i '/^source = /d' plugins.toml"

# --- Containerfile ----------------------------------------------------------

run_case "Containerfile not starting with ARG BASE is rejected" fail \
	"first instruction must be 'ARG BASE'" \
	"sed -i '1s/.*/ARG OTHER/' Containerfile"

run_case "Containerfile not pinned to FROM \${BASE} is rejected" fail \
	"second instruction must be 'FROM \${BASE}'" \
	"sed -i '2s|.*|FROM debian:bookworm|' Containerfile"

run_case "Containerfile setting USER is rejected" fail \
	"must not set USER" \
	"printf 'USER root\n' >> Containerfile"

run_case "Containerfile setting ENTRYPOINT is rejected" fail \
	"must not set ENTRYPOINT" \
	"printf 'ENTRYPOINT [\"/bin/sh\"]\n' >> Containerfile"

run_case "Containerfile setting CMD is rejected" fail \
	"must not set CMD" \
	"printf 'CMD [\"/bin/sh\"]\n' >> Containerfile"

run_case "unverified download in the Containerfile is rejected" fail \
	"download is not checksum-verified" \
	"printf 'RUN curl -fsSL -o /tmp/x https://example.invalid/x.tar.gz\n' >> Containerfile"

run_case "absent Containerfile is accepted" ok "" \
	"rm Containerfile"

# --- hygiene ----------------------------------------------------------------

run_case "symlink is rejected" fail \
	"skills/good-skill/ref.md: symlink" \
	"ln -s ../../AGENTS.md skills/good-skill/ref.md"

run_case "file over 1 MB is rejected" fail \
	"over the 1048576-byte limit" \
	"dd if=/dev/zero of=tools/big.bin bs=1024 count=1100"

run_case "file named like a private key is rejected" fail \
	"name matches 'id_*'" \
	"touch tools/id_rsa"

run_case "file named like an env file is rejected" fail \
	"name matches '.env*'" \
	"touch tools/.env.local"

run_case "pem file is rejected" fail \
	"name matches '*.pem'" \
	"touch tools/cert.pem"

# --- build.sh ---------------------------------------------------------------

host_only_refuses() {
	local sub="$1" out rc
	out="$(AGENTBOX_SESSION=1 "$BUILD" "$sub" 2>&1)"
	rc=$?
	if [[ $rc -eq 2 ]] && grep -qF "is host only" <<<"$out"; then
		pass "build.sh $sub refuses inside an agentbox session"
	else
		fail "build.sh $sub refuses inside an agentbox session" "expected exit 2 and a refusal, got exit $rc:
$out"
	fi
}

host_only_refuses deploy
host_only_refuses install
host_only_refuses all

check_repo() {
	local out rc
	out="$("$BUILD" check 2>&1)"
	rc=$?
	if [[ $rc -eq 0 ]]; then
		pass "./build.sh check passes on this repository"
	else
		fail "./build.sh check passes on this repository" "exit $rc:
$out"
	fi
}
check_repo

status_runs() {
	local out rc
	out="$("$BUILD" status 2>&1)"
	rc=$?
	if [[ $rc -eq 0 ]] && grep -qF "plugin pins:" <<<"$out"; then
		pass "./build.sh status reports without failing"
	else
		fail "./build.sh status reports without failing" "exit $rc:
$out"
	fi
}
status_runs

# --- summary ----------------------------------------------------------------

printf '\n%d passed, %d failed\n' "$PASSED" "$FAILED"
[[ $FAILED -eq 0 ]]
