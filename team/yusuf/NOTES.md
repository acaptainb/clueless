# Yusuf's notes

Personal handoff notes for Yusuf's next session (and for Yusuf's coding agent). Only Yusuf edits this file.
The shared board is [STATUS.md](../../STATUS.md); finished work goes in [WORKLOG.md](../../WORKLOG.md).

## Working on now

(nothing claimed in session #1) Merged: T05, T16, T17, T07, T29, T20, T30, T25. T06 (`yusuf/receipts`, session #2) fails to build on the Mac mini because of `@State`; session #2 has been told.

## Pushed, waiting for a Mac mini test

- Nothing from session #1. `main` after the T30 and T25 merges is compile-checked on the MacBook only.
- In-person tests for everything are deferred to the end: T28 in STATUS.md.

## Ideas and things to remember

- This MacBook (8 GB) must not run the models, servers or app: it lagged badly both times. `swift build` only.
- `models/` and `vendor/` exist on the MacBook and are to be kept, unused.
- Never use `@State` in the app: the Mac mini has no Xcode and cannot compile it. `@StateObject`, `@Binding`, `@FocusState`-free alternatives or `AppState` instead. The MacBook's `swift build` does not catch this.
