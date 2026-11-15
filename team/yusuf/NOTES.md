# Yusuf's notes

Personal handoff notes for Yusuf's next session (and for Yusuf's coding agent). Only Yusuf edits this file.
The shared board is [STATUS.md](../../STATUS.md); finished work goes in [WORKLOG.md](../../WORKLOG.md).

## Working on now

Session #1, Sun 2:40 am: T38 is merged (PR #34). T39 (`yusuf/small-fixes`, PR #35) and T41 (`yusuf/review-fixes`, PR #37, stacked on it) are pushed and queued. Everything earlier is merged (T05, T06, T07, T16, T17, T20, T25, T29, T30, T32, T33).

## Pushed, waiting for a Mac mini test

- `yusuf/review-fixes` (T41) contains `yusuf/small-fixes` (T39). Merge #35 first, then #37; or only #37 and close #35. The riskiest change is the microphone gate in call mode (`micHearsSpeakers` in `AppState.swift`): if "You" lines never appear live, `CLUELESS_MIC_GATE=0`.
- Option+S stops after the sentence being spoken, not mid-word (core change suggested to Aziz in the work log, not made).
- Still needing a person (T28 and T01, T02, T11, T12): hotkeys, a typed and a spoken question, the server warning row, capture restart, speech order by ear, long-card scroll, receipts click. Real look-aways work (in-person log, Sat 10:45 pm: 4 of 4 cards, 31 short glances ignored).

## Ideas and things to remember

- This MacBook (8 GB) must not run the models, servers or app: it lagged badly both times. `swift build` only.
- `models/` and `vendor/` exist on the MacBook and are to be kept, unused.
- Never use `@State` in the app: the Mac mini has no Xcode and cannot compile it. `@StateObject`, `@Binding`, `@FocusState`-free alternatives or `AppState` instead. The MacBook's `swift build` does not catch this.
