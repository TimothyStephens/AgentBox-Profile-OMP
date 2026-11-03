# prompts/

Prompt templates for every OMP session. agentbox mounts this directory
read-only at `~/.omp/agent/prompts`.

## Status: format not fully specified here — Tim to confirm

**The vendored reference set does not document this directory.** The OMP docs in
`reference/` (at commit `reference/omp/SOURCE_COMMIT`) mention prompt templates
only indirectly, and the doc that would describe them — `magic-keywords.md`,
referenced from
[`reference/omp/settings.md:11`](../reference/omp/settings.md) as "prompt words
that activate specialized per-turn behavior" — is **not vendored**.

What the vendored docs do establish:

- Prompt templates are a real, separate expansion stage.
  [`slash-command-internals.md` §5](../reference/omp/slash-command-internals.md)
  runs `expandPromptTemplate` **after** file-based slash-command expansion, and
  `expandPromptTemplates: false` bypasses all four expansion stages.
- Discovered prompt templates also register as slash commands, but only when
  their name is not already taken by a built-in, hook, custom, skill or file
  command ([§4](../reference/omp/slash-command-internals.md)).
- `prompts` is a capability contributed by the `omp-plugins` discovery provider
  ([`context-files.md`](../reference/omp/context-files.md), "Discovery
  providers"), alongside skills, commands, rules and hooks.

What is **unverified** and must not be guessed at: the exact filename-to-name
mapping, the frontmatter schema (in particular whatever field holds the magic
keywords that trigger a template), and whether matching is per-turn or
per-prompt.

Until Tim confirms the schema (by vendoring `magic-keywords.md`, or from the
OMP source), this directory ships empty and `./build.sh check` applies only
conservative structural rules:

- `prompts/*.md` only — any other extension is an error.
- No subdirectories.
- Frontmatter, if present, must parse.
- A missing `description` is a **warning**, not an error, because the real
  requirement is unknown.

Do not add a prompt template here on the strength of a guess; put the candidate
in `/run/agentbox/claude/inbox` instead and let Tim decide.
