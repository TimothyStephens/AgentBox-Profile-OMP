#!/usr/bin/env bash
# Build/deploy driver for this OMP profile. See README.md.
#
#   ./build.sh check     offline validation of this repo          (anywhere)
#   ./build.sh status    live profile vs this repo, plugin pins   (anywhere)
#   ./build.sh deploy    clone or fast-forward the live profile; install missing seeds (host only)
#   ./build.sh install   ab profile install + ab image build      (host only)
#   ./build.sh all       check, deploy, install; stop on failure  (host only)
#
# Exit status: 0 ok, 1 check failed, 2 refused (wrong place / usage), 3 ab cannot do it.

set -uo pipefail

REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROFILE="omp"
LIVE="${AGENTBOX_OMP_PROFILE:-$HOME/.config/agentbox/omp/profile}"
# agentbox also reads a few files from the directory ABOVE the live profile (~/.config/agentbox/<agent>/),
# never from the profile itself: keyless seeds and personal config a session mounts read-only. SEEDS names
# the ones agentbox looks for; seed/<name> in this repo is a copy that `deploy` installs when the live one
# is missing (never over it), and `status` reports each. Keys never go in them: `ab keys set <provider>`.
SEEDS="models.yml config.yml mcp.json"
SEED_DIR="$REPO/seed"

say()  { printf '%s\n' "$*"; }
warn() { printf '%s\n' "$*" >&2; }

# HOST ONLY: the live profile and `ab` live on the host, not in a session sandbox.
require_host() {
  local what="$1"
  if [[ -n "${AGENTBOX_SESSION:-}" || -e /run/agentbox ]]; then
    warn "build.sh $what: refusing to run inside an agentbox sandbox; this is host only."
    warn "  Run it from a terminal on the host, in a checkout of this repo."
    exit 2
  fi
}

# Where a fresh clone of this repo should come from.
clone_source() {
  local origin
  origin="$(git -C "$REPO" remote get-url origin 2>/dev/null)"
  if [[ -n "$origin" ]]; then printf '%s\n' "$origin"; else printf '%s\n' "$REPO"; fi
}

ab_has() {  # ab_has "profile install" -> 0 if that subcommand exists
  command -v ab >/dev/null 2>&1 || return 1
  # shellcheck disable=SC2086
  ab $1 --help >/dev/null 2>&1
}

# --- check -----------------------------------------------------------------

cmd_check() {
  say "== check: $REPO"
  python3 "$REPO/tools/check.py" --root "$REPO"
  local rc=$?
  if (( rc == 0 )); then say "check: ok"; else say "check: failed"; fi
  return $rc
}

# --- status ----------------------------------------------------------------

# True if $LIVE is missing or an empty directory: deploy may clone into it.
live_is_absent() {
  [[ ! -e "$LIVE" ]] && return 0
  [[ -d "$LIVE" && -z "$(ls -A -- "$LIVE" 2>/dev/null)" ]]
}

# Is $LIVE a clean clone of this repo? Sets REASON on failure.
REASON=""
live_is_clean_clone() {
  REASON=""
  if live_is_absent; then
    REASON="does not exist"
    return 1
  fi
  if ! git -C "$LIVE" rev-parse --git-dir >/dev/null 2>&1; then
    REASON="is not a git repository"
    return 1
  fi
  local src origin
  src="$(clone_source)"
  origin="$(git -C "$LIVE" remote get-url origin 2>/dev/null)"
  if [[ -z "$origin" ]]; then
    REASON="has no origin remote"
    return 1
  fi
  if [[ "$origin" != "$src" ]]; then
    REASON="has origin $origin, expected $src"
    return 1
  fi
  if [[ -n "$(git -C "$LIVE" status --porcelain 2>/dev/null)" ]]; then
    REASON="has uncommitted local changes"
    return 1
  fi
  # A live clone with commits this repo lacks is diverged, for deploy as for status: a fast-forward from
  # origin would not reconcile it, and an edit made live instead of here must not be papered over.
  local live_head
  live_head="$(git -C "$LIVE" rev-parse HEAD 2>/dev/null)"
  if ! git -C "$REPO" merge-base --is-ancestor "$live_head" HEAD 2>/dev/null; then
    REASON="has commits this repo does not (diverged: ${live_head:0:12} is not an ancestor of this repo's HEAD)"
    return 1
  fi
  return 0
}

