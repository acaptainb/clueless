# Status board

The live answer to "who is doing what". Read it before starting anything; update it when you claim,
finish or drop a task. History of finished work is in [WORKLOG.md](WORKLOG.md). Rules are in
[CLAUDE.md](CLAUDE.md).

Last updated: Sat Nov 14, 8:10 pm ET by Yusuf

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

Mac mini in use right now by: Aziz (engine fixes T34 to T36, Mac mini session; the app is closed)

Run order: the top row (`main` with PR #8) is next, ahead of any row added later; new rows go BELOW it. A `main` that does not run blocks every other branch.
Then the Yusuf rows, then the remaining Aziz rows 2 to 4 in order. Row 3 makes the recordings that the top
row (steps 6 and 7) and row 4 use.

| Branch | Who | What to test beyond `check.sh` | Result |
|---|---|---|---|
| `yusuf/call-notes-app` | Yusuf | T33 (PR #24), the app side of T13 to T15. `check.sh yusuf/call-notes-app app`. No person needed. It needs `demo/call/call.wav` (T21: `python3 scripts/make_demo_assets.py --user Yusuf`) and "Your name" in the app set to Yusuf. Launch with `CLUELESS_AUDIO_FILE=<path to demo/call/call.wav>`, `CLUELESS_TEST_MODE=call` and `CLUELESS_TEST_NOTES=1`: the call plays into the app in call mode (about 2 min), then session notes are asked for. In `.run/app.log`: (1) `[speakers] SpeakerKit loaded in N s from <folder>` soon after launch. If it says NOT loaded, the models are missing from `models/argmax/speakerkit-coreml`: record that; the notes should still be written, without labels. (2) While the call plays, the name trigger fires: `[card catch_up ...]` lines after each question to Yusuf (this is also the no-person part of T12). (3) After the call: `[notes] call notes: N lines, about 120 s of recorded audio, SpeakerKit loaded`, then `[notes] 3 speakers heard, X of Y lines labelled, names: Speaker 1 = ..., ...; labels and names took Z s`. Record the speakers heard, X of Y, the names and Z, and compare the names with `demo/call/expected.json`. (4) The `[card notes ...]` line that follows uses those names (Maya, Sam, Priya), not "Them" or "Speaker 1". Record its total time. (5) App memory in the HUD after the run against a run on `main`: the recording should add about 4 MB for a 2 min call. (6) Once without `CLUELESS_TEST_MODE` (study mode) and with `CLUELESS_TEST_NOTES=1`: no `[notes]` lines, and a `[card notes ...]` as on `main`. With a person (can wait for T28): the notes card title ends with "3 speakers, N named"; its receipts show names; a long notes card scrolls | RUN Sat 8:06 pm, Mac mini session. `PASS yusuf/call-notes-app @ 84b9f67: build ok, questions 10/10, catch-up 3/3, watcher 15/16`. Live: `demo/call/call.wav` in call mode with `CLUELESS_TEST_NOTES=1`. (1) `[speakers] SpeakerKit loaded in 7.3s from models/argmax/speakerkit-coreml`. (2) Three catch-up cards fired during the call (2.4 to 3.0 s each, first token 0.8 to 1.0 s), so the name trigger works with nobody at the keyboard. Their content is weak: the first says `asked: Sam, what about the database migration?` (not a question to Yusuf), the second has an empty `asked`, the third `asked: One more question. Yusuf.` The card is built as soon as the name is heard, before the rest of the question has been transcribed. (3) `[notes] call notes: 35 lines, 119 s of recorded audio, SpeakerKit loaded`, then `[notes] 7 speakers heard, 33 of 35 lines labelled, names: none; labels and names took 2.4s`. Expected 3 speakers and Maya, Sam, Priya. (4) `[card notes 8.60s, first token 1.68s]`; the notes say Speaker 1, 3, 5, 6, 7, not names, and repeat the invented `spy website` item. The wiring itself (recording, labelling, notes request) does what T33 set out to do; the 7 speakers and missing names are the engine problem already recorded for T13 and T14. (5) and (6) not run MERGED Sat 8:22 pm (PR #24) on Aziz's instruction; `PASS main @ 59fc0ed` with it. |
| `main` (PR #8, merged Sat about 7:05 pm BEFORE any Mac mini run) | Aziz | NEXT RUN, as soon as the run in progress finishes, whatever is listed below (Aziz asked again Sat 7:30 pm; `main` with PR #8 builds on the MacBook but has never been run). RUN THIS FIRST, before the Yusuf rows (Aziz decided Sat 7:20 pm): every other branch merges `main`, so a `main` that does not build blocks all of them. Steps (6) and (7) need the T21 recordings: do the rest now and come back to those two after the `aziz/demo-assets` row. `main` now holds T09 + T19 + T13/T14/T15 + T10 + T27, which were written on Windows and have never been compiled, so `main` itself may not build: any branch that merges `main` inherits that. Use `check.sh main` wherever the steps say `check.sh aziz/servers-one`. Expect build errors first, likeliest in `Sources/CluelessCore/Speakers.swift` (SpeakerKit calls) and `Sources/clueless-bench/Selftest.swift`; fix them on a new `aziz/` branch (or paste them into the work log for Aziz). If it will not build and a quick fix is not obvious, `aziz/prompt-cache`, `aziz/word-cut`, `aziz/call-notes`, `aziz/test-set` are the same stack one task at a time, to find which task breaks it; `git revert -m 1 3fe952e` takes PR #8 back out of `main`. (1) `check.sh aziz/servers-one`: build ok, then `== selftest: N/N passed` (a FAIL line names the broken logic), then PASS with questions 10/10. T09 changed the prompt order, so if questions or catch-up drop, re-run with `CLUELESS_PROMPT_LAYOUT=classic` in front: if that passes, the new layout is the cause and stays off. (2) In `.worktrees/check`: `.build/release/clueless-bench cache`; paste the two `==` lines into BENCHMARKS.md. `stable` should show fewer tokens evaluated and a faster first token than `classic`. (3) `.build/release/clueless-bench names`: expect 10 to 12 of 12. (4) `.build/release/clueless-bench notes`: the notes use Maya, Sam and Priya and leave one speaker as "Speaker 4". (5) `.build/release/clueless-bench answer 8080 9B questions_more`: note the score; if an answer is right but worded differently, loosen its keywords in `bench/questions_more.json`. (6) `.build/release/clueless-bench chunk <lecture wav> <its text>` (the T21 lecture, or the `smoke/` files): compare the `silence-2-8s` row with the last row `sil-2-8s hard cut`; paste both into BENCHMARKS.md. (7) With the T21 call: `.build/release/clueless-bench speakers <path to demo/call/call.wav> 3` should find 3 speakers, then `.build/release/clueless-bench notes 8080 <same wav>`. (8) `./scripts/servers.sh stop watcher`, `status` shows 8080 up and 8082 down, `start watcher` brings it back without restarting the answerer. If (1) passes, record the PASS line in the work log. Not testable live yet: call notes are not wired into the app (asked of Yusuf in the work log) | RUN Sat 7:08 to 7:20 pm, Mac mini session. (1) `PASS main @ 959cd08: build ok, questions 10/10, catch-up 3/3, watcher 16/16`, self-test 21/21; again `PASS main @ 6e9d4e8` with T29 and T20 merged. It built first time, no fixes needed. (2) cache: `classic: evaluated 326, cached 208, first token 0.47s, whole card 1.30s`; `stable: evaluated 412, cached 123, first token 0.58s, whole card 1.31s`. **Stable is NOT better than classic here.** (3) names: **7/12** (expected 10 to 12): a name goes to the person who SAID it, so Sam becomes Maya and Maya stays Speaker 1. (4) notes: uses the wrong names for that reason (Speaker 1, Maya, Priya, Speaker 4). (5) questions_more: 10/10, no keyword changes needed. (6) chunk on the demo lecture: word-safe 10.4% word error, hard cut 10.4%, same 44 chunks: no measurable difference. (7) speakers: 3 found in 23 turns, 0.31 s. Notes from the call wav: 36 lines, **6 speakers heard, no names resolved**; content mostly right, one invented item. SpeakerKit models had to be copied to `models/argmax/speakerkit-coreml` first. (8) stop/start watcher alone works; answerer kept its process id. All numbers are in BENCHMARKS.md section 7 |
| `main` (T26 and T08, merged in PRs #6 and #7) | Aziz | Aziz 2 of 4, right after the Yusuf rows. The build and the gate are already covered: `PASS main @ bd30b52`. What is left is measuring, in the main checkout after `git pull` and `swift build -c release`. (1) `.build/release/clueless-bench prompts`: every line ends "same as built-in". (2) `.build/release/clueless-bench screencost smoke/shot.png`: expect `policy: 17/17` and the `auto` rows at 6/6 with a first-token time close to the `ocr` row. Paste the table into BENCHMARKS.md. (3) Show `smoke/shot.png` full screen, `screencapture -x .run/full.png`, run the bench again on `.run/full.png`. (4) Pick the smallest size whose `both` row is still 6/6 and set it in `ScreenPolicy.imageMaxSide` (`Sources/CluelessCore/ScreenInput.swift`). (5) In the app: the screen menu shows "Auto"; "when is the homework due" answers in about 1 to 2 s and the log line says `image 0 bytes`; "what does the diagram show" attaches the image. Then move T08 to Done | RUN Sat 7:10 to 7:28 pm, Mac mini session. (1) prompts: all six "same as built-in". (2) screencost on the slide: policy 17/17; ocr 5/6; both and auto 6/6 at 1024, 768 and 512; auto first token 0.39 to 0.58 s against 0.31 s for ocr. (3) Real 1920x1080 capture with the slide in a window: both 6/6 at all sizes; auto 6/6, 5/6, 6/6. (4) Chosen size **768**, not 512: on the demo lecture chart slide 512 loses the curve colour (1/2), 768 and 1024 get 2/2, and 768 is 0.6 s faster to first token than 1024. Set in `ScreenPolicy.imageMaxSide`, merged as PR #21 (`PASS aziz/image-768 @ 2175377`). (5) Live app: "When is the homework due?" -> `image 0 bytes`, 0.89 s, correct; "Which curve diverges, and what colour is it?" -> image attached (104 KB), "red", 2.48 s. The menu showing "Auto" was not looked at (needs a click). Tables in BENCHMARKS.md section 7 |
| `aziz/demo-assets` | Aziz | Aziz 3 of 4. T21. No Swift changed, so the build cannot break; this is about the audio. (1) In the branch checkout: `python3 scripts/make_demo_assets.py --user Yusuf`. It should print three different call voices and write `demo/call/call.wav` (about 2 min), six `demo/lecture/audio/slideN.wav` and `demo/lecture/lecture.wav` (about 3 min). If it says not enough English voices, install two more in System Settings > Accessibility > Spoken Content. (2) `afplay demo/call/call.wav`: three clearly different voices, 8 s of silence after each question to the user. (3) Open `demo/lecture/slides.html` full screen, press Start: narration plays and the slides advance by themselves. (4) Open `demo/paper/learning-rate-note.pdf`: page 2 has a chart with three coloured curves. (5) With the app running, try the questions in `demo/README.md` (that part is T04) | RUN Sat 7:13 pm, Mac mini session (branch already merged, run on `main`). (1) Script ran clean: `call voices: Maya = Albert, Sam = Daniel, Priya = Karen`, `demo/call/call.wav` 116.2 s, six slide wavs 22.9 to 27.7 s, `demo/lecture/lecture.wav` 162.2 s. Maya's preferred voices are not installed, so she got Albert, a novelty voice: install Samantha or Ava (System Settings > Accessibility > Spoken Content) and rerun before recording the video. (2) Not listened to. SpeakerKit separates the three voices (3 speakers found). (3) Slides render correctly in a headless browser (slides 3 to 6 checked as images); Start and auto-advance not run (needs a click). (4) PDF page 2 renders and its figure question is answered. (5) See the T04 row |
| `main`, after the first row passes and T21 is merged | Aziz | Aziz 4 of 4. T04, answer quality on real material. Launch the app (`./scripts/make_app.sh run`). (1) Play the T21 lecture (`demo/lecture/slides.html` full screen) and ask the study questions in `demo/README.md`; note right or wrong and the seconds for each. (2) Open `demo/paper/learning-rate-note.pdf` and ask its questions, including one about the chart on page 2 (that one should attach the image). (3) Write the results into BENCHMARKS.md section 6 and move T04 to Done, or list the misses in the work log | RUN Sat 7:20 to 7:28 pm, Mac mini session, HEADLESS (pages and slides rendered to full-screen images, plus one full lecture run through the app). Paper: 11/11. Lecture screen and chart questions: 7/7 with the screenshot (the two colour questions are 0/2 from OCR alone). **MISS: "When are office hours this week?" asked at the end of the lecture -> "The provided timeline does not contain information about office hours".** It was transcribed (`My office hours this week moved to Tuesday at 3`) but dropped before the model saw it: a question sends at most 45 lines, the 162 s lecture made 45, and the stepped window then drops the oldest ten (`AppState.run`, `maxLines: 45`, and `Timeline.recent`). This question is on the demo run sheet. Fix: raise the cap to about 120 lines, or join consecutive chunks of one speaker into one line. Not run: the other four audio questions, and the live browser lecture with a person. T04 stays open until the cap is fixed and the audio questions are re-run. Details in BENCHMARKS.md section 7 |
| `aziz/camera-test` | Aziz | T31, a testing tool, not a feature. Written on Windows, never compiled: expect build errors first, likeliest in the new `Sources/Clueless/CameraTestView.swift` (list in `team/aziz/NOTES.md`). `check.sh aziz/camera-test app`; the gate numbers must be unchanged (no engine change). Then launch with `CLUELESS_CAMERA_TEST=1`. NEEDS A PERSON at the webcam (it is the tool for the T28 head-turn test); without one, only steps 1, 2 and 7 can be checked. (1) A second window "Clueless camera test (testing only)" opens, with the live camera picture on the left (allow the Camera prompt the first time). Without the variable it must NOT open; the "…" menu entry "Camera test window (testing only)" opens it too. (2) Nobody in view: red "No person", Faces found 0, no box. (3) Sit facing the screen: green "Focused" and a box around the face that follows it as you move. If the box is mirrored left to right or upside down relative to the face, say which. (4) Turn the head slowly: Yaw changes; at about 30 degrees the label turns orange "Distracted / looking away"; same for Pitch when looking down or up. Note whether yaw moves smoothly or jumps in big steps (45 degrees), and whether pitch ever shows a value. (5) Stay turned away 3 s: Tracker goes to AWAY and Last event says "left"; face the screen again: back to present within about 1 s and Last event says "returned after N s"; a 1 to 2 s glance must not flip the tracker. (6) A second person in view: "2 faces visible" and the box stays on the nearer one. (7) Close the window with capture paused: the eye icon in the panel goes away (camera off); with the look-away setting off and the window open, looking away gives NO card. Write down the yaw and pitch at which looking at a second monitor, a phone on the desk and a notebook register, for tuning `maxAngle` EYE TRACKING ADDED Sat night (e09f731, new `Sources/Clueless/EyeGaze.swift`, written on Windows, NOT compiled: the branch must be rebuilt and may not build; if it does not, e09f731~1 is the last commit that was running). Extra checks with the window open: (8) yellow outlines sit on both eyes and a red dot on each pupil, and they follow the face; say if they are offset or mirrored. (9) Facing the screen with eyes centred: "Eyes: on the screen", left / right near 0. (10) Keep the head still and look far left, far right, up, down: write down the left / right and up / down numbers for each, and for looking at each edge of the screen, at a second monitor and at a phone on the desk; the limits (0.35 and 0.60) are guesses. (11) Close the eyes: "Eyes: closed"; write down the openness open and closed. (12) Note whether the numbers are steady or jitter from frame to frame while holding still. The eye estimate is display only: it must not change when cards fire | RUN Sat 7:31 pm, Mac mini session. `PASS aziz/camera-test @ 542c0b2: build ok, questions 10/10, catch-up 3/3, watcher 16/16`, self-test 21/21. It compiled first time. (1) With `CLUELESS_CAMERA_TEST=1` the window "Clueless camera test (testing only)" opens with the live camera picture on the left; without the variable it does not open (two screenshots, `.run/cam1-full.png`, `.run/cam2-full.png`). The menu entry was not clicked. (2) Nobody facing the camera (a shoulder was in the corner of the frame): red "No person", Faces found 0, no box, Yaw and Pitch show a dash, Limit ±30° (0.52 rad), Tracker AWAY, Last event "left (7:32:00 PM)", Frames analysed counting up, "Look away" setting on, Capture recording. (3) to (6) need a person at the webcam: not run. (7) needs clicks: not run. NOT merged: it edits `Presence.swift`, which `yusuf/look-away-start` also changes, so the two need merging in order UPDATE Sat 8:21 pm: `PASS aziz/camera-test @ e09f731: build ok, questions 10/10, catch-up 3/3, watcher 15/16` (the eye-tracking commit builds first time). MERGED Sat 8:22 pm (PR #20) on Aziz's instruction. Code review before the merge found one real bug: closing the camera test window with its red button QUITS THE WHOLE APP (it is the only regular window and the app quits when its last window closes). Not fixed yet. The steps that need a person, and the eye-tracking checks, are still to do. |

## Milestones

| Milestone | Target | State |
|---|---|---|
| M0 Smoke tests | Sat 4:00 pm | Done except the Wi-Fi-off run (T03). Tagged `m0` |
| M1 Study mode | Sat 7:30 pm | About 80%. Left: T01, T02, T03, T04 |
| M2 Catch-up | Sat 10:30 pm | About 90%. Look-away trigger merged (live tuning in T28). T06 screen receipts merged. Left: the in-person tests in T28, then tag `m2` |
| M3 Call mode | Sun 1:30 am | About 30%. Left: T11 to T15 |
| M4 Pro features | only if key arrives | Not started. No key yet |
| M5 Ship | Sun 11:30 am | About 35%. HUD done. Left: T21 to T24 |

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
| T34 (new) Catch-up cards must come from the transcript: on the Mac mini a card summarised the terminal text on screen, and with an empty transcript it invented "you were asked" from the screen | Aziz | `aziz/catchup-grounding` | Sat 8:40 pm | Done at the Mac mini by the Mac mini session, so it is compiled and measured as it goes |
| T35 (new) Call notes with real speakers and names: rebuild the transcript from the recording one speaker turn at a time (a live line can hold two people), stop SpeakerKit hearing 6 to 7 speakers for 3, and work the names out in code from who is addressed and who answers (the model gave 7/12) | Aziz | `aziz/call-notes-names` | Sat 8:40 pm | Mac mini session. Touches `Speakers.swift`, `prompts/names.txt`, the bench |
| T36 (new) Bench command that plays a recording into a timeline and asks a list of questions at the end, to finish the T04 lecture audio questions and the real-audio half of T10; also `download: false` for TTSKit (asked by Yusuf in the work log) | Aziz | `aziz/lecture-questions` | Sat 8:40 pm | Mac mini session |
| T33 (new) Wire call notes into the app (asked by Aziz in the work log for T13 to T15): record the session's system audio, load SpeakerKit with the other models, and in call mode make Session notes call `SessionNotes.make` so the notes are by speaker with names | Yusuf | `yusuf/call-notes-app` | Sat 7:52 pm | Written on the MacBook (session #2), compile-checked only. PR #24 (draft), in the test queue |
| T31 (new) Camera test window, for testing only: live webcam picture with the face box, a Focused / Distracted / No person label and the numbers behind the look-away trigger (yaw, pitch, limit, tracker state), to tune T05 by eye in T28 | Aziz | `aziz/camera-test` | Sat 7:20 pm | Pushed (542c0b2), written on the Windows laptop, never compiled; in the test queue. Touches `Sources/Clueless/` (Yusuf's folder): one new file plus small edits in `Presence.swift`, `AppState.swift`, `OverlayView.swift`, `App.swift` |
| T08 Cut the screenshot cost: OCR by default, image only for visual questions, smaller image; bench to measure each | Aziz | `aziz/screenshot-cost` | Sat 6:05 pm | Written on the Windows laptop, not compiled, nothing measured yet. App wiring is on `aziz/screenshot-cost-app` |
| T21 Demo assets: a multi-speaker call, a narrated slide lecture and a PDF, all generated locally (no downloads) | Aziz | `aziz/demo-assets` | Sat 6:26 pm | Written on the Windows laptop. Slides and PDF checked in a browser there; the audio script has never been run |
| T04 Check answer quality on a real lecture and a real PDF on screen | Aziz | `main` (a Mac mini run, no code) | Sat 7:10 pm | Queued as Aziz 4 of 4; needs the T21 assets and a passing `main` |

## Up next

Unclaimed. "Suggested" is only a suggestion; whoever claims it in the table above owns it.

### M1 Study mode
| ID | Task | Suggested |
|---|---|---|
| T01 | Verify spoken answers in the live app (TTSKit plays, does not get transcribed back) | Yusuf |
| T02 | Verify hotkeys in the live app: Option+Space ask, Option+C catch-up, Option+S stop speaking | Yusuf |
| T03 | Run the whole app on the Mac mini with Wi-Fi off; record the result in BENCHMARKS.md | Yusuf |

### M2 Catch-up
| ID | Task | Suggested |
|---|---|---|

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
| T28 | In-person live tests deferred until the features are built (Yusuf's decision, Sat 6:45 pm). T05: allow the Camera prompt; eye icon shows; look away 10 s while audio plays then back gives a card; a 1 to 2 s glance does nothing; silence gives no card; pause turns the camera off; tune `maxAngle` / `awayAfter` in `Presence.swift`. T16: orange row and HUD dots while servers start; Restart button; a question during a restart gets a "still starting" card; servers are not restarted mid-answer. T17: display sleep or monitor unplug restarts capture; "Stop sharing" in the menu bar is not undone; pause stays paused; Study/Call switch keeps listening. T07: speech starts before the card finishes; sentences in order, none twice; Option+S stops it at once; a new question cuts off the old speech. T20: ask for session notes and check that a long card scrolls inside the panel. T25: press Option+V and ask a real question out loud while a lecture plays through the speakers; it is transcribed and answered; the lecture is not what gets asked; compare `CLUELESS_VOICE_PROCESSING=0`; a voice question asked while a card is being written is answered afterwards, not lost. T06: click the thumbnail under RECEIPTS to enlarge it inside the card (it scrolls, the HUD stays visible) and again to shrink it; the arrow opens the saved file; a new question replaces the thumbnail; session notes show none | both |

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
