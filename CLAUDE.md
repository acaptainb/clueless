# Clueless: instructions for coding agents

Two people work on this repo at the same time, each with their own AI coding tool. These rules exist
so nobody builds the same thing twice.

The project brief is the source of truth for what to build. The status board says who is doing what:

@BRIEF.md
@STATUS.md

History of finished work is in WORKLOG.md. Measurements are in BENCHMARKS.md.

## At the start of every session

1. `git fetch` and bring your branch up to date with `origin/main`.
2. Read STATUS.md as it is on `origin/main`, and the last entries of WORKLOG.md.
3. Work out who you are working for from `git config user.name` or `gh api user`, and match it to the
   People table in STATUS.md. Ask if it is not clear.

## Before starting any task

- Find it in STATUS.md. If it is under "Done", say so, point at where it landed, and do not redo it.
- If it is under "In progress" for the other person, say so and stop. Suggest an unclaimed task instead.
- If the request is not on the board, add it to "Up next" with a new ID first.
- Claim it: move its line into "In progress" with your person's name, branch and time, then commit only
  STATUS.md and push that commit straight to `main`. The claim must be on `main` before the work starts,
  otherwise the other person cannot see it.

## While working

- One branch per task, named `<person>/<topic>` (for example `yusuf/lookaway`). Never commit code to `main`.
- Stay inside your role's folders (see People in STATUS.md). If you need a change in the other person's
  folder, ask for it in WORKLOG.md or make it a separate small PR.
- Do not change the shared interface (`TimelineLine`, `Watcher.watch`, `Answerer.answer`, `Card`) without
  a WORKLOG.md entry marked CONTRACT in the same PR.
- Performance and reliability come first. Measure before and after with `clueless-bench`, and put the
  numbers in BENCHMARKS.md.

## When finishing a task

In the same PR as the code:
- Move the task from "In progress" to the top of "Done" in STATUS.md, and update the milestone table.
- Append one line to WORKLOG.md: what changed, what was measured, anything the other person must do.

Before merging the PR into `main`:
- `swift build -c release` passes.
- With the servers running, `clueless-bench answer` is still 10/10 and `clueless-bench watch` is still
  16/16. If a score drops, fix it or say why in the PR.
- Merge `origin/main` into the branch first and rebuild.

Tag `main` at each milestone (`m1`, `m2`, ...). If you stop a task without finishing, remove your claim
and leave a WORKLOG.md line saying how far it got.

## Commits

No co-author or "generated with" lines in commits or pull requests.
