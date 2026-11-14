# Yusuf's notes

Personal handoff notes for Yusuf's next session (and for Yusuf's coding agent). Only Yusuf edits this file.
The shared board is [STATUS.md](../../STATUS.md); finished work goes in [WORKLOG.md](../../WORKLOG.md).

## Working on now

T07 speak early, branch `yusuf/speak-early`. Code is pushed and compiles. Waiting for the Mac mini. T05, T16, T17 are merged. Next candidates: T06, T20.

## Pushed, waiting for a Mac mini test

- `yusuf/speak-early` (T07). Watch for: generation slowing down while TTS plays; gaps between sentences.
- Seen in the Mac mini look-away test: the catch-up ran before the last few seconds of audio were transcribed ("3 lines missed" logged, 5 in the window). Idea: on a trigger, flush the chunkers (`AudioChunker.flush()`) and wait for the transcription chain before building the card. Not on the board yet.
- In-person live tests for T05, T16, T17 are deferred to the end: see T28 in STATUS.md. T05 will likely need `maxAngle` / `awayAfter` tuning in `Presence.swift`.

## Ideas and things to remember

- This MacBook (8 GB) must not run the models, servers or app: it lagged badly both times. `swift build` only.
- `models/` and `vendor/` exist on the MacBook and are to be kept, unused.
