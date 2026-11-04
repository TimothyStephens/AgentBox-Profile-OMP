# agentbox-profile-omp

Tim's personal OMP (Oh My Pi) profile for agentbox (`ab`), a rootless-podman
sandbox launcher.

**This repository is the source.** The profile agentbox actually reads is a git
clone of it at `~/.config/agentbox/omp/profile`. Nothing in this repo writes to
that clone except `./build.sh deploy`, run by Tim on the host.

## Layout

| Path | Mounted at | What it is |
| --- | --- | --- |
| `AGENTS.md` | folded into the session instructions | Tim's standing rules |
| `skills/` | `~/.omp/agent/skills` (read-only) | Agent Skills — [format](docs/skills.md) |
| `rules/` | `~/.omp/agent/rules` (read-only) | Rulebook / always-apply / TTSR rules — [format](docs/rules.md) |
| `prompts/` | `~/.omp/agent/prompts` (read-only) | Prompt templates — [format](docs/prompts.md) (**schema unverified**) |
| `agents/` | `~/.omp/agent/agents` (read-only) | Task-agent definitions — [format](docs/agents.md) |
| `commands/` | `~/.omp/agent/commands` (read-only) | File-based slash commands — [format](docs/commands.md) |
| `plugins.toml` | — | Plugins agentbox installs, pinned to commit shas |
| `Containerfile` | — | Optional user image layer (neovim 0.10.4) |
| `build.sh`, `tools/`, `tests/` | — | Build machinery; never shipped into a session |
| `THIRD_PARTY.md` | — | Provenance for everything vendored |
| `PARITY.md` | — | What must stay identical to `agentbox-profile-claude` |
| `docs/` | — | Format reference for each load directory, one file per directory |
| `reference/omp/` | — | OMP's own format docs, the spec this repo cites |

Those five directories are mounted read-only into **every OMP session in every
project**. `ab run --no-profile` skips all of it, plugins and the image layer
included.

OMP settings (`config.yml`), `mcp.json` and `mags-codedev.yaml` live in
`~/.config/agentbox/omp/`, outside this repo. Do not add them here.

Auto-learn writes only to `~/.omp/agent/managed-skills`, which agentbox makes
per-session and drains to a review inbox at teardown. Nothing here may depend
on it.

This repo has a sibling, `agentbox-profile-claude`. [`PARITY.md`](PARITY.md) is
the contract for what must stay identical between them and which differences
the harness is allowed to force. Read it before changing `AGENTS.md`,
`build.sh`, `tools/check.py`, `Containerfile`, `plugins.toml`, `THIRD_PARTY.md`
or this file's section order. Test case names carry that contract: `shared:`
cases must exist under the same name in both repos, `omp:` cases are this
harness only.

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
./tests/run.sh      # 85 cases: the rules, the warnings, the host-only refusals
```

Run both. A green `check` with a red `tests/run.sh` means the checker itself
changed behaviour.

### 3. Commit

One commit per green step, with a message that says what now works. Don't push
unless Tim asks.

### 4. Tim deploys

On the host, not in a sandbox:

```sh
./build.sh status    # live profile commit vs this repo's HEAD, plugin pins, ab
./build.sh deploy    # git pull --ff-only into ~/.config/agentbox/omp/profile
./build.sh install   # ab profile install omp, + ab image build omp
./build.sh all       # check, deploy, install; stops at the first failure
```

`deploy` and `install` are **host only**. They refuse with exit 2 when
`AGENTBOX_SESSION` is set or `/run/agentbox` exists, so an agent inside a
sandbox cannot reach the live profile.

`deploy` only fast-forwards. It refuses, and prints a one-time migration, unless
the live directory is a clean, non-detached git clone of *this* repository
(matched by root commit) with an `origin` remote.

`install` exits 3 if `ab` is missing a command it needs. It decides that by
grepping `ab`'s own help text — `ab profile install` is still being built, so
treat a "no" from `status` as "ask `ab`", not as proof.

### 5. Run clean

```sh
ab run --no-profile     # none of this repo, no plugins, no image layer
```

Use it to tell "the profile broke it" apart from "the project broke it".

### 6. Roll back

The live profile is a git clone, so rolling back is a checkout on the host:

```sh
git -C ~/.config/agentbox/omp/profile log --oneline -10
git -C ~/.config/agentbox/omp/profile checkout <good-commit>
./build.sh install
```

That leaves the clone with a detached HEAD, so the next `deploy` will refuse
until Tim puts it back on its branch:

```sh
git -C ~/.config/agentbox/omp/profile checkout main
```

To roll back the *source* instead, revert here and deploy again — that keeps
the live clone fast-forwardable.

## Working in this repo from a sandbox

`check` and `tests/run.sh` are the whole inner loop; both work offline inside
agentbox. `deploy` and `install` do not and will refuse.

`check` rejects any unexpected top-level entry, with one exception: `.dev/`,
which is gitignored and holds EGM's artifacts (`.dev/docs`, see `AGENTS.md`)
and show-me's HTML files (`.dev/show-me`). A run that produced artifacts still
passes, and `.dev/` is skipped by the symlink and size rules because it is
never deployed. The secret-name rules (`.env*`, `*.pem`, `id_*`) still apply
inside it, so don't park anything sensitive there.