# After a pull, the live clone must be at this repo's HEAD. deploy fast-forwards the live clone from ITS
# origin, so an unpushed commit here leaves it behind while the pull reports success; that is the case
# this catches. Takes the two paths as arguments so tests can run it against scratch repositories.
live_matches_repo() {
  local live="$1" repo="$2" live_head repo_head
  live_head="$(git -C "$live" rev-parse HEAD 2>/dev/null)"
  repo_head="$(git -C "$repo" rev-parse HEAD 2>/dev/null)"
  if [[ -z "$live_head" || -z "$repo_head" ]]; then
    warn "build.sh deploy: cannot read HEAD of $live or $repo"
    return 1
  fi
  if [[ "$live_head" != "$repo_head" ]]; then
    warn "build.sh deploy: live profile is at ${live_head:0:12} but this repo is at ${repo_head:0:12};"
    warn "  push this repo first (deploy fast-forwards the live clone from its origin)."
    return 1
  fi
  return 0
}

print_migration() {
  say ""
  say "One-time migration (run on the host, then ./build.sh deploy):"
  say "  mv $LIVE ${LIVE}.pre-repo"
  say "  git clone $(clone_source) $LIVE"
  say ""
  say "Keep profile.pre-repo until you have compared it against this repo; delete it then."
}

cmd_status() {
  local head live_head
  head="$(git -C "$REPO" rev-parse HEAD 2>/dev/null || echo '(no commits)')"
  say "repo:  $REPO"
  say "  HEAD $head"

  say "live:  $LIVE"
  if live_is_clean_clone; then
    live_head="$(git -C "$LIVE" rev-parse HEAD)"
    say "  HEAD $live_head"
    if [[ "$live_head" == "$head" ]]; then
      say "  up to date with this repo"
    elif git -C "$REPO" merge-base --is-ancestor "$live_head" "$head" 2>/dev/null; then
      local behind
      behind="$(git -C "$REPO" rev-list --count "$live_head..$head" 2>/dev/null)"
      say "  $behind commit(s) behind this repo; ./build.sh deploy will fast-forward it"
    else
      say "  diverged from this repo (not an ancestor of HEAD)"
    fi
  elif live_is_absent; then
    say "  does not exist yet; ./build.sh deploy will clone this repo there"
  else
    say "  not deployable: $REASON"
  fi

  say "plugins:"
  if [[ -f "$REPO/plugins.toml" ]]; then
    python3 "$REPO/tools/check.py" --list-plugins --root "$REPO" \
      | while read -r id source ref; do
          say "  $id  $source  ${ref:0:12}"
        done
  else
    say "  (no plugins.toml)"
  fi

  say "seeds: $(seed_dst)"
  seed_report

  say "ab:"
  if ! command -v ab >/dev/null 2>&1; then
    say "  not on PATH (expected inside a session sandbox; needed on the host)"
  else
    say "  $(command -v ab)"
    if ab_has "profile install"; then say "  profile install: available"
    else say "  profile install: NOT available"; fi
    if ab_has "image build"; then say "  image build: available"
    else say "  image build: NOT available"; fi
  fi
  return 0
}

# --- seeds -----------------------------------------------------------------

# The directory agentbox reads the seeds from: the one above the live profile.
seed_dst() { dirname -- "$LIVE"; }

