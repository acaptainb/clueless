# Yusuf's notes

Personal handoff notes for Yusuf's next session (and for Yusuf's coding agent). Only Yusuf edits this file.
The shared board is [STATUS.md](../../STATUS.md); finished work goes in [WORKLOG.md](../../WORKLOG.md).

## Working on now

T05 look-away trigger, branch `yusuf/look-away`. Code is pushed and compiles. Waiting for the Mac mini.

## Pushed, waiting for a Mac mini test

- `yusuf/look-away` (T05). Likely tuning after the live test: `maxAngle` (0.52 rad) and `awayAfter` (3 s) in `Presence.swift`; minimum absence for a card (5 s) in `AppState.presenceChanged`. Uses the system default camera; if the Mac mini picks the wrong one, select the device explicitly in `Presence.configure`.

## Ideas and things to remember

- This MacBook (8 GB) must not run the models, servers or app: it lagged badly both times. `swift build` only.
- `models/` and `vendor/` exist on the MacBook and are to be kept, unused.
