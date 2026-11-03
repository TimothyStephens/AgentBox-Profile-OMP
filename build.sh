#!/usr/bin/env bash
#
# Build/deploy driver for Tim's agentbox OMP profile.
#
#   ./build.sh check     offline validation of this repository
#   ./build.sh status    live profile vs this repo's HEAD, plugin pins, ab
#   ./build.sh deploy    HOST ONLY: git pull --ff-only into the live profile
#   ./build.sh install   HOST ONLY: ab profile install omp (+ ab image build)
#   ./build.sh all       check, then deploy, then install
#
# Exit status:
#   0  success
#   1  problems found, or a command failed
#   2  a HOST ONLY command was refused (running inside an agentbox session)
#   3  the `ab` CLI is missing a command this script needs
#
set -euo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# The live profile is a git clone of this repo that agentbox reads. Overridable
# for tests only; Tim's real path is the default.
LIVE_DIR="${AGENTBOX_OMP_PROFILE:-$HOME/.config/agentbox/omp/profile}"
PROFILE_NAME="omp"

EXIT_PROBLEMS=1
EXIT_REFUSED=2
EXIT_NO_AB=3

say() { printf '%s\n' "$*"; }
err() { printf '%s\n' "$*" >&2; }

die() {
	err "$1"
	exit "${2:-$EXIT_PROBLEMS}"
}

# --- host-only guard --------------------------------------------------------