# One line per seed: the repo's seed/<name> against the live copy. Names come from SEEDS (what agentbox looks
# for) plus whatever seed/ holds, so a file in only one place is still reported.
seed_report() {
  local dst names=() n f
  dst="$(seed_dst)"
  for n in $SEEDS; do names+=("$n"); done
  if [[ -d "$SEED_DIR" ]]; then
    for f in "$SEED_DIR"/*; do
      [[ -f "$f" ]] || continue
      n="$(basename -- "$f")"
      case " ${names[*]-} " in *" $n "*) ;; *) names+=("$n") ;; esac
    done
  fi
  if (( ${#names[@]} == 0 )); then
    say "  (none expected for this profile)"
    return 0
  fi
  for n in "${names[@]}"; do
    local repo="$SEED_DIR/$n" live="$dst/$n" state
    if [[ -f "$repo" && -f "$live" ]]; then
      if cmp -s -- "$repo" "$live"; then
        state="live = seed/$n"
      else
        state="live DIFFERS from seed/$n (deploy never overwrites; copy whichever is right over the other)"
      fi
    elif [[ -f "$repo" ]]; then
      state="not live yet; ./build.sh deploy will install seed/$n"
    elif [[ -f "$live" ]]; then
      state="live only, not in this repo (cp $live $SEED_DIR/ to keep it here)"
    else
      state="MISSING: neither $live nor seed/$n; sessions run on $PROFILE's own defaults"
    fi
    say "  $n: $state"
  done
}

# deploy: install each seed/<name> whose live copy is missing. Never over an existing one -- it may hold a
# change made on the host -- and status says when the two differ.
seed_install() {
  [[ -d "$SEED_DIR" ]] || return 0
  local dst f n
  dst="$(seed_dst)"
  for f in "$SEED_DIR"/*; do
    [[ -f "$f" ]] || continue
    n="$(basename -- "$f")"
    [[ -e "$dst/$n" ]] && continue
    mkdir -p -- "$dst" || return 1
    cp -- "$f" "$dst/$n" && chmod 600 -- "$dst/$n" || return 1
    say "deploy: installed seed/$n -> $dst/$n"
  done
  return 0
}

deploy_seeds() {
  seed_install || return 1
  say "seeds: $(seed_dst)"
  seed_report
}

# --- deploy ----------------------------------------------------------------

# First-time setup: clone this repo to $LIVE, creating its parent directories.
bootstrap_live() {
  local src
  src="$(clone_source)"
  say "== deploy: $LIVE does not exist; first-time setup"
  mkdir -p -- "$(dirname -- "$LIVE")" || return 1
  say "== deploy: git clone $src $LIVE"
  git clone -- "$src" "$LIVE" || return 1
  say "deploy: live profile created at $(git -C "$LIVE" rev-parse --short HEAD)"
  deploy_seeds || return 1
  say "deploy: next, ./build.sh install to install plugins and build the image"
  return 0
}

cmd_deploy() {
  require_host deploy
  if live_is_absent; then
    bootstrap_live
    return $?
  fi
  if ! live_is_clean_clone; then
    warn "build.sh deploy: refusing to touch $LIVE: it $REASON."
    warn "  deploy only fast-forwards a clean clone of this repo."
    print_migration >&2
    exit 2
  fi
  say "== deploy: git -C $LIVE pull --ff-only"
  git -C "$LIVE" pull --ff-only || return 1
  live_matches_repo "$LIVE" "$REPO" || return 1
  say "deploy: live profile is now at $(git -C "$LIVE" rev-parse --short HEAD)"
  deploy_seeds || return 1
  say "deploy: new sessions pick it up; existing sessions keep what they loaded"
  return 0
}

# --- install ---------------------------------------------------------------

cmd_install() {
  require_host install
  if ! command -v ab >/dev/null 2>&1; then
    warn "build.sh install: ab is not on PATH; cannot install plugins or build the image."
    exit 3
  fi
  if ! ab_has "profile install"; then
    warn "build.sh install: this ab has no 'profile install' command yet."
    exit 3
  fi
  say "== install: ab profile install $PROFILE"
  ab profile install "$PROFILE" || return 1

  if [[ -f "$REPO/Containerfile" ]]; then
    if ! ab_has "image build"; then
      warn "build.sh install: Containerfile present but this ab has no 'image build' command yet."
      exit 3
    fi
    say "== install: ab image build $PROFILE"
    ab image build "$PROFILE" || return 1
  else
    say "install: no Containerfile, skipping image build"
  fi
  say "install: ok"
  return 0
}

# --- all -------------------------------------------------------------------

cmd_all() {
  cmd_check   || return $?
  cmd_deploy  || return $?
  cmd_install || return $?
  say "all: ok"
  return 0
}

usage() {
  sed -n '2,11p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

# tests/run.sh sources this file to call the functions above directly; only a direct run dispatches.
[[ "${BASH_SOURCE[0]}" == "$0" ]] || return 0

case "${1:-}" in
  check)   cmd_check ;;
  status)  cmd_status ;;
  deploy)  cmd_deploy ;;
  install) cmd_install ;;
  all)     cmd_all ;;
  ""|-h|--help|help) usage; [[ -z "${1:-}" ]] && exit 2 || exit 0 ;;
  *) warn "build.sh: unknown command '${1}'"; usage >&2; exit 2 ;;
esac
