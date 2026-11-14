# Status board

The live answer to "who is doing what". Read it before starting anything; update it when you claim,
finish or drop a task. History of finished work is in [WORKLOG.md](WORKLOG.md). Rules are in
[CLAUDE.md](CLAUDE.md).

Last updated: Sat Nov 14, 6:45 pm ET by Yusuf

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
| `aziz/engine-combined` | Aziz | RUN THIS FIRST, it replaces the two Aziz rows below: T26 + T08 engine + T08 app wiring + `main`, merged with no code conflicts. One `check.sh aziz/engine-combined app` builds all of it; then do the T26 steps and the T08 steps (2) to (6) from the rows below against this branch. If it passes, merge this branch and drop the three separate ones. If the build fails, the error file tells which task: `Prompts.swift` or `loadCases` is T26, `ScreenInput.swift` or `ScreenCost.swift` is T08 | not run yet |
| `aziz/prompts-data` | Aziz | T26. Engine only, so `check.sh aziz/prompts-data` is the whole test; it was written on Windows and has never been compiled, so expect to paste build errors back. (1) Build ok and PASS with the same scores as `main` (questions 10/10, watcher 15 or 16 of 16, catch-up 2 or 3 of 3). (2) The answer output has a line `== prompts: all 5 from prompts/*.txt`. If it says BUILT-IN, the files are not being found. (3) In `.worktrees/check`, `.build/release/clueless-bench prompts` prints five lines that all end "same as built-in". (4) Optional: add the word TEST to the end of `.worktrees/check/prompts/watcher.txt`, run `clueless-bench prompts` again and see "differs from built-in" with no rebuild, then `git -C .worktrees/check checkout prompts` | not run yet |
| `aziz/screenshot-cost`, then `aziz/screenshot-cost-app` | Aziz | T08. Written on Windows, never compiled. (1) `check.sh aziz/screenshot-cost`. (2) Measure: `cd .worktrees/check && .build/release/clueless-bench screencost smoke/shot.png`. Expect `policy: 17/17`, and the `auto` rows at 6/6 with a first-token time close to the `ocr` row (1 image sent out of 6). Paste the table into BENCHMARKS.md. (3) Real full-screen capture: show `smoke/shot.png` full screen, `screencapture -x .run/full.png`, run the bench again on `.run/full.png`. (4) Pick the smallest size whose `both` row is still 6/6 and set it as the default in `ScreenPolicy.imageMaxSide` (`Sources/CluelessCore/ScreenInput.swift`). (5) Optional: restart the servers with `ANSWERER_IMAGE_MAX_TOKENS=256` and rerun; if the fork rejects `--image-max-tokens` the answerer will not start, so unset it. (6) `check.sh aziz/screenshot-cost-app app` (the app wiring, 2 files in `Sources/Clueless/`): the menu shows "Auto" selected; "when is the homework due" answers in about 1 to 2 s and the log line says `image 0 bytes`; "what does the diagram show" attaches the image. Both branches touch one line each in `Bonsai.swift` and `main.swift` that T26 also edits nearby: merge T26 first | not run yet |
| `aziz/demo-assets` | Aziz | T21. No Swift changed, so the build cannot break; this is about the audio. (1) In the branch checkout: `python3 scripts/make_demo_assets.py --user Yusuf`. It should print three different call voices and write `demo/call/call.wav` (about 2 min), six `demo/lecture/audio/slideN.wav` and `demo/lecture/lecture.wav` (about 3 min). If it says not enough English voices, install two more in System Settings > Accessibility > Spoken Content. (2) `afplay demo/call/call.wav`: three clearly different voices, 8 s of silence after each question to the user. (3) Open `demo/lecture/slides.html` full screen, press Start: narration plays and the slides advance by themselves. (4) Open `demo/paper/learning-rate-note.pdf`: page 2 has a chart with three coloured curves. (5) With the app running, try the questions in `demo/README.md` (that part is T04) | not run yet |
| `aziz/servers-one` | Aziz | ONE RUN FOR FIVE BRANCHES: this is `main` + T09 + T19 + T13/T14/T15 + T10 + T27, stacked in that order (`aziz/prompt-cache`, `aziz/word-cut`, `aziz/call-notes`, `aziz/test-set`, `aziz/servers-one`). All written on Windows, never compiled: expect build errors first, likeliest in `Sources/CluelessCore/Speakers.swift` (SpeakerKit calls) and `Sources/clueless-bench/Selftest.swift`. If a later branch will not build, test an earlier one in the stack. (1) `check.sh aziz/servers-one`: build ok, the line `== selftest: N/N passed` (any FAIL line names the broken logic), then PASS with questions 10/10. The prompt order changed (T09), so if questions or catch-up drop, re-run with `CLUELESS_PROMPT_LAYOUT=classic` in front: if that passes, the new layout is the cause. (2) In `.worktrees/check`: `.build/release/clueless-bench cache` and paste the two `==` lines into BENCHMARKS.md; `stable` should show fewer tokens evaluated and a faster first token than `classic`. (3) `.build/release/clueless-bench names`: expect 10 to 12 of 12. (4) `.build/release/clueless-bench notes`: notes should use Maya, Sam, Priya and leave one speaker as "Speaker 4". (5) `.build/release/clueless-bench answer 8080 9B questions_more`: note the score, loosen keywords in `bench/questions_more.json` if an answer is right but worded differently. (6) `.build/release/clueless-bench chunk <lecture wav> <reference txt>`: compare the `silence-2-8s` row with the last row `sil-2-8s hard cut`. (7) With a recorded multi-speaker call (T21): `.build/release/clueless-bench speakers <wav>` and `notes 8080 <wav>`. (8) `./scripts/servers.sh stop watcher`, `status` shows 8080 up and 8082 down, `start watcher` brings it back without restarting the answerer | not run yet |

