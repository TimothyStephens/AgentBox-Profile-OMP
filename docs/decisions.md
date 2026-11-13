# Decisions

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
