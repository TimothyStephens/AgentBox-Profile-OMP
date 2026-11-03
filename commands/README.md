# commands/

File-based slash commands for every OMP session. agentbox mounts this directory
read-only at `~/.omp/agent/commands`, which the **native** slash-command
provider (priority 100) loads as the user command set.

Reference:
[`reference/omp/slash-command-internals.md`](../reference/omp/slash-command-internals.md).

## Layout

`commands/<name>.md`, one level, **non-recursive** (`loadFilesFromDir` defaults
to `*.md`; hidden files and gitignored paths are skipped). The command name is
the filename without `.md`, and it is invoked as `/<name>`. Unlike the `claude`
provider, the native provider adds **no** `dir:name` namespace aliases, so
subdirectories here are simply not discovered.

Project `.omp/commands` beats this directory on a name collision. Built-in
commands reserve their names first — a file named `model.md` is never reached.

## Frontmatter

All optional; the body is the template.

| Key | Effect |
| --- | --- |
| `description` | Autocomplete description. Falls back to the first non-empty body line, truncated to 60 chars. `check` warns when it is missing. |
| `argument-hint` | Ghost text in autocomplete / ACP input hints (also accepted as `argumentHint`). |
| `side: true` | Runs the expanded template as a `/btw` side question: off-transcript, non-steering, read-only. Must be the boolean `true` — `"true"` does not count. |

## Argument substitution

Applied in one pass over the body:

| Placeholder | Meaning |
| --- | --- |
| `$1`, `$2`, … | Positional args. Missing values render empty. |
| `$@[start]`, `$@[start:length]` | 1-based slice. Zero/out-of-range renders empty. |
| `$ARGUMENTS`, `$@` | All args. |

Arg parsing is simple quote-aware splitting: `'single'` and `"double"` keep
spaces and the delimiters are stripped; there is **no backslash escaping**, an
unmatched quote consumes to end of input, and empty quoted args are discarded.
Dollar placeholders inside argument *values* are not substituted again.

If the template uses no inline placeholder, the raw argument text is appended.

## Authoring notes

- An unknown `/...` is not an error: it falls through to prompt-template
  expansion and then to the model as literal text.
- There is no file watcher. Commands are re-read at init, on cwd change
  (`/move`), on editor swap and on `/reload-plugins`.
