# Status board

The live answer to "who is doing what". Read it before starting anything; update it when you claim,
finish or drop a task. History of finished work is in [WORKLOG.md](WORKLOG.md). Rules are in
[CLAUDE.md](CLAUDE.md).

Last updated: Sat Nov 14, 6:30 pm ET by Aziz

## People

| Person | GitHub | Codes on | Role | Branch prefix | Notes folder |
|---|---|---|---|---|---|
| Aziz | `acaptainb` | Windows laptop (cannot build or run the app). Also the person usually at the Mac mini | B, the engine, and Mac mini runner | `aziz/` | `team/aziz/` |
| Yusuf | `yusuf-2007` | MacBook, M2. Can compile Swift as an error check; cannot run the models or the app | A, the app | `yusuf/` | `team/yusuf/` |

All work before Sat 5:50 pm was done by Aziz at the Mac mini.

## Roles in detail

**Role B, the engine: what the app thinks and says.** Folders: `Sources/CluelessCore/`, `Sources/clueless-bench/`, `scripts/`.
- Owns: the prompts, the Bonsai servers and their speed, the watcher, speaker labels and names, session
  notes, the benchmark test sets, the demo assets (lecture video, PDF, recorded call).
- Tasks: T04, T08, T09, T10, T13, T14, T15, T19, T21, T26.
- How it is tested: almost entirely by `./scripts/check.sh`, which gives scores and timings with nobody
  watching the screen. That is why it suits a laptop that cannot compile.
- Success looks like: same or better scores, lower latency numbers in BENCHMARKS.md.

**Role A, the app: what the user sees, hears and triggers.** Folder: `Sources/Clueless/`.
- Owns: screen and audio capture, the floating panel, hotkeys, the webcam look-away trigger, spoken
  answers, the HUD, restarting things when they fail.
- Tasks: T01, T02, T03, T05, T06, T07, T11, T12, T16, T17, T20, T25.
- How it is tested: live, at the Mac mini, by a person looking and listening (`check.sh <branch> app`).
  The benchmarks cannot see any of it, so this role needs the most Mac mini time.
- Success looks like: every trigger works first time, nothing hangs, the demo runs for 20 minutes.

**Shared.** T18 (soak test), T22 (reaching the Mac mini), T23 (video), T24 (submission), and the interface
between the two halves: `TimelineLine`, `Watcher.watch`, `Answerer.answer`, `Card`. `AppState.swift` connects
the halves: A owns it; when B adds a capability, B writes it in the core and A wires it into the app.

**Mac mini runner.** Whoever is at the Mac mini (or the coding agent running on it) works through the test
queue: runs `check.sh` on queued branches, does the live tests, merges what passes, records the result.

## Machines

**Laptops are for writing code only. Nothing is run or tested on a laptop.** One exception: Yusuf's MacBook
may run `swift build` to catch compile errors before pushing. That is an error check, not a test; the
Mac mini result is the only one that counts.

**The Mac mini is the only build and test machine** ("James's Mac Mini", M6, 32 GB, macOS 27).
- Checkout: `/Users/captain/clueless`. It holds everything that is not in git: `models/`, `vendor/llama.cpp`,
  and the Screen Recording permission for Clueless.app.
- Attached: onn 4K webcam with microphone (needed for the look-away trigger and call mode).
- Test a pushed branch: `./scripts/check.sh <branch>` (build + benchmarks, prints PASS or FAIL).
  Add `app` to also launch that branch's app for a live test.
- One test at a time. The servers, screen and speakers are shared, so check the table below first.

## Mac mini test queue

Code is not done until it has passed on the Mac mini. After pushing a branch, add a line here (push the
STATUS.md change straight to `main`). Whoever runs the test fills in the result and removes the line
once the PR is merged.

Mac mini in use right now by: nobody

