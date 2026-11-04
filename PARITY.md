# Profile parity contract (identical in both profile repos)
- Shared: the instruction-file core block; build.sh commands check, status, deploy, install,
  all; exit codes 0 ok, 1 check failed, 2 refused (inside a session, or live dir not a clean
  clone), 3 ab lacks the command; THIRD_PARTY.md format (name, source URL, path, commit,
  license, local changes); the Containerfile (ARG BASE / FROM ${BASE}, neovim 0.10.4 with
  sha256 check, EDITOR=nvim and VISUAL=nvim, nothing else); plugins.toml format; README.md
  section order; docs/<load-directory>.md, one file per load directory, holding the format
  documentation that may not sit inside the directory it documents.
- check, shared rules: skills one level deep, name == dir name, name pattern; documented
  frontmatter keys pass, unknown keys warn; no symlinks or files over 1 MB in tracked paths;
  .env*, *.pem, id_* are errors anywhere, .dev/ included; .dev/ is otherwise skipped (it is
  gitignored and never deployed); only the documented top-level entries; load directories hold
  only loadable items (no README*, no non-loadable file; the load directories are skills/,
  agents/, commands/, plus OMP's rules/ and prompts/).
- tests: every shared rule has a pass case and a fail case, with the same names in both repos.
- Allowed differences: the instruction file name; the "## This harness" section; harness
  directories (Claude: settings.json; OMP: rules/, prompts/); the frontmatter key sets; the
  live path and the ab agent name.
