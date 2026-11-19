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
| `disable-model-invocation: true` | Agent-Skills spelling of `hide`; normalized to `disableModelInvocation` and read as `hide`. This is how the shared `show-me` stays unlisted while remaining invocable as `/skill:show-me`. |
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

## Shared skills: the `agentbox-skills` plugin

The skills every agentbox profile has are not in `skills/`. They live in one
repository, `agentbox-skills`
(<https://github.com/TimothyStephens/AgentBox-Skills>), declared in
`plugins.toml` as the marketplace plugin `agentbox@agentbox-skills` at a
pinned commit, and are invoked like any other skill: `/skill:<name>` (on a
name clash with another skill, `/skill:agentbox/<name>`), e.g.
`/skill:show-me` or `/skill:learn-repo`. Provenance, licences and local
changes of the vendored ones are in that repository's `THIRD_PARTY.md`; change
them there, never by copying one back into `skills/`.

| Skill | What for | Model-invocable |
| --- | --- | --- |
| `learn-repo` | build an understanding of an existing repo before a task | no |
| `review-drift` | review another agent's work for scope creep and drift from a plan, from a clean context | no |
| `show-me` | explain the current topic with diagrams, code-shape sketches or an HTML file under `.dev/show-me` | no |
| `ub-mode` | the reduced coding principles, on request | no |
| `mags-manifest-design` | write or edit a MAGs-CodeDev `manifest.json` | yes |
| `full-review` | a read-only, comprehensive code review of a branch, range, PR or the whole repo | no |
| `handoff` | a dated handoff note at the end of a session, for the next one's `learn-repo` | no |
| `characterization-tests` | pin the current behaviour of untested code before changing it | no |
| `systematic-debugging` | root-cause a bug or failure before fixing it | yes |
| `verification-before-completion` | run the checks before claiming work is done | yes |
| `test-driven-development` | write the test first | yes |
| `webapp-testing` | drive a local web UI with Playwright (not in the images; see agentbox-skills' THIRD_PARTY.md) | yes |
| `differential-review` | security-focused review of a PR, commit or diff | yes |
| `insecure-defaults` | find fail-open insecure defaults (hardcoded secrets, weak auth) | yes |
| `supply-chain-risk-auditor` | audit a project's dependencies (needs network the `packages` egress mostly blocks) | yes |

"Model-invocable: no" means `disable-model-invocation: true`: the skill runs
only when invoked. The list is the repository's at the pinned commit; its
README is the current one.

`skills/` holds only skills this profile alone has, and none today: it is empty
but for `.gitkeep`, which keeps it in git. It must still exist, because
agentbox mounts it read-only over the skill path; that `.gitkeep` is the one
plain file `check` allows directly in `skills/`. A skill every profile should
have goes in `agentbox-skills` instead.

## Authoring notes

- Keep every asset inside the skill directory; `skill://` rejects absolute
  paths, `..` traversal, and anything resolving outside the skill base dir.
- Do not rely on OMP auto-learn: it writes only to
  `~/.omp/agent/managed-skills`, which agentbox makes per-session and drains to
  a review inbox at teardown. Nothing in this repo may depend on it.
- Vendored (third-party) skills must be listed in
  [`../THIRD_PARTY.md`](../THIRD_PARTY.md) with source, commit, license and
  local changes.
