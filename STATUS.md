# Status board

The live answer to "who is doing what". Read it before starting anything; update it when you claim,
finish or drop a task. History of finished work is in [WORKLOG.md](WORKLOG.md). Rules are in
[CLAUDE.md](CLAUDE.md).

Last updated: Sun Nov 15, 9:55 am ET by Aziz

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

Run order: the top row (`main` with PR #8) is next, ahead of any row added later; new rows go BELOW it. A `main` that does not run blocks every other branch.
Then the Yusuf rows, then the remaining Aziz rows 2 to 4 in order. Row 3 makes the recordings that the top
row (steps 6 and 7) and row 4 use.

| Branch | Who | What to test beyond `check.sh` | Result |
|---|---|---|---|
| `aziz/engine-fixes` | Aziz | T43 (PR #43), three engine fixes. Written on Windows, never compiled: expect build errors first, likeliest in `Sources/CluelessCore/Speech.swift` (the new `Speaker`: `withTaskCancellationHandler`, `tts.audioOutput.stopPlayback`). (1) `check.sh aziz/engine-fixes`: build ok, the self-test has two new lines starting `notes:` that say ok, gate no worse than `main`. (2) `check.sh` uses the main checkout's `servers.sh`, so try the new script from the worktree: `.worktrees/check/scripts/servers.sh` cannot be used as it is (it looks for models next to itself); instead after merging and `git pull` in the main checkout: `./scripts/servers.sh stop watcher`, then `./scripts/servers.sh start`: it must print `answerer is already running on port 8080: left alone`, the answerer keeps its process id, the watcher comes up; `cat .run/answerer.pid` is the pid that `lsof -nP -iTCP:8080 -sTCP:LISTEN -t` prints. Then `echo 1 > .run/answerer.pid; ./scripts/servers.sh start`: the pid file is put right again. Then `./scripts/servers.sh stop` and `status`: both down. The `lsof` / `ps` lines have never run anywhere. (3) No person: launch the app with `CLUELESS_AUDIO_FILE` on the demo lecture and `CLUELESS_TEST_QUESTION`: the `[speech] queued` lines appear and the card is spoken to the end as on `main` (the new stop must not cut speech that nobody stopped). (4) With a person: Option+S in the middle of a spoken card cuts the voice at once; the next card is spoken normally; Option+V while a card is being spoken: the voice stops and is not in the transcribed question. (5) Call notes on the demo call as before (Maya, Sam, Priya); the log has a new line `[notes] your lines: N in the whole call, M of them in the capped list` | not run yet |
| `aziz/app-fixes` | Aziz | T44 (PR #44), three app fixes in `Sources/Clueless/`. Written on Windows, never compiled. `check.sh aziz/app-fixes app`; the gate numbers must be unchanged (no engine change). (1) No person: `./scripts/servers.sh stop`, launch with `CLUELESS_NO_SERVER_START=1` and the lecture file, press Catch me up (or use the look-away hook): the card must show `Bonsai did not answer` and not `Nothing directed at you` (screenshot). (2) With a person: play the lecture, press Pause in the middle of a sentence, wait 3 s: that sentence is in the transcript and the log; press Play: listening continues. (3) Force a capture restart (unplug and replug the display, or sleep the display) and press Pause while the status says `Restarting, try N`: it stays paused, the log says `[capture] paused during a restart`, and one press of Play resumes. (4) Call mode, loudspeakers: Pause right after someone says the user's name: no card starts by itself after the pause. (5) A look-away card and a hotkey catch-up still lose no words at the cut (T46 must be unaffected: the merge keeps its 2 s rule) | not run yet |
| `main` (after PRs #38, #40, #42) | Yusuf | Merged Sun 9:50 am on Yusuf's word, before a Mac mini run. (1) `check.sh main` must PASS. (2) T47 was never run: with live capture and the Mac unlocked, look for `[warmup] first screenshot Ns, OCR Ns` soon after "Listening" and time the first card (trigger to `[receipt] ... saved`). If the app misbehaves at launch, `CLUELESS_NO_SCREEN_WARMUP=1` turns it off: say so and it gets reverted. (3) T42: one catch-up on the demo lecture reads "The speaker explained…", not "Them explained…" | not run yet |

## Milestones

| Milestone | Target | State |
|---|---|---|
| M0 Smoke tests | Sat 4:00 pm | Done, including the Wi-Fi-off run (T03). Tagged `m0` |
| M1 Study mode | Sat 7:30 pm | About 90%. Answer quality checked on the demo paper and lecture (T04). Spoken answers (T01) and the Wi-Fi-off run (T03) confirmed in person by Aziz. Left: T02 (hotkeys and a typed question, a person) |
| M2 Catch-up | Sat 10:30 pm | About 95%. Look-away trigger works with a real person (four spoken cards during the demo lecture, glances and silence give none). T06 screen receipts merged. Left: the hotkey catch-up (T02) and the rest of T28, then tag `m2` |
| M3 Call mode | Sun 1:30 am | About 75%. Call notes by speaker with names work on the demo call, in the bench and in the app (T13 to T15, T33, T35). Left: T11 and T12 live with a microphone, T38 |
| M4 Pro features | only if key arrives | Not started. No key yet |
| M5 Ship | Sun 11:30 am | About 45%. HUD and demo assets done. Left: T18 (soak, running Sat 9 pm), T22 to T24 |

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
| T43 (new) Three engine bugs found by reading `main @ 8d9727e`: Option+S and a voice question do not stop audio that is already playing (`Speaker.stop` only cancels a task the speech queue never sets); call notes drop the user's earlier lines when the call has more than 200 lines; `servers.sh start` with one server already up launches both and overwrites the pid file of the healthy one | Aziz | `aziz/engine-fixes` | Sun 1:55 am | Pushed (PR #43), written on the Windows laptop, never compiled; in the test queue. One call-site line in `Sources/Clueless/CallNotes.swift` (Yusuf's folder) goes with the core change |
| T44 (new) Three app bugs found by reading `main @ 8d9727e`: Pause pressed while capture is restarting is undone when the restart finishes; Pause throws away the audio still waiting to be transcribed; a failed catch-up card shows "Nothing directed at you" instead of the error | Aziz | `aziz/app-fixes` | Sun 1:55 am | Pushed (PR #44), written on the Windows laptop, never compiled; in the test queue. In `Sources/Clueless/` (Yusuf's folder: `CaptureRestart.swift`, `AppState.swift`, `OverlayView.swift`), as a separate small PR; Aziz asked for these fixes |
| T48 (new) Camera window for the demo video, and eye direction counts as looking away: a camera button in the panel header opens a compact "Clueless camera" window with one label (Focused / Distracted / No person) and a tracking view behind an eye button; the look-away trigger also uses the eye verdict (off switch in the "…" menu and `CLUELESS_EYES=0`) | Aziz | `aziz/camera-demo` | Sun 9:55 am | After the feature freeze: Aziz decided to make this exception for the demo video. Being written on the Windows laptop, cannot be compiled there. In `Sources/Clueless/` (Yusuf's folder), as one small PR |

## Up next

Unclaimed. "Suggested" is only a suggestion; whoever claims it in the table above owns it.

### M1 Study mode
| ID | Task | Suggested |
|---|---|---|
| T02 | Verify hotkeys in the live app: Option+Space ask, Option+C catch-up, Option+S stop speaking | Yusuf |

### M2 Catch-up
| ID | Task | Suggested |
|---|---|---|

### Performance (the main focus)
| ID | Task | Suggested |
|---|---|---|
| T40 | First word late in a long session: 3.4 s after 20 minutes (120 lines, nothing cached). `Answerer.prewarm` cuts a cold 8 s to 1.6 s in the bench, but wired into the app it did not help, because catch-ups and questions send different slices of the timeline and the server keeps one cached prompt (BENCHMARKS.md section 8). Make both card types send the same lines, with the instructions saying which part matters, then call `prewarm` after new lines and after each card | Aziz and Yusuf |

### M3 Call mode
| ID | Task | Suggested |
|---|---|---|
| T11 | Live test of call mode: microphone = You, system audio = Them (needs Microphone permission) | Yusuf |
| T12 | Name trigger through the watcher, live: saying the user's name produces a catch-up card | Yusuf |

### Reliability
| ID | Task | Suggested |
|---|---|---|
| T18 | Soak test, second half: 20 minutes with LIVE capture (ScreenCaptureKit, speakers, webcam, spoken cards). The file-fed half is done (see Done) | both |
| T28 | In-person live tests deferred until the features are built (Yusuf's decision, Sat 6:45 pm). DONE Sun by Aziz in person: the T05 look-away card with real head turns, and that cards are spoken (T01). Still open in T05: pause turns the camera off, and tuning `maxAngle` / `awayAfter` (no angles were written down). Everything from T16 on is still to do. T05: allow the Camera prompt; eye icon shows; look away 10 s while audio plays then back gives a card; a 1 to 2 s glance does nothing; silence gives no card; pause turns the camera off; tune `maxAngle` / `awayAfter` in `Presence.swift`. T16: orange row and HUD dots while servers start; Restart button; a question during a restart gets a "still starting" card; servers are not restarted mid-answer. T17: display sleep or monitor unplug restarts capture; "Stop sharing" in the menu bar is not undone; pause stays paused; Study/Call switch keeps listening. T07: speech starts before the card finishes; sentences in order, none twice; Option+S stops it at once; a new question cuts off the old speech. T20: ask for session notes and check that a long card scrolls inside the panel. T25: press Option+V and ask a real question out loud while a lecture plays through the speakers; it is transcribed and answered; the lecture is not what gets asked; compare `CLUELESS_VOICE_PROCESSING=0`; a voice question asked while a card is being written is answered afterwards, not lost. T06: click the thumbnail under RECEIPTS to enlarge it inside the card (it scrolls, the HUD stays visible) and again to shrink it; the arrow opens the saved file; a new question replaces the thumbnail; session notes show none | both |

### M5 Ship
| ID | Task | Suggested |
|---|---|---|
| T22 | Decide how each person reaches the Mac mini from their laptop (in person, or turn on Remote Login / Screen Sharing) so tests can be started without waiting | both |
| T23 | Record the demo video, under 2 minutes | both |
| T24 | Final README and the Discord submission | both |

## Open questions

- Is Apple's built-in OCR fine under the "LLMs must be Bonsai" rule? Ask the organizer.
- Argmax Pro key: requested? received? (decides M4)
- The live demo has to run on the Mac mini (the rules say "own laptop allowed"). Can it be brought to the finals with a screen, keyboard, webcam and speakers? Ask the organizer.

## Done

Newest first. One line each; details and numbers are in WORKLOG.md and BENCHMARKS.md.

| Task | Who | When | Where |
|---|---|---|---|
| T47 One screenshot is taken and read right after capture starts, then discarded, so the first card does not wait for it (it waited about 15 s once). Compile-checked on the MacBook only: **never run on the Mac mini**. `CLUELESS_NO_SCREEN_WARMUP=1` turns it off | Yusuf | Sun 9:50 am | PR #42 |
| T42 Cards no longer say "Them": one line in the catch-up and question prompts and their built-in copies. On the Mac mini (Sun 2 am): gate, grounding 12/12 and lecture 5/5 equal to `main`. Merged on Yusuf's word; Aziz had not answered | Yusuf | Sun 9:50 am | PR #38 |
| T46 Words are no longer lost where a card is built mid-sentence: a look-away card cuts the audio once, not twice, and a cut piece under 1.1 s is padded with silence (WhisperKit returns nothing for audio under 1 s). `check.sh` PASS; lecture with a simulated look-away: 0 words lost in 3 runs, against 3, 4 and 11 on `main`. Speed about the same (not proven equal) | Yusuf | Sun 3:45 am | PR #41 |
| T45 Test hook `CLUELESS_TEST_T41`. `check.sh` PASS; on the Mac mini, file hook and live capture: a question asked during a card gets its card; Option+S during a streaming card: no further speech queued; play pressed twice: one stream; capture restarted 0.6 s after a simulated stream error (the first time T17's restart has run) | Yusuf | Sun 3:05 am | PR #39 |
| T41 Nine fixes from an independent review of the app code: a typed question waits for a card in progress instead of being dropped; Option+S no longer lets speech start again; in call mode microphone audio is dropped while the loudspeakers or Clueless are speaking (`CLUELESS_MIC_GATE=0` turns that off); capture cannot be started twice; main menu (paste, quit); "Your name" dialog; screenshots use the main display; hotkey registration logged; a placeholder card while a question is still being said. `check.sh` PASS, all four hotkeys register, demo call and lecture runs unchanged. The behaviours themselves need a person: `team/yusuf/SHIP.md` | Yusuf | Sun 1:45 am | PR #37 |
| T39 Small fixes: the file test hook plays in real time (was 4.5% slow); entering call mode starts a new call for the notes; Whisper's "you" / "Thank you." lines on near-silence are dropped (checked by reading only: none occurred in the test); the look-away log says why no card was made. `check.sh` PASS. Not done: the camera test window retry | Yusuf | Sun 1:35 am | PR #35 |
| T38 A name-triggered catch-up card waits for the speaker to finish (0.8 s of quiet, 6 s at most). `check.sh` PASS; on the demo call the name-first question waited 5.2 s and the card has the question ("Can your team still hit Friday for the release candidate?", empty on `main`); a question with the name inside it waited 0.0 s | Yusuf | Sun 1:28 am | PR #34 |
| T03 Whole app run on the Mac mini with Wi-Fi off: worked (Aziz, in person; Wi-Fi is this Mac's only network connection). No timings taken | Aziz | Sun 1:20 am | BENCHMARKS.md section 1, WORKLOG |
| T01 Spoken answers in the live app: Aziz heard the cards spoken; in the log all four cards were queued for speech 1.7 to 2.0 s after the trigger and none came back as a transcript line | Aziz | Sun 1:20 am | WORKLOG |
| T05 / T28 (part) Look-away trigger with a real person: four look-aways of 6 to 9 s during the demo lecture each gave a spoken catch-up card in 2 to 3 s; 31 short glances and 87 look-aways in silence gave none | Aziz | Sun 1:20 am | WORKLOG |
| T37 Forced cuts look 3 s back for a gap between words (was 1.5 s): lecture audio questions 4/5 -> 5/5, word error and lag unchanged | Aziz | Sat 9:37 pm | PR #32 |
| T18 (first half) 22-minute soak with a lecture fed through the file hook: 340 lines, no crash, app 300 to 366 MB, answerer 1.2 GB, watcher 0.25 to 0.29 GB, transcription 0.40 s per chunk at the start and at the end. The question at the end was right but slow to start (3.4 s to first token with 120 lines) | Aziz | Sat 9:18 pm | BENCHMARKS.md, WORKLOG |
| T36 `clueless-bench lecture`: the lecture's audio-only questions in one run, 4/5 on the demo lecture (the miss is a lost word at a forced cut, T37). TTSKit loads with `download: false` | Aziz | Sat 8:55 pm | PR #30 |
| T34 Catch-up cards come from what was said: screen text labelled as background and cut to 600 characters, no model call when nothing was said. `clueless-bench grounding` 12/12 | Aziz | Sat 8:50 pm | PR #29 |
| T35 Call notes with real speakers and names: the recording is transcribed again per speaker turn, names come from who is addressed and who answers (in code). Names bench 7/12 -> 12/12; notes on the demo call say Maya, Sam, Priya, in the bench and in the app. Demo call voices fixed (Samantha, Daniel, Tara) | Aziz | Sat 8:45 pm | PR #28 |
| T31 Camera test window with experimental eye readings; closing it no longer quits the app. Used in person by Aziz on Sun: head turns and eye readings worked (no numbers written down) | Aziz | Sat 8:30 pm | PRs #20, #27 |
| T33 Call notes wired into the app: recording, SpeakerKit, notes on request. `check.sh` PASS; live run on the demo call | Yusuf | Sat 8:22 pm | PR #24 |
| T04 Answer quality on real material: demo paper 11/11, lecture slides 7/7 (chart colours need the screenshot), lecture audio 4/5 | Aziz | Sat 8:55 pm | BENCHMARKS.md sections 7 and 8 |
| T08 Screenshot cost: auto policy (image only for visual questions), default size 768. Text question 0.9 s with no image; chart question answered with the image | Aziz | Sat 7:30 pm | PRs #6, #7, #21 |
| T21 Demo assets: 2 min three-voice call, 2.7 min narrated lecture with slides, 2-page paper; audio built on the Mac mini | Aziz | Sat 8:45 pm | `aziz/demo-assets`, PR #28 |
| Answerer memory: host prompt cache off, 10 GB -> 1.6 GB | Aziz | Sat 8:05 pm | PR #22 |
| T32 Questions send up to 120 timeline lines (was 45). `check.sh` PASS; on the 162 s demo lecture "When are office hours this week?" is now answered correctly citing L5; first token 1.83 s vs 1.63 s on `main` | Yusuf | Sat 8:10 pm | PR #23 |
| T06 Screen receipts: the screenshot behind each card is saved, recorded on the timeline line (`snapshot`) and shown as a thumbnail under RECEIPTS. `check.sh` PASS; on the Mac mini both files were saved in 18 to 19 ms with no change in first-token time. Click to enlarge and open are not seen yet (T28) | Yusuf | Sat 7:52 pm | PR #15 |
| T25 Ask a question by voice (Option+V or the microphone button, study mode; WhisperKit). `check.sh` PASS. Live on the Mac mini with nobody speaking: echo cancellation on (now the default) keeps the lecture out of the question at the cost of a few transcript words while the microphone is open. A real spoken question has never been tested: T28 | Yusuf | Sat 7:45 pm | PR #18 |
| T30 No look-away card before a face has been seen, or for almost nothing missed. `check.sh` PASS; two launches with no false card, hook still gives a card | Yusuf | Sat 7:45 pm | PR #19 |
| T20 HUD: two rows (network, each Bonsai server with memory, app memory, total; stt, ocr, watcher, first word, whole card, tok/s, cached). Panel now resizes to fit its content. `check.sh` PASS; screenshots on the Mac mini show both rows with and without a card and values matching the log. Long-card scrolling not seen yet (T28) | Yusuf | Sat 7:10 pm | PR #16 |
| T29 Cards include the last few seconds: buffered audio is transcribed before a card is built (0.05 to 0.48 s wait measured); look-away count now matches. Also turns on the stepped timeline window for T09. `check.sh` PASS | Yusuf | Sat 7:10 pm | PR #17 |
| T07 Speech starts on the first complete sentence of a streaming card. `check.sh` PASS on the Mac mini; catch-up speech starts 0.44 s earlier (1.46 s vs 1.90 s), no measurable slowdown of generation. Listening test (order, Option+S) deferred to T28 | Yusuf | Sat 6:55 pm | PR #12 |
| T27 `servers.sh start answerer` / `start watcher` / `stop <name>`: one server alone | Aziz | Sat 6:30 pm | `aziz/servers-one` |
| T10 Test set grown to 20 questions (`bench/questions_more.json`). Real recorded audio still to do, needs the T21 recordings | Aziz | Sat 6:30 pm | `aziz/test-set` |
| T13 Speaker labels at end of session: `SessionAudio`, `SpeakerLabeler` (SpeakerKit), `Speakers.assign` | Aziz | Sat 6:30 pm | `aziz/call-notes` |
| T14 Speaker names from context: `NameResolver`, `prompts/names.txt`, `clueless-bench names` | Aziz | Sat 6:30 pm | `aziz/call-notes` |
| T15 Session notes by speaker with names: `SessionNotes.make`; notes prompt asks for decisions, action items, open questions | Aziz | Sat 6:30 pm | `aziz/call-notes` |
| T19 Forced audio cut lands in the gap between words, not mid-word | Aziz | Sat 6:30 pm | `aziz/word-cut` |
| T09 Prompt order that the server can reuse from its cache; `clueless-bench cache` measures it | Aziz | Sat 6:30 pm | `aziz/prompt-cache` |
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
