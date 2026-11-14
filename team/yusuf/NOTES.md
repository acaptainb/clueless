# Yusuf's notes

Personal handoff notes for Yusuf's next session (and for Yusuf's coding agent). Only Yusuf edits this file.
The shared board is [STATUS.md](../../STATUS.md); finished work goes in [WORKLOG.md](../../WORKLOG.md).

## Working on now

(nothing claimed) T05, T16, T17 are merged. Next candidates: T06, T07, T20.

## Pushed, waiting for a Mac mini test

- `main` after the three merges needs one `check.sh main`.
- In-person live tests for T05, T16, T17 are deferred to the end: see T28 in STATUS.md. T05 will likely need `maxAngle` / `awayAfter` tuning in `Presence.swift`.

## Ideas and things to remember

- This MacBook (8 GB) must not run the models, servers or app: it lagged badly both times. `swift build` only.
- `models/` and `vendor/` exist on the MacBook and are to be kept, unused.
