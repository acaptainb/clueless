# Yusuf's notes

Personal handoff notes for Yusuf's next session (and for Yusuf's coding agent). Only Yusuf edits this file.
The shared board is [STATUS.md](../../STATUS.md); finished work goes in [WORKLOG.md](../../WORKLOG.md).

## Working on now

T07 speak early (`yusuf/speak-early`, PR #12) and T06 screen receipts (`yusuf/receipts`, PR #15). Both are pushed and compile. Waiting for the Mac mini. T05, T16, T17 are merged. Next candidate: T20. Aziz also asked in the work log for call notes to be wired into the app.

## Pushed, waiting for a Mac mini test

- `yusuf/voice-ask` (T25). If voice processing causes trouble (ducked speakers, broken system-audio capture), remove the two `setVoiceProcessingEnabled` lines in `VoiceAsk.swift` and accept that the lecture bleeds into the question.
- `yusuf/hud` (T20). Never seen on screen: the top row may be too wide for the 420 pt panel.
- `yusuf/receipts` (T06). It was written in a separate working copy, `.worktrees/receipts`, because the main folder was on `yusuf/speak-early`. Watch for: the Clueless panel showing up inside the saved screenshot; the thumbnail making the card taller than the panel. T06 and T07 both edit `AppState.run`; a trial merge of the two was clean.
- `yusuf/fresh-catchup` (T29): the fix for cards missing the last few seconds. Waiting for the Mac mini.
- In-person live tests for T05, T16, T17 are deferred to the end: see T28 in STATUS.md. T05 will likely need `maxAngle` / `awayAfter` tuning in `Presence.swift`.

## Ideas and things to remember

- This MacBook (8 GB) must not run the models, servers or app: it lagged badly both times. `swift build` only.
- `models/` and `vendor/` exist on the MacBook and are to be kept, unused.
