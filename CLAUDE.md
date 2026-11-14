# Clueless: instructions for coding agents

Two people work on this repo at the same time, each with their own AI coding tool. These rules exist
so nobody builds the same thing twice.

The project brief is the source of truth for what to build. The status board says who is doing what:

@BRIEF.md
@STATUS.md

History of finished work is in WORKLOG.md. Measurements are in BENCHMARKS.md.

## Where code runs

- **Laptops are for writing code only.** Do not build, run, test, install models or start servers on a
  laptop. Aziz's laptop runs Windows and cannot build the app at all; do not try.
- **The Mac mini is the only build and test machine.** Its checkout at `/Users/captain/clueless` holds the
  models, the llama.cpp fork and the app's permissions. See "Machines" in STATUS.md.
- On a laptop, "done coding" means: pushed to your branch and added to the "Mac mini test queue" in
  STATUS.md. Say clearly that the change is untested. Never report a task as working until
  `./scripts/check.sh <branch>` has passed on the Mac mini.
- On the Mac mini: more than one person uses it, so ask who you are working for if it is not obvious.
  Before a live test, check "Mac mini in use right now by" in STATUS.md, set it to your person, and clear
  it when you finish. Run one check or live test at a time.
- Code written without a compiler breaks easily. Keep laptop changes small, one task per branch, so a
  failed build on the Mac mini is quick to find and fix.

## At the start of every session

1. `git fetch` and bring your branch up to date with `origin/main`.
2. Read STATUS.md as it is on `origin/main`, and the last entries of WORKLOG.md.
3. Work out who you are working for (Aziz or Yusuf) and which machine you are on. On a laptop,
   `git config user.name` usually tells you. On the shared Mac mini it does not: ask.

## Before starting any task

- Find it in STATUS.md. If it is under "Done", say so, point at where it landed, and do not redo it.
- If it is under "In progress" for the other person, say so and stop. Suggest an unclaimed task instead.
- If the request is not on the board, add it to "Up next" with a new ID first.
- Claim it: move its line into "In progress" with your person's name, branch and time, then commit only
  STATUS.md and push that commit straight to `main`. The claim must be on `main` before the work starts,
  otherwise the other person cannot see it. (Edits to STATUS.md, WORKLOG.md and `team/` are the only
  things that may go straight to `main`.)

## While working

- One branch per task, named `aziz/<topic>` or `yusuf/<topic>`. Never commit code to `main`.
- Personal notes for the next session (what is half done, what to test next) go in `team/aziz/NOTES.md` or
  `team/yusuf/NOTES.md`. Only edit your own.
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
- Merge `origin/main` into the branch and push.
- On the Mac mini, `./scripts/check.sh <branch>` prints PASS (build ok, questions 10/10, watcher at most one
  miss, catch-up at least 2 of 3). Paste the PASS line into the PR. If it fails, fix it or say why in the PR.
- If the change touches capture, the panel, speech or anything else the benchmarks cannot see, also run
  `./scripts/check.sh <branch> app` and try it live.

Tag `main` at each milestone (`m1`, `m2`, ...). If you stop a task without finishing, remove your claim
and leave a WORKLOG.md line saying how far it got.

## Commits

No co-author or "generated with" lines in commits or pull requests.