| Branch | Who | What to test beyond `check.sh` | Result |
|---|---|---|---|
| `yusuf/look-away` | Yusuf | T05. `check.sh yusuf/look-away app`, Call or Study mode, something playing. (1) Camera prompt appears; allow it; eye icon shows in the header. (2) Turn your head away or leave for 10 s while audio plays, look back: a "While you looked away" card appears within about 1 s of returning. (3) A 1 to 2 s glance away does nothing. (4) Look away with silence: no card. (5) Pause capture: camera light goes off. If it fires too easily or not at all, note it: the angle (`maxAngle`) and timing (`awayAfter`) in `Presence.swift` need tuning on the real webcam. No-person check: launch with `CLUELESS_AUDIO_FILE=<wav> CLUELESS_TEST_LOOKAWAY=20` and a card should appear about 50 s in | not run yet |
| `yusuf/capture-restart` | Yusuf | T17. `check.sh yusuf/capture-restart app`, play a lecture. (1) IMPORTANT, check first: leave the Mac silent for 60 s. The transcript must stay "Listening" with no "Capture restarted" lines in `.run/app.log`. If it restarts in silence, the stream sends no buffers when quiet and the 15 s stall check (`captureStallSeconds` in `CaptureRestart.swift`) must be raised or removed. (2) Put the display to sleep for 20 s and wake it, or unplug and replug the monitor: status shows "Restarting", then "Listening" again, and the transcript continues. (3) Click the screen-sharing icon in the menu bar and stop sharing: the app goes to paused and does NOT restart. (4) Press pause: stays paused. (5) Switch Study to Call and back: still listening | not run yet |
| `yusuf/server-health` | Yusuf | T16. `check.sh yusuf/server-health app`. (1) With the servers stopped (`servers.sh stop`), launch the app: an orange row says it is starting the servers, it clears in about 20 s, both HUD dots go green, a question works. (2) While the app runs, `kill $(cat .run/answerer.pid)`: within about 5 s the row appears and the servers restart by themselves; a question asked meanwhile gets a "still starting" card, not a hang. (3) `kill $(cat .run/watcher.pid)` only: the row says the watcher is down and offers Restart; nothing restarts until the button is pressed; questions still work. (4) Ask a long question and confirm the servers are NOT restarted while it is answering | not run yet |
| `aziz/prompts-data` | Aziz | T26. Engine only, so `check.sh aziz/prompts-data` is the whole test; it was written on Windows and has never been compiled, so expect to paste build errors back. (1) Build ok and PASS with the same scores as `main` (questions 10/10, watcher 15 or 16 of 16, catch-up 2 or 3 of 3). (2) The answer output has a line `== prompts: all 5 from prompts/*.txt`. If it says BUILT-IN, the files are not being found. (3) In `.worktrees/check`, `.build/release/clueless-bench prompts` prints five lines that all end "same as built-in". (4) Optional: add the word TEST to the end of `.worktrees/check/prompts/watcher.txt`, run `clueless-bench prompts` again and see "differs from built-in" with no rebuild, then `git -C .worktrees/check checkout prompts` | not run yet |

## Milestones

| Milestone | Target | State |
|---|---|---|
| M0 Smoke tests | Sat 4:00 pm | Done except the Wi-Fi-off run (T03). Tagged `m0` |
| M1 Study mode | Sat 7:30 pm | About 80%. Left: T01, T02, T03, T04 |
| M2 Catch-up | Sat 10:30 pm | About 50%. Left: T05, T06, T07 |
| M3 Call mode | Sun 1:30 am | About 30%. Left: T11 to T15 |
| M4 Pro features | only if key arrives | Not started. No key yet |
| M5 Ship | Sun 11:30 am | About 25%. Left: T20 to T24 |

Feature freeze: Sun 2:00 am. Submit by Sun 11:30 am.

### Working timeline (agreed Sat 5:10 pm)

| When | Goal |
|---|---|
| Sat until 6:30 pm | Finish M1, Wi-Fi-off run, tag `m1` |
| Sat 6:30 to 9:30 pm | M2: look-away trigger (A), latency work (B), tag `m2` |
| Sat 9:30 pm to Sun 12:30 am | M3: call mode live, speaker labels, notes with names, tag `m3` |
| Sun 12:30 to 2:00 am | Reliability pass: 20-minute soak test, failure handling, then feature freeze |
| Sun 8:00 to 9:30 am | Demo assets, full rehearsal with Wi-Fi off |
| Sun 9:30 to 11:00 am | Record the video, final README |
| Sun 11:30 am | Submit |

### Priorities: fast, reliable, working

Measured on the Mac mini: transcript lag 2.5 s, watcher 1 s, first words of a card 0.8 s without a screenshot
but 6 s with one, whole card about 6 s. In order of payoff:
1. Screenshot cost (T08). 2. Prompt cache reuse (T09). 3. Speak the first field early (T07).
4. App starts and checks the servers itself, capture restarts itself (T16, T17). 5. Soak test and
Wi-Fi-off rehearsal (T18, T03). Free memory first: the Mac mini was at 27 of 32 GB during the benchmarks.

## In progress

One line per claimed task. Add your line and push it to `main` BEFORE you start work.

| Task | Who | Branch | Started | Notes |
|---|---|---|---|---|
| T05 Look-away trigger: webcam + Vision face detection; looking away then back fires a catch-up | Yusuf | `yusuf/look-away` | Sat 5:45 pm | Written on the MacBook, compile-checked only; needs a live Mac mini test with the webcam |
| T16 App starts and health-checks the Bonsai servers itself; clear message when one is down | Yusuf | `yusuf/server-health` | Sat 5:50 pm | Written on the MacBook, compile-checked only |
| T17 Restart capture automatically if the stream stops | Yusuf | `yusuf/capture-restart` | Sat 5:55 pm | Written on the MacBook, compile-checked only |
| T26 Move the prompts and the benchmark test cases out of Swift into data files | Aziz | `aziz/prompts-data` | Sat 6:05 pm | Written on the Windows laptop, not compiled; needs `check.sh` on the Mac mini |
| T08 Cut the screenshot cost: OCR by default, image only for visual questions, smaller image; bench to measure each | Aziz | `aziz/screenshot-cost` | Sat 11:05 pm | Being written on the Windows laptop, not compiled |

