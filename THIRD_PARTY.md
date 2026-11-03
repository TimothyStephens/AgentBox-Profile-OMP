# Third-party content

Everything vendored into this profile, with the upstream it came from and what
was changed locally. Update this file in the same commit that adds, moves or
edits vendored content.

Provenance below was verified by fetching each upstream file at its pinned
commit and diffing it against the vendored copy (2026-11-03).

## Vendored skills

### `skills/show-me`

| | |
| --- | --- |
| Source | <https://github.com/humanlayer/skills> — `plugins/show-me/skills/show-me` |
| Commit | `4d69d20f6e9b57b4fcf0d501ccfb1be961f0f329` |
| License | MIT — `skills/show-me/LICENSE` (Copyright (c) 2026 HumanLayer) |

**Local changes**

- `SKILL.md` is byte-identical to upstream (md5 `02b8b71f5f6f5669323e8558f6981f14`).
- `LICENSE` was **added** to the skill directory. Upstream has no LICENSE inside
  `plugins/show-me/skills/show-me/`; this file is a verbatim copy of the
  repository-root `LICENSE` at the pinned commit, placed here so the MIT terms
  travel with the vendored directory.

**Note for Tim:** the build brief said show-me's local changes are described in
a comment at the top of its frontmatter. There is no such comment, and the
`SKILL.md` has no local changes at all — so this table, not the skill file, is
the record. The brief also said the LICENSE is upstream "in its folder"; it is
not, it is the repo-root license.

`disable-model-invocation: true` in its frontmatter is upstream, not a local
change. OMP normalizes that key to `disableModelInvocation` and reads it as
`hide` (`reference/omp/skills.md`), so show-me is never listed in the system
prompt and is reached only as `/skill:show-me` or `skill://show-me`.

### `skills/ub-mode`

| | |
| --- | --- |
| Source | <https://github.com/unclebob/ub-mode> — repository root (`SKILL.md`, `LICENSE`) |
| Commit | `3da62bf3fcfd2034de41f30d920d2739e566171f` |
| License | MIT — `skills/ub-mode/LICENSE` (Copyright (c) 2026 Robert C. Martin) |

**Local changes**

- None. `SKILL.md` and `LICENSE` are both byte-identical to upstream.

**Note for Tim:** the brief gave the source path as
`plugins/ub-mode/skills/ub-mode`. That path does not exist at this commit — the
repository tree is exactly `LICENSE`, `README.md`, `SKILL.md` at the root, and
the vendored files match the root copies. The brief also said local changes are
described in a comment at the top of the frontmatter; there is no such comment
and there are no local changes.

### `skills/mags-manifest-design`

| | |
| --- | --- |
| Source | <https://github.com/TimothyStephens/MAGS-CodeDev> — `mags-codedev-extension/skills/mags-manifest-design` |
| Commit | `63e0271ae259e973123984fa065b6d00572a277a` |
| License | Tim's own project; no separate license file vendored |

**Local changes**

- None. `SKILL.md` is byte-identical to upstream.

## Vendored documentation

### `reference/omp/`

| | |
| --- | --- |
| Source | <https://github.com/can1357/oh-my-pi> — `docs/` |
| Commit | see [`reference/omp/SOURCE_COMMIT`](reference/omp/SOURCE_COMMIT) (`5dc44d3417722796fd96e8be6bee4712023d1667`) |
| License | upstream project license; vendored for reference only |

**Local changes**

- None; kept as received. These files are the format spec this repo's READMEs
  and `tools/check.py` cite. Not shipped into a session — `reference/` is not
  one of the directories agentbox mounts.

## Declared, not vendored

Plugins in [`plugins.toml`](plugins.toml) are installed by agentbox at
`ab profile install omp`, from their own marketplaces at the pinned refs. No
plugin content lives in this repository.
