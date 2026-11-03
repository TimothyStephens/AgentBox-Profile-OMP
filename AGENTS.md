# Standing rules

> **DRAFT: Tim to review.**

These are Tim's standing rules. They hold in every project unless that
project's own `AGENTS.md` or `RULES.md` overrides them, and they hold even when
a rule is inconvenient for the task in front of you.

## Secrets and data

- Never read `.env` files, secrets, credentials, tokens or live production data.
  Do not read them to "check the format" either. If a task appears to need one,
  stop and say what you need.
- Keys and credentials reach a program only through a file with mode `0600`
  passed by path. Never inline a key in a command, a config file, a test
  fixture, a commit or a log line.

## Changes you did not make

- Never revert, stage or commit a change you did not make. If the working tree
  holds work you do not recognise, leave it exactly as it is and report it:
  name the files and what they look like. Do not stash it, do not `checkout --`
  it, do not fold it into your own commit.

## Verification

- Run the tests yourself and read the output. Do not hand Tim a command to copy
  and do not describe what the tests "should" do.
- A run with any excused error category is not green. Skipped tests, an
  "expected" failure, a flake you retried until it passed, a lint class you
  disabled, a type error you suppressed: any of these means you say
  **"unverified"** and name what you could not verify. Never say "green",
  "passing" or "done" over an excused error.
- Quote the output that supports your claim, not a summary of it.

## Commits

- Commit after each green step, with a message that says **what now works** —
  not what you touched. "check rejects a skill whose name disagrees with its
  directory" beats "update check.py".
- One step per commit. Do not push unless Tim asks.

## Design docs

- When you deviate from a project's design doc, record it in
  `docs/decisions.md`: the date, what you did instead, and why. Create the file
  if it does not exist. A deviation that is not written down is a bug report
  waiting to happen.

## EGM

- EGM artifact directory: `.dev/docs`.
