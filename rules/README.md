# rules/

Rule files for every OMP session. agentbox mounts this directory read-only at
`~/.omp/agent/rules`, which the **native** rule provider (priority 100) loads as
user rules: `<active-native-agent-dir>/rules/*.{md,mdc}`.

Reference:
[`reference/omp/rulebook-matching-pipeline.md`](../reference/omp/rulebook-matching-pipeline.md).

## Layout

`rules/<name>.md` or `rules/<name>.mdc`, one level, non-recursive. The rule
**name is the filename without its extension** — frontmatter cannot rename it.
Rule identity is the name alone, so two files with the same stem are the same
logical rule and the lower-precedence one is shadowed.

`RULES.md` (sticky, always-apply) is **not** part of this directory; it would
live at `~/.omp/agent/RULES.md`, which agentbox does not mount from this repo.

## Frontmatter

Every key is optional, but a rule that sets none of `description`,
`alwaysApply: true`, `condition`, `astCondition` or `question` joins no bucket:
it is invisible in the system prompt and not addressable via `rule://<name>`.
`./build.sh check` treats that as an error.

| Key | Effect |
| --- | --- |
| `description` | Required for the **rulebook** bucket: the rule is listed by name + description and the model reads `rule://<name>` on demand. |
| `alwaysApply: true` | **Always-apply** bucket: the full body is injected into every system prompt. Wins over `description` (a rule with both is always-apply only). |
| `globs` | Rendered beside the rulebook listing; used as a path gate for TTSR matching. Does **not** auto-select rulebook rules. |
| `condition` | Regex TTSR trigger. A value that looks like a file glob is rewritten to `tool:edit(<glob>)` + `tool:write(<glob>)` scope with catch-all condition `.*`. |
| `astCondition` | ast-grep structural pattern(s); matched against finalized edit/write snapshots. |
| `question` | One natural-language yes/no question answered by the `judge` role about completed output. Never interrupts. |
| `scope` | Narrows TTSR surfaces: `text`, `thinking`, `tool`, `tool:<name>(<glob>)`. Default is `text` + `tool`. |
| `agents` | Glob list of agent names the rule applies to. `main` = top-level session, `sub` = an unnamed subagent. Omitted = every agent. |
| `interruptMode` | `never` / `prose-only` / `tool-only` / `always`; overrides the global TTSR interrupt mode. |
| `enabled: false` | Excluded before name deduplication. |

A rule with a trigger goes to **TTSR only** if `TtsrManager` accepts it, even
when it also sets `alwaysApply` or `description`.

## Authoring notes

- Always-apply bodies are deduped against the system/custom/append prompt and
  loaded context files: identical content is not injected twice.
- Keep always-apply rules short — they ride on every request.
- Subagents re-evaluate `agents` under their own name, so `agents: main` keeps a
  rule out of every subagent.
