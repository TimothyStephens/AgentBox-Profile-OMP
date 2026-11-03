# agents/

Task-agent definitions for every OMP session. agentbox mounts this directory
read-only at `~/.omp/agent/agents`, which OMP discovers as **user** agents
(`~/.omp/agent/agents/*.md`).

Reference:
[`reference/omp/task-agent-discovery.md`](../reference/omp/task-agent-discovery.md).

## Layout

`agents/<file>.md`, one level, non-recursive. Files in a directory are read in
lexicographic order. **The agent name comes from frontmatter, not the filename**
— but keep them equal; `./build.sh check` warns when they differ.

Precedence (first wins, exact case-sensitive name match): project
`.omp/agents` → user `.omp/agents` (this directory) → OMP extension packages →
Claude marketplace plugins → bundled agents. So a file here named `reviewer`
replaces the bundled reviewer wholesale — nothing merges, so restate `tools`,
`spawns`, `model` and `output` if the replacement needs them.

## Required frontmatter

| Key | Notes |
| --- | --- |
| `name` | String. `main` and `sub` are reserved (checked after trim + lowercase) and make the definition invalid. |
| `description` | String. Shown to the delegating model in the `task` tool description. |

The body is the agent's `systemPrompt`.

## Optional frontmatter

| Key | Effect |
| --- | --- |
| `tools` | CSV or array. Omitted / YAML-null = default built-in toolset. Any other empty declaration (`[]`, empty CSV, malformed) = **no** built-ins. MCP, extension and custom tools stay additive. |
| `spawns` | `*`, CSV or array of agent names this agent may `task`. Missing `spawns` + `task` in `tools` implies `*`. |
| `model` | One selector, CSV or array, tried in order. `@role` aliases resolve through `modelRoles` in `config.yml` (outside this repo). |
| `thinking-level` / `thinking` | Effort for the agent, clamped by `task.maxEffort`. |
| `output` | Opaque JSON schema; applies only to structured runs (`task.structured`, or `structured: true` here). |
| `structured: true` | Keeps structured results (and the `yield` tool) while `task.structured` is off. |
| `blocking: true` | Parent waits for this agent even with async task execution. |
| `autoloadSkills` | Skill names from the parent session, injected as a hidden message before the first prompt. Unknown names are ignored. |
| `read-summarize: false` | Disables structural read summaries for the child. |
| `prewalk` | `true`, or a target such as `"@smol"`: start on the resolved model, hand off at the first edit/write. |
| `advisor` | `true`, or a model pattern: pair spawned sessions with an advisor. |

## Authoring notes

- Task subagents never inherit `AGENTS.md` (any file whose basename is
  `agents.md`, case-insensitive). Put anything helpers must obey in a rule, not
  in `AGENTS.md`.
- One bad file does not abort discovery: it is logged and skipped. `check`
  catches that before it ships.
- Depth is capped by `task.maxRecursionDepth` (default 2); at the cap `task` is
  removed from the child's tools.