# deploy and install touch the host's live profile and run the host's podman.
# Inside an agentbox session neither is reachable, and the live profile is
# deliberately outside the grant, so refuse rather than half-doing it.
require_host() {
	local what="$1"
	local -a reasons=()
	[[ -n "${AGENTBOX_SESSION:-}" ]] && reasons+=("AGENTBOX_SESSION is set")
	[[ -e /run/agentbox ]] && reasons+=("/run/agentbox exists")
	if ((${#reasons[@]} > 0)); then
		local joined
		joined="$(
			IFS=', '
			printf '%s' "${reasons[*]}"
		)"
		err "refusing: '$what' is host only, and this looks like an agentbox session ($joined)."
		err "The live profile at $LIVE_DIR is outside the grant on purpose."
		err "Run '$0 $what' from a host shell instead."
		exit "$EXIT_REFUSED"
	fi
}

# --- ab availability --------------------------------------------------------

AB_HELP=""
AB_HELP_LOADED=0

# Collect `ab`'s help text once. Only --help/help forms are run: never a bare
# subcommand, which could do real work.
load_ab_help() {
	((AB_HELP_LOADED)) && return 0
	AB_HELP_LOADED=1
	command -v ab >/dev/null 2>&1 || return 0
	AB_HELP="$(
		{
			ab --help 2>&1 || true
			ab help 2>&1 || true
			ab profile --help 2>&1 || true
			ab image --help 2>&1 || true
		} || true
	)"
}

# Heuristic: does ab's help text mention this subcommand word? `ab` is still
# being built, so this only tells us whether the command is advertised.
ab_mentions() {
	load_ab_help
	[[ -n "$AB_HELP" ]] || return 1
	grep -qE "(^|[^[:alnum:]_-])$1([^[:alnum:]_-]|$)" <<<"$AB_HELP"
}

ab_ready() {
	command -v ab >/dev/null 2>&1
}

# --- live-profile identity --------------------------------------------------

root_commit() { git -C "$1" rev-list --max-parents=0 HEAD 2>/dev/null | tail -1; }

print_migration() {
	local origin stamp
	origin="$(git -C "$REPO_DIR" remote get-url origin 2>/dev/null || true)"
	[[ -n "$origin" ]] || origin="$REPO_DIR"
	stamp="$(date +%Y%m%d%H%M%S)"
	err ""
	err "One-time migration, on the host, from a shell you trust:"
	err ""
	err "  mv \"$LIVE_DIR\" \"$LIVE_DIR.bak.$stamp\""
	err "  git clone $origin \"$LIVE_DIR\""
	err ""
	err "Then copy back, by hand, anything in $LIVE_DIR.bak.$stamp that you still"
	err "need and that this repo does not already carry, and delete the backup."
	err "After that: $0 deploy && $0 install"
}

# --- commands ---------------------------------------------------------------

cmd_check() {
	command -v python3 >/dev/null 2>&1 || die "python3 is required for '$0 check'"
	python3 "$REPO_DIR/tools/check.py" --root "$REPO_DIR"
}

cmd_status() {
	local repo_head repo_root
	repo_head="$(git -C "$REPO_DIR" rev-parse HEAD 2>/dev/null || echo "(no commits)")"
	repo_root="$(root_commit "$REPO_DIR")"
	say "repo:          $REPO_DIR"
	say "  HEAD:        $repo_head"
	if [[ -n "$(git -C "$REPO_DIR" status --porcelain 2>/dev/null)" ]]; then
		say "  tree:        dirty (uncommitted changes are not deployed)"
	else
		say "  tree:        clean"
	fi

	say ""
	say "live profile:  $LIVE_DIR"
	if [[ ! -d "$LIVE_DIR" ]]; then
		say "  state:       absent (not installed)"
	elif ! git -C "$LIVE_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
		say "  state:       present but not a git clone — deploy will refuse"
	else
		local live_head live_root live_branch
		live_head="$(git -C "$LIVE_DIR" rev-parse HEAD 2>/dev/null || echo "(no commits)")"
		live_root="$(root_commit "$LIVE_DIR")"
		live_branch="$(git -C "$LIVE_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")"
		say "  HEAD:        $live_head"
		say "  branch:      $live_branch"
		if [[ -n "$(git -C "$LIVE_DIR" status --porcelain 2>/dev/null)" ]]; then
			say "  tree:        dirty — deploy will refuse"
		else
			say "  tree:        clean"
		fi
		if [[ -n "$repo_root" && "$live_root" != "$repo_root" ]]; then
			say "  state:       a different repository — deploy will refuse"
		elif [[ "$live_head" == "$repo_head" ]]; then
			say "  state:       at this repo's HEAD"
		else
			local behind
			behind="$(git -C "$REPO_DIR" rev-list --count "$live_head..$repo_head" 2>/dev/null || echo "?")"
			say "  state:       behind this repo by $behind commit(s) — run '$0 deploy'"
		fi
	fi

	say ""
	say "plugin pins:"
	if command -v python3 >/dev/null 2>&1; then
		python3 - "$REPO_DIR/plugins.toml" <<'PY'
import sys, tomllib
from pathlib import Path
path = Path(sys.argv[1])
if not path.is_file():
    print("  plugins.toml: absent")
    raise SystemExit(0)
try:
    data = tomllib.loads(path.read_text())
except Exception as exc:
    print(f"  plugins.toml: does not parse ({exc})")
    raise SystemExit(0)
entries = data.get("plugin") or []
if not entries:
    print("  (none declared)")
for entry in entries:
    print(f"  {entry.get('id', '?'):<24} {entry.get('ref', '?')}  <- {entry.get('source', '?')}")
PY
	else
		say "  (python3 missing; cannot read plugins.toml)"
	fi

	say ""
	say "ab:"
	if ! ab_ready; then
		say "  ab:                  not on PATH"
	else
		say "  ab:                  $(command -v ab)"
		for sub in "profile" "install" "image" "build"; do
			if ab_mentions "$sub"; then
				say "  mentions '$sub':     yes"
			else
				say "  mentions '$sub':     no — '$0 install' will exit $EXIT_NO_AB"
			fi
		done
	fi
}

cmd_deploy() {
	require_host deploy

	if [[ ! -d "$LIVE_DIR" ]]; then
		err "refusing: $LIVE_DIR does not exist, so there is nothing to fast-forward."
		print_migration
		exit "$EXIT_REFUSED"
	fi
	if ! git -C "$LIVE_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
		err "refusing: $LIVE_DIR is not a git work tree."
		print_migration
		exit "$EXIT_REFUSED"
	fi

	local repo_root live_root
	repo_root="$(root_commit "$REPO_DIR")"
	live_root="$(root_commit "$LIVE_DIR")"
	if [[ -z "$repo_root" || "$live_root" != "$repo_root" ]]; then
		err "refusing: $LIVE_DIR is a clone of a different repository (root commit ${live_root:-none} != $repo_root)."
		print_migration
		exit "$EXIT_REFUSED"
	fi
	if ! git -C "$LIVE_DIR" remote get-url origin >/dev/null 2>&1; then
		err "refusing: $LIVE_DIR has no 'origin' remote, so 'git pull --ff-only' has nothing to pull from."
		print_migration
		exit "$EXIT_REFUSED"
	fi
	if [[ -n "$(git -C "$LIVE_DIR" status --porcelain)" ]]; then
		err "refusing: $LIVE_DIR is not clean. Local edits there would be lost; this repo is the source."
		git -C "$LIVE_DIR" status --short >&2
		print_migration
		exit "$EXIT_REFUSED"
	fi
	if [[ "$(git -C "$LIVE_DIR" rev-parse --abbrev-ref HEAD)" == "HEAD" ]]; then
		err "refusing: $LIVE_DIR has a detached HEAD, so there is no branch to fast-forward."
		print_migration
		exit "$EXIT_REFUSED"
	fi

	say "deploying to $LIVE_DIR"
	git -C "$LIVE_DIR" pull --ff-only
	say "live profile is now at $(git -C "$LIVE_DIR" rev-parse HEAD)"
}

cmd_install() {
	require_host install

	ab_ready || die "ab is not on PATH; cannot install the profile." "$EXIT_NO_AB"
	ab_mentions profile || die "this ab has no 'profile' command (need 'ab profile install $PROFILE_NAME')." "$EXIT_NO_AB"
	ab_mentions install || die "this ab's profile command has no 'install' (need 'ab profile install $PROFILE_NAME')." "$EXIT_NO_AB"

	say "ab profile install $PROFILE_NAME"
	ab profile install "$PROFILE_NAME"

	if [[ -f "$REPO_DIR/Containerfile" ]]; then
		ab_mentions image || die "this ab has no 'image' command (need 'ab image build $PROFILE_NAME' for the Containerfile)." "$EXIT_NO_AB"
		ab_mentions build || die "this ab's image command has no 'build' (need 'ab image build $PROFILE_NAME')." "$EXIT_NO_AB"
		say "ab image build $PROFILE_NAME"
		ab image build "$PROFILE_NAME"
	fi
}

cmd_all() {
	cmd_check
	cmd_deploy
	cmd_install
}

usage() {
	sed -n '3,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

main() {
	local command="${1:-}"
	case "$command" in
	check) cmd_check ;;
	status) cmd_status ;;
	deploy) cmd_deploy ;;
	install) cmd_install ;;
	all) cmd_all ;;
	-h | --help | help | "") usage ;;
	*)
		err "unknown command: $command"
		usage >&2
		exit "$EXIT_PROBLEMS"
		;;
	esac
}

main "$@"
