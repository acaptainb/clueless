# Yusuf's notes

Personal handoff notes for Yusuf's next session (and for Yusuf's coding agent). Only Yusuf edits this file.
The shared board is [STATUS.md](../../STATUS.md); finished work goes in [WORKLOG.md](../../WORKLOG.md).

## Working on now

Session #1, Sun 1:45 am: nothing claimed, nothing open. T38, T39, T41 and the README update are merged (PRs #34 to #37).

## Pushed, waiting for a Mac mini test

- Nothing. `main` after the last merges is compile-checked on the MacBook only: one `check.sh main` is asked for in the work log.
- Everything left needs a person at the Mac mini: `team/yusuf/SHIP.md`. If "You" lines never appear in call mode on the loudspeakers, launch with `CLUELESS_MIC_GATE=0`.
- Option+S stops after the sentence being spoken, not mid-word (core change suggested to Aziz in the work log, not made).

## Ideas and things to remember

- This MacBook (8 GB) must not run the models, servers or app: it lagged badly both times. `swift build` only.
- `models/` and `vendor/` exist on the MacBook and are to be kept, unused.
- Never use `@State` in the app: the Mac mini has no Xcode and cannot compile it. `@StateObject`, `@Binding`, `@FocusState`-free alternatives or `AppState` instead. The MacBook's `swift build` does not catch this.
