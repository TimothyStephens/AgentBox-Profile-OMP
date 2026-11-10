# agentbox-profile-omp

An OMP (Oh My Pi) profile for agentbox (`ab`), a rootless-podman sandbox
launcher.

**This repository is the source.** The profile agentbox actually reads is a git
clone of it at `~/.config/agentbox/omp/profile`. Nothing in this repo writes to
that clone except `./build.sh deploy`, run on the host.

## Layout

| Path | Mounted at | What it is |
| --- | --- | --- |
| `AGENTS.md` | folded into the session instructions | Standing rules for every session |
| `skills/` | `~/.omp/agent/skills` (read-only) | Agent Skills — [format](docs/skills.md) |
| `rules/` | `~/.omp/agent/rules` (read-only) | Rulebook / always-apply / TTSR rules — [format](docs/rules.md) |
| `prompts/` | `~/.omp/agent/prompts` (read-only) | Prompt templates — [format](docs/prompts.md); ships empty |
| `agents/` | `~/.omp/agent/agents` (read-only) | Task-agent definitions — [format](docs/agents.md) |
| `commands/` | `~/.omp/agent/commands` (read-only) | File-based slash commands — [format](docs/commands.md) |
| `plugins.toml` | — | Plugins agentbox installs, pinned to commit shas |
| `Containerfile` | — | Optional user image layer (neovim 0.10.4) |
| `build.sh`, `tools/`, `tests/` | — | Build machinery; never shipped into a session |
| `THIRD_PARTY.md` | — | Provenance for everything vendored |
| `docs/` | — | Format reference for each load directory, one file per directory, plus `decisions.md` |
| `reference/omp/` | — | OMP's own format docs, the spec this repo cites |
| `seed/` | copied to `~/.config/agentbox/omp/` | Keyless copies of what agentbox reads from there: `models.yml`, `config.yml`, `mcp.json`, `mags-codedev.yaml`. `deploy` installs a missing one and never overwrites; `status` reports each |

Those five directories are mounted read-only into **every OMP session in every
project**. `ab run --no-profile` skips all of it, plugins and the image layer
included.

agentbox reads OMP's own settings from `~/.config/agentbox/omp/`, beside the
live profile, not from the profile: `models.yml` (the keyless model seed, from
which each session's `models.yml` is generated for the providers that have a key
file), `config.yml`, `mcp.json` and `mags-codedev.yaml`. A session without them
runs on OMP's defaults and says so. `seed/` in this repo is where a keyless copy
of each lives: `./build.sh deploy` installs any whose live copy is missing (and
never overwrites one that exists), `./build.sh status` reports each file as
live = seed, differing, not live yet, live only, or MISSING, and `check` refuses
a credential in any of them (`apiKey` in `models.yml` outright, as agentbox
does). Keys go through `ab keys set <provider>`, never into a seed. In this repo `seed/` is
**gitignored**: the live files are personal config and stay on the host, where
`status` reports them as "live only". A `seed/` you create locally still feeds
`deploy`; it just never gets committed.

Auto-learn writes only to `~/.omp/agent/managed-skills`, which agentbox makes
per-session and drains to a review inbox at teardown. Nothing here may depend
on it.

This repo has a sibling, `agentbox-profile-claude`, for Claude Code. `build.sh`,
the `Containerfile`, the shared core block of `AGENTS.md` and the shared `check`
rules are kept the same in both, and the test cases named `shared:` exist under
the same name in both repos; `omp:` cases are this harness only. Change a shared
part here and make the same change there.

## The loop

### 1. Edit

Add or change a skill, rule, agent or command. `docs/<directory>.md` is the
format reference for each one and links to the vendored OMP doc that is the
spec. The documentation cannot live inside the directory it documents: those
are mounted onto discovery paths, so OMP loads whatever is in them — a
`commands/README.md` becomes a `/README` command in every session.

### 2. Check

```sh
./build.sh check
```

Offline, no dependencies, no network, no `ab`. Prints every problem as
`path: problem` (warnings as `path: warning: problem`) and exits 1 if there is
at least one error. What it enforces is listed in
[`tools/check.py`](tools/check.py); every rule has a test.

```sh
./tests/run.sh      # 102 cases: the rules, the warnings, the host-only refusals
```

Run both. A green `check` with a red `tests/run.sh` means the checker itself
changed behaviour.

### 3. Commit

One commit per green step, with a message that says what now works. Don't push
unless asked.

### 4. Deploy

On the host, not in a sandbox:

```sh
./build.sh status    # live profile commit vs this repo's HEAD, plugin pins, ab
./build.sh deploy    # clone ~/.config/agentbox/omp/profile, or git pull --ff-only it
./build.sh install   # ab profile install omp, + ab image build omp
./build.sh all       # check, deploy, install; stops at the first failure
```

`deploy` and `install` are **host only**. They refuse with exit 2 when
`AGENTBOX_SESSION` is set or `/run/agentbox` exists, so an agent inside a
sandbox cannot reach the live profile.

On a new host, `deploy` sees that the live directory does not exist (or is
empty), creates `~/.config/agentbox/omp/` and clones this repo (its `origin`
URL, or this checkout if it has no origin) to `profile/`. After that it only
fast-forwards: if the directory exists but is not a clean clone of this repo
with the same `origin`, it refuses with exit 2 and prints the one-time
migration: move it aside to `profile.pre-repo`, then `git clone` this repo in
its place.

`install` runs `ab profile install omp`, then `ab image build omp` if a
`Containerfile` exists. It exits 3 if `ab` is not on PATH or lacks one of those
commands, which it decides by running the subcommand with `--help`.

### 5. Run clean

```sh
ab run --no-profile     # none of this repo, no plugins, no image layer
```

Use it to tell "the profile broke it" apart from "the project broke it".

### 6. Roll back

```sh
git revert <bad commit>     # or: git revert --no-commit <range> && git commit
./build.sh check
./build.sh all              # on the host
```

Roll *forward* with a revert commit rather than resetting history: `deploy` is
`pull --ff-only` and refuses a rewritten branch. If you do need to rewind, do it
in this repo, then move the live clone aside and re-clone using the migration
`deploy` prints.

## Working in this repo from a sandbox

`check` and `tests/run.sh` are the whole inner loop; both work offline inside
agentbox. `deploy` and `install` do not and will refuse.

`check` rejects any unexpected top-level entry, with one exception: `.dev/`,
which is gitignored and holds EGM's artifacts (`.dev/docs`, see `AGENTS.md`)
and show-me's HTML files (`.dev/show-me`). A run that produced artifacts still
passes, and `.dev/` is skipped by the symlink and size rules because it is
never deployed. The secret-name rules (`.env*`, `*.pem`, `id_*`) still apply
inside it, so don't park anything sensitive there.
