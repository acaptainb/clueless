# Yusuf's notes

Personal handoff notes for Yusuf's next session (and for Yusuf's coding agent). Only Yusuf edits this file.
The shared board is [STATUS.md](../../STATUS.md); finished work goes in [WORKLOG.md](../../WORKLOG.md).

## Working on now

T30 (`yusuf/look-away-start`) and the T25 fix (`yusuf/voice-ask`): both pushed, compile-checked, waiting for the Mac mini.

Merged so far: T05, T16, T17, T07, T29, T20. T06 (`yusuf/receipts`) was written in the second MacBook session and is in the queue.

## Pushed, waiting for a Mac mini test

- `yusuf/look-away-start` (T30, PR pending merge on PASS).
- `yusuf/voice-ask` (T25). Voice processing is off by default now. If the lecture leaks into spoken questions too much, options: `CLUELESS_VOICE_PROCESSING=1` if it no longer costs transcript lines with minimal ducking, or drop the feature (it is optional).
- In-person tests for everything are deferred to the end: T28 in STATUS.md.

## Ideas and things to remember

- This MacBook (8 GB) must not run the models, servers or app: it lagged badly both times. `swift build` only.
- `models/` and `vendor/` exist on the MacBook and are to be kept, unused.
