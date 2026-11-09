# prompts/

Prompt templates for every OMP session. agentbox mounts this directory
read-only at `~/.omp/agent/prompts`. It ships empty.

## What the vendored reference establishes

The OMP docs in `reference/omp/` (at the commit in `reference/omp/SOURCE_COMMIT`)
do not describe this directory's file format. `magic-keywords.md`, which
[`reference/omp/settings.md`](../reference/omp/settings.md) cites for "prompt
words that activate specialized per-turn behavior", is not vendored. What they
do establish:

- Prompt templates are a separate expansion stage.
  [`slash-command-internals.md` §5](../reference/omp/slash-command-internals.md)
  runs `expandPromptTemplate` **after** file-based slash-command expansion, and
  `expandPromptTemplates: false` bypasses all four expansion stages.
- Discovered prompt templates also register as slash commands, but only when
  their name is not already taken by a built-in, hook, custom, skill or file
  command ([§4](../reference/omp/slash-command-internals.md)).
- `prompts` is a capability contributed by the `omp-plugins` discovery provider
  ([`context-files.md`](../reference/omp/context-files.md), "Discovery
  providers"), alongside skills, commands, rules and hooks.

Not specified there, and so not enforced here: the filename-to-name mapping,
the frontmatter schema (including the field that holds the trigger keywords),
and whether matching is per-turn or per-prompt.

## What `check` enforces

Structural rules only:

- `prompts/*.md` only — any other extension is an error.
- No subdirectories.
- Frontmatter, if present, must parse.
- A missing `description` is a **warning**, not an error.

## Adding a template

Vendor the upstream document that specifies the format (`magic-keywords.md`, or
the relevant OMP source) into `reference/omp/`, record it in `THIRD_PARTY.md`,
then tighten `check_prompts` in `tools/check.py` and this file to match. Do not
add a template on the strength of a guess.