## Up next

Unclaimed. "Suggested" is only a suggestion; whoever claims it in the table above owns it.

### M1 Study mode
| ID | Task | Suggested |
|---|---|---|
| T01 | Verify spoken answers in the live app (TTSKit plays, does not get transcribed back) | Yusuf |
| T02 | Verify hotkeys in the live app: Option+Space ask, Option+C catch-up, Option+S stop speaking | Yusuf |
| T03 | Run the whole app on the Mac mini with Wi-Fi off; record the result in BENCHMARKS.md | Yusuf |
| T04 | Check answer quality on a real lecture video and a real PDF on screen (needs T21 assets) | Aziz |

### M2 Catch-up
| ID | Task | Suggested |
|---|---|---|
| T06 | Receipts for screen sources: save the screenshot, set `snapshot` on the timeline line, show it in the card | Yusuf |
| T07 | Start speaking the first field as soon as it is complete, not after the whole card | Yusuf |

### Performance (the main focus)
| ID | Task | Suggested |
|---|---|---|
| T09 | Keep the prompt prefix identical between requests so the server reuses its cache; measure prompt time | Aziz |
| T10 | Grow the test set to about 20 questions and add real recorded audio, not only synthetic speech | Aziz |
| T19 | The forced cut at 8 s can split a word across two lines: overlap chunks or cut at a word boundary | Aziz |

### M3 Call mode
| ID | Task | Suggested |
|---|---|---|
| T11 | Live test of call mode: microphone = You, system audio = Them (needs Microphone permission) | Yusuf |
| T12 | Name trigger through the watcher, live: saying the user's name produces a catch-up card | Yusuf |
| T13 | Speaker labels at end of session with SpeakerKit on the recorded system audio | Aziz |
| T14 | Resolve speaker names from context ("thanks, Priya") | Aziz |
| T15 | End-of-session notes by speaker, using the names | Aziz |

### Reliability
| ID | Task | Suggested |
|---|---|---|
| T18 | 20-minute soak test: memory, lag and crashes over a long session | both |

### M5 Ship
| ID | Task | Suggested |
|---|---|---|
| T20 | Finish the HUD: latency per stage, RAM including the servers, tokens per second, network off | Yusuf |
| T21 | Demo assets, stored locally: a lecture video, a PDF paper, a 2 to 3 minute multi-speaker call | Aziz |
| T22 | Decide how each person reaches the Mac mini from their laptop (in person, or turn on Remote Login / Screen Sharing) so tests can be started without waiting | both |
| T23 | Record the demo video, under 2 minutes | both |
| T24 | Final README and the Discord submission | both |
| T25 | Optional: ask a question by voice instead of typing | Yusuf |

## Open questions

- Is Apple's built-in OCR fine under the "LLMs must be Bonsai" rule? Ask the organizer.
- Argmax Pro key: requested? received? (decides M4)
- The live demo has to run on the Mac mini (the rules say "own laptop allowed"). Can it be brought to the finals with a screen, keyboard, webcam and speakers? Ask the organizer.

## Done

Newest first. One line each; details and numbers are in WORKLOG.md and BENCHMARKS.md.

| Task | Who | When | Where |
|---|---|---|---|
| Mac mini test workflow: `scripts/check.sh`, test queue, laptops are code-only, per-person folders | Aziz | Sat 5:40 pm | `yusuf/mac-mini-workflow` |
| Team tracking: STATUS.md, WORKLOG.md, workflow rules | Aziz | Sat 5:25 pm | `main` |
| Answers stream into the card (first words in 0.8 s) | Aziz | Sat 4:58 pm | PR #1 |
| Live system-audio capture and transcription verified in the app | Aziz | Sat 4:55 pm | PR #1 |
| Screen Recording permission survives rebuilds (signing fix) | Aziz | Sat 4:52 pm | PR #1 |
| Method benchmarks: answerer model, watcher model, screen input, audio chunking | Aziz | Sat 4:10 pm | PR #1, BENCHMARKS.md |
| Study-mode app: capture, floating panel, hotkeys, cards with receipts, HUD basics | Aziz | Sat 4:00 pm | PR #1 |
| Engine core: timeline, Bonsai client, watcher, answerer, chunked transcription, OCR, speech | Aziz | Sat 3:50 pm | PR #1 |
| M0 smoke tests: Bonsai 9B text and image, watcher, Argmax transcribe, speak, diarize | Aziz | Sat 3:40 pm | PR #1, tag `m0` |
| Bonsai servers: llama.cpp fork built from source, 9B/4B/2B models downloaded and checksummed | Aziz | Sat 3:30 pm | `scripts/servers.sh` |
