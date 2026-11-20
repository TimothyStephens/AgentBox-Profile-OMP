# Decisions

## 2026-11-19: the shared skills come from agentbox-skills, not from copies in `skills/`

- What: the five skills every profile carried as a byte-identical copy (`learn-repo`, `show-me`,
  `ub-mode`, `review-drift`, `mags-manifest-design`) are removed from `skills/` and come from the
  `agentbox-skills` repository (<https://github.com/TimothyStephens/AgentBox-Skills>) instead, declared
  in `plugins.toml` as the marketplace plugin `agentbox@agentbox-skills` pinned at `245ba14b`. That
  repository also brings skills this profile did not have (full-review, handoff, characterization-tests,
  systematic-debugging, verification-before-completion, test-driven-development, skill-creator,
  webapp-testing, differential-review, insecure-defaults, supply-chain-risk-auditor). They are invoked
  as `/skill:<name>` as before (`/skill:agentbox/<name>` on a name clash). The vendored skills' entries
  in `THIRD_PARTY.md` moved to that repository's `THIRD_PARTY.md`.
- Why: one source for skills shared by all agents; Tim, 19 Nov.
- `skills/` stays: it is empty but for `skills/.gitkeep`, and `check` now allows that one file directly
  in `skills/` (a shared rule, with a `shared:` test in all three repos). It is not dropped, though
  agentbox would simply not mount a missing one: the mount is what makes the agent's skill path
  read-only, and without it that path is the project's writable state, where one session could leave a
  skill every later session loads.
- Bumping: commit and push agentbox-skills, `ab profile install <agent> --resolve` for the sha, then
  change `ref` in all three profiles' `plugins.toml` together.

## 2026-11-16: secret names, `status` on a broken plugins.toml, shared test labels checked

- What: the secret-name rule in `tools/check.py` adds `*.key` and any path component named `secrets`
  (the names agentbox masks in a session), anywhere, `.dev/` included. `./build.sh status` exits 1 and
  prints "(plugins.toml does not parse)" when `check.py --list-plugins` fails, instead of listing
  nothing and exiting 0. `tests/run.sh` ends with a case that greps the sibling repo's `run.sh` for
  every `shared:` label in this one (a trailing "(detail)" ignored; skipped with a note when the
  sibling checkout is absent), and the labels were renamed so both repos pass it; no case was dropped.
  Stale text fixed: the README's "102 cases" and the Containerfile's `ab run --no-profile`.
- Why: a `server.key` or `secrets/` passed `check` although a session would mask it; a broken
  plugins.toml made `status` look clean; and "same test names in both repos" was a promise nothing
  checked, which had drifted (review of 16 Nov, item 51).

## 2026-11-16: `check` applies the launcher's plugins.toml and Containerfile rules exactly

- What: in `plugins.toml` an unknown section or an unknown key in any `[[plugin]]`, `[[npm]]` or
  `[[repo]]` entry is an error (it was a warning); a `[[plugin]]` `source` must be GitHub shorthand
  or a plain https URL without credentials or `..` (it was not checked); `extension_dir` accepts
  what `plugins.py _repo` accepts (`.` and nested relative paths) and refuses absolute paths, a
  leading `..` and anything `normpath` would rewrite (it accepted only a single directory name, so
  `.` was refused). In the `Containerfile`, `ARG BASE` and `FROM ${BASE}` match case-sensitively
  (`ARG base` was accepted) and the checksum rule applies to RUN and ADD only (a URL in ENV or
  LABEL failed it).
- Why: the file's own comment promised an ERROR for an unknown key, and a warning does not stop a
  deploy that `ab profile install omp` then refuses; the other four rules drifted from the launcher
  and from the Claude checker, failing what the install accepts or passing what it refuses (review
  of 16 Nov, item 24).

## 2026-11-16: `deploy` fails when the live clone does not reach this repo's HEAD

- What: after `git pull --ff-only`, `build.sh deploy` compares the live clone's HEAD with this
  checkout's and fails (exit 1, "push this repo first") when they differ; `live_is_clean_clone`
  also requires the live HEAD to be an ancestor of this repo's HEAD, so a live clone with its own
  commits is "diverged" for `deploy` as it already was for `status`. The comparison is a function,
  `live_matches_repo LIVE REPO`, and `build.sh` returns early when sourced so `tests/run.sh` can
  call it against scratch repositories (deploy itself is host only).
- Why: the pull fast-forwards from the live clone's `origin`, so with an unpushed commit here it
  succeeded and printed "now at <old sha>" as if the deploy had happened; and a live clone ahead of
  origin was accepted as clean although nothing would ever reconcile it (review of 16 Nov, item 23).

## 2026-11-15: `mags-codedev.yaml` is not a seed any more

- What: dropped from `build.sh` SEEDS, the README and the checker's docstring. The seeds are
  `models.yml`, `config.yml`, `mcp.json`.
- Why: MAGS-CodeDev f48ef34 (4 Nov) removed the `~/.omp/agent/mags-codedev.yaml` config path; a file
  there "is simply ignored". The launcher stopped mounting it the same day (agentbox decisions.md,
  15 Nov). MAGS stays outside agentbox as its own container, Tim's decision.

## 2026-11-13: the MAGS-CodeDev `[[repo]]` entry is gone; MAGS is not an OMP extension at the pinned ref

- What: removed `[[repo]] mags-codedev` (ref d44fea8c, `extension_dir = "mags-codedev-extension"`) from
  `plugins.toml`; the status test names pi-session-stats instead.
- Why: `ab profile install omp` failed on `omp plugin link` with "package.json not found". MAGS-CodeDev
  commit 3d3d8a4c (3 Nov, "chore: drop the OMP extension, keep its manifest-design guide") removed the
  extension; the pinned ref is after it and holds no `package.json` anywhere. MAGS is a standalone Python
  CLI meant to run as its own agentbox agent (its README, "Running under agentbox"). What this profile
  keeps of it is `skills/mags-manifest-design`. The installer is fail-fast, so the dead entry also took the
  marketplace copy down with it and egm did not load in sessions.

## 2026-11-10: `seed/` — keyless config agentbox reads beside the live profile, installed by deploy

- What: a `seed/` directory in the profile repo. `./build.sh deploy` copies each `seed/<name>` to
  `~/.config/agentbox/<agent>/<name>` when no live copy exists, mode 0600, and never overwrites one;
  `./build.sh status` prints a `seeds:` block naming every file agentbox looks for (`SEEDS` in
  `build.sh`: for OMP `models.yml config.yml mcp.json mags-codedev.yaml`, for Claude none) plus
  whatever `seed/` holds, each as `live = seed`, `DIFFERS`, `not live yet`, `live only` or
  `MISSING`. `check` allows `seed/`, requires flat files, and refuses a credential-shaped line
  (`apiKey`, `token`, `secret`, `password`, `authorization` with a real value; `apiKey` in
  `models.yml` with any value, which is agentbox's own rule). `build.sh` is still the same script in
  both repos; its per-profile lines are now the profile name, the live path and `SEEDS`.
- Why: a session on OMP without `~/.config/agentbox/omp/models.yml` runs on defaults and only says
  so in a warning at start; nothing in the profile's own tooling knew the file existed, and a new
  host had to learn it from agentbox's INSTALL.md. The seeds are keyless by agentbox's design, so
  a copy can live in the repo; `deploy` installing a missing one makes a fresh host complete, and
  never overwriting keeps a host-side edit safe. Committing `seed/` is the default so it travels
  with the repo; a `seed/` line in `.gitignore` makes it host-local instead, with `status` still
  reporting it.

## 2026-11-09: PARITY.md dropped; build.sh is the same script in both profile repos

- What: `PARITY.md`, the written parity contract with the sibling profile repo, was deleted from
  `agentbox-profile-claude` and `agentbox-profile-omp`. `build.sh` was ported from the Claude repo
  to the OMP repo verbatim; the two now differ only in the profile name, the live-path variable
  and how they call `tools/check.py`. The OMP `deploy` therefore clones the live profile on first
  run, matches the live clone by `origin` URL rather than root commit, and no longer checks for a
  detached HEAD.
- Why: the Claude repo's latest `build.sh` changes were to be synced to the OMP repo, and the
  parity discussion taken out of the README and `PARITY.md`, since the review that did the sync
  made the repos match. The shared parts are now listed in one paragraph of each README.

## 2026-11-20: pi-lens is dropped

- What: pi-lens 4.4.9 is removed from `plugins.toml` (and from the Pi profile's).
- Why: Tim, 20 Nov. It installs the language servers and linters it runs on demand; agentbox now turns those
  installs off (unpinned npm/pip/gem code) and no image carries the tools, so little of it worked, at about
  290,000 lines and a prompt cost every session. OMP has its own LSP support (`src/lsp`). The `PI_LENS_DISABLE_*`
  variables agentbox sets stay, in case it comes back with pinned tools in an image.

## 2026-11-20: pi-session-stats and pi-content-audit at 7c7ddba and a427f1a

- What: both pins moved to the commits that declare `@oh-my-pi/*` as optional peer dependencies instead of
  dependencies.
- Why: `ab profile install pi` failed on 20 Nov: the installer's `npm install` in the pi-session-stats
  checkout downloaded OMP (151 packages) and was killed for memory (exit 137, reproduced). Neither host
  loads those copies (Pi aliases them, OMP remaps them to its bundled copy), so the install now fetches
  nothing; OMP 18.13.3 was checked loading both extensions from a checkout with no node_modules.