## Milestones

| Milestone | Target | State |
|---|---|---|
| M0 Smoke tests | Sat 4:00 pm | Done except the Wi-Fi-off run (T03). Tagged `m0` |
| M1 Study mode | Sat 7:30 pm | About 80%. Left: T01, T02, T03, T04 |
| M2 Catch-up | Sat 10:30 pm | About 65%. Look-away trigger merged (live tuning in T28). Left: T06, T07 |
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
| T08 Cut the screenshot cost: OCR by default, image only for visual questions, smaller image; bench to measure each | Aziz | `aziz/screenshot-cost` | Sat 6:05 pm | Written on the Windows laptop, not compiled, nothing measured yet. App wiring is on `aziz/screenshot-cost-app` |
| T19 Forced cut at 8 s can split a word: cut at the quietest point instead | Aziz | `aziz/word-cut` | Sat 6:25 pm | Written on the Windows laptop, not compiled; stacked on `aziz/engine-combined` |
| T13 Speaker labels at end of session with SpeakerKit on the recorded system audio | Aziz | `aziz/call-notes` | Sat 6:25 pm | Written on the Windows laptop, not compiled; stacked on `aziz/engine-combined` |
| T14 Resolve speaker names from context | Aziz | `aziz/call-notes` | Sat 6:25 pm | Written on the Windows laptop, not compiled; stacked on `aziz/engine-combined` |
| T15 End-of-session notes by speaker, using the names | Aziz | `aziz/call-notes` | Sat 6:25 pm | Written on the Windows laptop, not compiled; stacked on `aziz/engine-combined` |
| T10 Grow the test set to about 20 questions | Aziz | `aziz/test-set` | Sat 6:25 pm | Written on the Windows laptop, not compiled; stacked on `aziz/engine-combined` |
| T27 `servers.sh start answerer` / `start watcher`: start or stop one server alone (asked for by Yusuf for T16) | Aziz | `aziz/servers-one` | Sat 6:25 pm | Written on the Windows laptop, not run; stacked on `aziz/test-set` |
| T21 Demo assets: a multi-speaker call, a narrated slide lecture and a PDF, all generated locally (no downloads) | Aziz | `aziz/demo-assets` | Sat 6:26 pm | Written on the Windows laptop. Slides and PDF checked in a browser there; the audio script has never been run |

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

### M3 Call mode
| ID | Task | Suggested |
|---|---|---|
| T11 | Live test of call mode: microphone = You, system audio = Them (needs Microphone permission) | Yusuf |
| T12 | Name trigger through the watcher, live: saying the user's name produces a catch-up card | Yusuf |

### Reliability
| ID | Task | Suggested |
|---|---|---|
| T18 | 20-minute soak test: memory, lag and crashes over a long session | both |
| T28 | In-person live tests deferred until the features are built (Yusuf's decision, Sat 6:45 pm). T05: allow the Camera prompt; eye icon shows; look away 10 s while audio plays then back gives a card; a 1 to 2 s glance does nothing; silence gives no card; pause turns the camera off; tune `maxAngle` / `awayAfter` in `Presence.swift`. T16: orange row and HUD dots while servers start; Restart button; a question during a restart gets a "still starting" card; servers are not restarted mid-answer. T17: display sleep or monitor unplug restarts capture; "Stop sharing" in the menu bar is not undone; pause stays paused; Study/Call switch keeps listening | both |

### M5 Ship
| ID | Task | Suggested |
|---|---|---|
| T20 | Finish the HUD: latency per stage, RAM including the servers, tokens per second, network off | Yusuf |
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
| T09 Prompt order that the server can reuse from its cache; `clueless-bench cache` measures it | Aziz | Sat 7:00 pm | `aziz/prompt-cache` |
| T05 Look-away trigger (webcam + Vision). `check.sh` PASS and the simulated absence passed on the Mac mini; real head-turn test and tuning deferred to T28 | Yusuf | Sat 6:45 pm | PR #3 |
| T17 Capture restarts itself after a stream error or a 15 s stall. `check.sh` PASS, no false restart in silence; the restart itself has not fired yet, deferred to T28 | Yusuf | Sat 6:45 pm | PR #5 |
| T16 App starts and health-checks the Bonsai servers. `check.sh` PASS; auto-start and restart after a kill verified on the Mac mini; panel row and Restart button deferred to T28 | Yusuf | Sat 6:45 pm | PR #4 |
| T26 Prompts in `prompts/*.txt`, benchmark cases in `bench/*.json`; edits need no Swift change | Aziz | Sat 6:30 pm | `aziz/prompts-data` |
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
