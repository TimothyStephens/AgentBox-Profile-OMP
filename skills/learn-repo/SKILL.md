---
name: learn-repo
description: >
  Builds the understanding of an existing repository that the session which wrote it would have had:
  what it is for, how it is put together, why it was built that way, what state it is in, and how to
  build, test and change it safely. Reads only; changes nothing; ends with a sourced briefing and waits
  for instructions. Use when the user runs /learn-repo (or /skill:learn-repo) at the start of a session
  in a repository that already has code, or asks to "learn", "onboard onto" or "get up to speed on" a repo.
disable-model-invocation: true
---

# learn-repo

You are starting work in a repository someone already built. Your goal is to reach the understanding the
session that built it had at the end of its work: not a file listing, but the purpose, the design and the
reasons behind it, the conventions, the current state, and the traps. When you finish, you should be able
to take a task here and do it the way the author would have, without reinventing what exists or breaking
what they protected.

**This skill reads. It does not change anything.** No edits, no commits, no installs, no formatters, no
running the app or the tests unless the user asked for that when invoking this skill. If a step would
write, skip it and say so in the briefing. Do not start any task; when you finish, wait.

## Rules for what you claim

- Every non-obvious claim in the briefing cites where it came from: `path:line`, a commit (`abc1234`), or
  a command's output. A claim you cannot trace is marked **inferred** or left out. An unsourced
  architecture summary is worse than none: it describes what the code was meant to be, not what it is.
- The code and its tests are the truth. Docs, comments and commit messages are evidence of intent; where
  they disagree with the code, report the disagreement instead of picking one.
- Prefer reading a little of many places over all of one place. Skim, then go deep only where the design
  decisions live.

## Scale the effort to the repo

First measure: `git ls-files | wc -l`, the top-level layout, `git log --oneline | wc -l`, and the
languages (file extensions). A small repo (under ~200 files) can be read nearly whole. A large one is read
breadth-first: every top-level directory gets a look, and only the core gets read line by line. If your
harness can run sub-agents in parallel, give each one an area (for example docs + history, entry points +
core, tests + tooling) and have them return sourced findings; otherwise do the passes yourself in order.

## The passes

Work through these in order. Each one feeds the next. Keep notes as you go (in your context, not in the
repo).

1. **The author's own words.** Read the instruction and intent files first, because they are what the
   builder left for whoever came next: `CLAUDE.md`, `AGENTS.md`, `.cursorrules`, `.github/copilot-*`,
   `README*`, `CONTRIBUTING*`, `docs/` (design docs, ADRs, decision logs, specs, proposals), `CHANGELOG*`,
   `TODO*`, `ROADMAP*`. Note the stated purpose, the stated rules, and anything marked as decided or
   rejected, with its reason.

2. **The history: how it got here and why.** Commit messages are the closest record of the builder's
   reasoning.
   - `git log --oneline --decorate -n 60` and `git log --reverse --oneline | head -30` (how it started).
   - `git log --stat -n 15` (what the recent work touched), `git shortlog -sn | head` (who).
   - For the 2-3 most central files you find later: `git log --follow --oneline -- <file> | head -20`,
     and read the messages of the commits that changed the design, not the typo fixes.
   - `git branch -a`, `git status`, `git stash list`: unfinished work, uncommitted changes, other lines of
     work. Uncommitted changes are someone's work in progress; report them, never touch them.
   - Look for reverted commits and "fix"/"revert"/"workaround" messages: they mark where something was
     hard, which is where a newcomer breaks things again.

3. **The perimeter: how it runs.** Before the architecture, find what actually executes:
   - entry points (main modules, CLI definitions, server startup, `bin/`, package `scripts`, `Makefile`
     targets, `__main__`, `cmd/`);
   - the build, test and lint commands as the repo defines them (`Makefile`, `package.json`, `pyproject`,
     `Cargo.toml`, CI workflows in `.github/workflows/` or equivalent: CI is the most honest list of what
     must pass);
   - configuration: where settings come from, environment variables read, config files and their
     defaults (do not read real secret files such as `.env`; their example or template versions are fine);
   - external systems: databases, APIs, queues, files written outside the repo, containers.

4. **The core: how it is put together.** Find the 5-15 files that everything else depends on (the most
   imported, the domain model, the main loop, the public API). Read those properly. For each major
   component, know: its job, its inputs and outputs, what it depends on, and what depends on it. Follow
   one real request or command end to end through the code, from entry point to output.

5. **The tests: what the author protected.** Tests are the spec the builder wrote for themselves. Read the
   test layout, the fixtures and helpers, and the tests of the core files. Note what is tested heavily
   (the author cared, or it broke before), what is not tested at all, and any test that encodes a
   surprising rule. Note how tests are run and whether some need special setup (network, containers,
   credentials, slow markers).

6. **The conventions: how the author writes.** From the code you have read: naming, error handling,
   logging, how modules are split, typing, comment style, how dependencies are added (or avoided), how
   commits are written. The aim is that your future changes look like theirs.

7. **Loose ends and traps.** Collect: TODO/FIXME/HACK/XXX comments (`git grep -n -E "TODO|FIXME|HACK|XXX"`
   , sample them, do not list hundreds), dead or half-finished code, deprecated paths still in use,
   docs that disagree with the code, and anything a comment warns about ("do not", "must", "careful",
   "order matters").

## The briefing

When the passes are done, write one briefing in the conversation (not a file, unless the user asked for
one). Keep it dense; aim for something a reader takes in within five minutes. Use these headings:

1. **What this is** - purpose, users, scope, in two or three sentences. Status: prototype, in use,
   maintained, abandoned?
2. **How it runs** - entry points; the exact build, test and lint commands; configuration; external
   systems.
3. **How it is built** - the components and how they connect (a short list or a small diagram), and the
   one end-to-end path you traced.
4. **Why it is this way** - the key design decisions, each with its reason and source; alternatives that
   were tried or rejected; constraints the author worked under.
5. **Conventions** - what a change must look like to fit in.
6. **Current state** - recent work, work in progress (branches, uncommitted changes, stashes), known
   breakage, open TODOs that matter.
7. **Traps** - the things most likely to go wrong for someone new: fragile areas, surprising rules,
   places where docs and code disagree, what the tests do not cover.
8. **Open questions** - what you could not determine from the repo and would ask the author. Keep it
   short and specific.
9. **Coverage** - what you read fully, what you skimmed, what you did not look at, and anything you
   skipped because it would have written or needed access you do not have.

End with one line saying you are ready for instructions. Then stop and wait. Do not propose a plan of work
unless the user asks.

## Gotchas

- A long README or design doc can describe a plan that was never finished. Confirm against the code
  before you repeat it as fact.
- Generated, vendored and lock files (`dist/`, `build/`, `vendor/`, `node_modules/`, `*.lock`,
  `*_pb2.py`, minified files) are not the author's design. Skip them except to note they exist.
- In a monorepo, find the workspace definition first (`pnpm-workspace.yaml`, `Cargo.toml` workspace,
  `go.work`, root `package.json` workspaces) and brief per package only where it matters.
- If the history is one squashed commit, say so: the "why" then has to come from docs and code alone, and
  more of the briefing will be **inferred**.
- If the session is sandboxed (secret files masked, no network), some config or tests will not be
  reachable. That is expected; list it under Coverage instead of working around it.
