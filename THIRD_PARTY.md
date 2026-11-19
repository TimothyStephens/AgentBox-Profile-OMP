# Third-party content

Everything vendored into this profile. Update this file in the same commit that
adds, moves or edits vendored content.

As in the sibling Claude profile repo, every entry carries the same six fields: **name**,
**source URL**, **path**, **commit**, **license**, **local changes**.

No skill is vendored here at the moment. `show-me`, `ub-mode` and
`mags-manifest-design`, with the other skills shared by every agentbox profile,
moved to the `agentbox-skills` repository on 2026-11-19 (see
`docs/decisions.md`). Their provenance, pinned commits, licences and local
changes are recorded in that repository's
[`THIRD_PARTY.md`](https://github.com/TimothyStephens/AgentBox-Skills/blob/main/THIRD_PARTY.md).

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

- `egm@egm` — Elephant Goldfish Model, <https://github.com/google/elephant-goldfish-model>.
- `agentbox@agentbox-skills` — the skills shared by every agentbox profile,
  <https://github.com/TimothyStephens/AgentBox-Skills>. Third-party skills in
  it are vendored there, and its `THIRD_PARTY.md` is their record.
- The `[[npm]]` and `[[repo]]` entries, each at the version or commit pinned in
  `plugins.toml`.
