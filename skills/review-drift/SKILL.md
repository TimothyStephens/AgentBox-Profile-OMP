---
name: review-drift
description: >
  Review another agent's work for scope creep and drift from a plan, from a clean context.
  Takes the baseline (a design doc, task, or plan file) and a git range. Use when the user
  runs /review-drift, typically in a reviewer project (`ab project add --review-of`).
disable-model-invocation: true
---

# review-drift

You are reviewing work you did not write, and you should not know how its author thought
about it. That is the point: judge what the code and its history do against what was asked,
not against the author's account of it.

## Inputs

The user gives you, or you ask for:

1. **The baseline**: the file(s) that say what was supposed to be built (a design doc, a task,
   a plan, `docs/decisions.md` entries). If there is none, say so and stop: a scope review with
   no scope is guessing.
2. **The range**: a git range such as `main..HEAD` or `<base-commit>..HEAD`, and whether
   uncommitted work (`git status`, `git diff`) is in scope. Default: the range plus uncommitted
   work.

## Rules

- Read the baseline **first**, completely, and write down its items before looking at code.
- Commit messages, comments, docs and TODOs written in the range are **claims**, not evidence.
  Check each claim you rely on against the diff.
- Do not ask the author, read their notes, or look for their transcripts. If something is
  ambiguous, report the ambiguity.
- You may not be able to write to the tree (a reviewer's root is read-only). Do not try to
  fix anything; report it.
- Tag each finding: **[Certain]** you read it in the diff or ran it; **[likely]** a strong
  inference; **Guessing** filling a gap.

## Procedure

1. List the baseline items (B1, B2, ...).
2. `git log --stat <range>` and `git diff <range>` (plus `git diff` / `git status` for
   uncommitted work). Group the changes by intent.
3. Trace every change group to a baseline item. A group that traces to none is **scope creep**.
4. For every baseline item, find where it was done. Done differently from the baseline is
   **drift**; not done is **missing**.
5. Look for **silent changes**: behaviour, defaults, rules or tests that changed without the
   baseline or `docs/decisions.md` saying so. Weakened or deleted tests count.
6. Only then, correctness problems you happened to see; this skill is not a full code review.

## Report

Lead with the most serious finding. Then:

```
Baseline: <files>     Range: <range> (+ uncommitted: yes/no)

Scope creep      <change> -- <file:line> -- traces to no baseline item  [tag]
Drift            B<n>: baseline says <x>; the code does <y> -- <file:line>  [tag]
Missing          B<n>: <item> -- not found in the range  [tag]
Silent changes   <what changed, where, and that nothing records it>  [tag]
Other            <correctness issues seen in passing>  [tag]

Traced cleanly   B1, B3, ...
```

An empty section is written as `none`. Do not pad: a short, true report is the useful one.
