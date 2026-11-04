# Third-party content

Everything vendored into this profile. Update this file in the same commit that
adds, moves or edits vendored content.

Per [PARITY.md](PARITY.md) every entry carries the same six fields: **name**,
**source URL**, **path**, **commit**, **license**, **local changes**.

Provenance was verified by fetching each upstream file at its pinned commit and
diffing it against the vendored copy (2026-11-03).

## skills/show-me

| Field | Value |
| --- | --- |
| Name | `show-me` |
| Source URL | <https://github.com/humanlayer/skills> |
| Path | `plugins/show-me/skills/show-me` |
| Commit | `4d69d20f6e9b57b4fcf0d501ccfb1be961f0f329` |
| License | MIT — `skills/show-me/LICENSE` (Copyright (c) 2026 HumanLayer) |

**Local changes**

Two edits to the body of `SKILL.md`, plus an added `LICENSE`. The frontmatter is
untouched and carries no comment: this file is the only record.

1. **The HTML artifact is saved, not opened.** Upstream ends the "For a visual
   UI" bullet with "Then open it for the user:" and a
   `Bash(open path/to/show-me-{description}.html)` block. `open` is macOS-only
   and fails in an agentbox sandbox, which has no display and no browser opener.
   Replaced with an instruction to save the file as
   `.dev/show-me/show-me-{description}.html` and hand the user that path, so the
   user opens it on their own machine. `.dev/` is gitignored and is the same
   artifact directory `AGENTS.md` gives EGM.
2. **A terminal note under `### guidance`.** Added a paragraph saying the user
   reads replies in a terminal, where Mermaid is source text rather than a
   picture, so the plain-text views are preferred and a diagram that must be
   seen rendered belongs in the HTML file. Upstream offers Mermaid without that
   caveat.
3. **`LICENSE` added to the skill directory.** Upstream has no LICENSE inside
   `plugins/show-me/skills/show-me/`; this is a verbatim copy of the
   repository-root `LICENSE` at the pinned commit, so the MIT terms travel with
   the vendored directory.

Nothing else in the body changed, and no view, example or code block was removed
other than the `Bash(open …)` block named above.

*Correction to the build brief:* it said these local changes are described in a
comment at the top of the frontmatter. There is no such comment and, before the
two edits above, `SKILL.md` had no local changes at all. It also said the LICENSE
is upstream "in its folder"; it is not, it is the repo-root license.

## skills/ub-mode

| Field | Value |
| --- | --- |
| Name | `ub-mode` |
| Source URL | <https://github.com/unclebob/ub-mode> |
| Path | repository root (`SKILL.md`, `LICENSE`) |
| Commit | `3da62bf3fcfd2034de41f30d920d2739e566171f` |
| License | MIT — `skills/ub-mode/LICENSE` (Copyright (c) 2026 Robert C. Martin) |

**Local changes**

One frontmatter key added to `SKILL.md`; the body and `LICENSE` are
byte-identical to upstream. No comment was added to the frontmatter: this file
is the record.

1. **`disable-model-invocation: true`.** Upstream sets no `hide` or
   `disable-model-invocation`, so ub-mode was listed in the system prompt and the
   model could select it on its own — and its description ("Follow the reduced
   principles when writing or changing code") invites that on any code change,
   not only when asked. OMP normalizes the key to `disableModelInvocation` and
   reads it as `hide` (`reference/omp/skills.md`), so the skill is now opt-in:
   never listed, still reachable as `/skill:ub-mode` and `skill://ub-mode`.
   `hide` does not disable a skill. This matches `AGENTS.md`: "show-me and
   ub-mode run only when I invoke them."

*Correction to the build brief:* it gave the path as
`plugins/ub-mode/skills/ub-mode`. That path does not exist at this commit — the
tree is exactly `LICENSE`, `README.md`, `SKILL.md` at the root, and the vendored
files match the root copies. It also said local changes are described in a
frontmatter comment; there is no such comment.

## skills/mags-manifest-design

| Field | Value |
| --- | --- |
| Name | `mags-manifest-design` |
| Source URL | <https://github.com/TimothyStephens/MAGS-CodeDev> |
| Path | `skills/mags-manifest-design/SKILL.md` |
| Commit | `d44fea8c5bf4021e3103ee9671a06940fc7f713c` |
| License | Tim's own project; no separate license file vendored |

**Local changes**

None. `SKILL.md` is byte-identical to upstream.

## reference/omp

| Field | Value |
| --- | --- |
| Name | OMP format documentation |
| Source URL | <https://github.com/can1357/oh-my-pi> |
| Path | `docs/` |
| Commit | `5dc44d3417722796fd96e8be6bee4712023d1667` (see [`reference/omp/SOURCE_COMMIT`](reference/omp/SOURCE_COMMIT)) |
| License | upstream project license; vendored for reference only |

**Local changes**

None; kept as received. These files are the format spec this repo's READMEs and
`tools/check.py` cite. Not shipped into a session — `reference/` is not one of
the directories agentbox mounts.

## Declared, not vendored

Plugins in [`plugins.toml`](plugins.toml) are installed by agentbox at
`ab profile install omp`, from their own marketplaces at the pinned refs. No
plugin content lives in this repository.
