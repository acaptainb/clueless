# Status board

The live answer to "who is doing what". Read it before starting anything; update it when you claim,
finish or drop a task. History of finished work is in [WORKLOG.md](WORKLOG.md). Rules are in
[CLAUDE.md](CLAUDE.md).

Last updated: Sat Nov 14, 5:25 pm ET by Yusuf

## People

| Person | GitHub | Role | Machine notes |
|---|---|---|---|
| Yusuf | `acaptainb` | A, the app (proposed, confirm) | M6, 32 GB. Models installed, Screen Recording granted, live capture working |
| Teammate (fill in name) | (fill in) | B, the engine (proposed, confirm) | Needs README setup first (T22) |

Role A owns `Sources/Clueless/`. Role B owns `Sources/CluelessCore/`, `Sources/clueless-bench/`, `scripts/`.
`AppState.swift` is the glue file: A owns it; B adds functions in the core and A calls them.

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

## In progress

One line per claimed task. Add your line and push it to `main` BEFORE you start work.

| Task | Who | Branch | Started | Notes |
|---|---|---|---|---|
| (nothing claimed) | | | | |

## Up next

Unclaimed. "Suggested" is only a suggestion; whoever claims it in the table above owns it.

### M1 Study mode
| ID | Task | Suggested |
|---|---|---|
| T01 | Verify spoken answers in the live app (TTSKit plays, does not get transcribed back) | A |
| T02 | Verify hotkeys in the live app: Option+Space ask, Option+C catch-up, Option+S stop speaking | A |
| T03 | Run the whole app with Wi-Fi off on each laptop; record the result in BENCHMARKS.md | both |
| T04 | Check answer quality on a real lecture video and a real PDF on screen (needs T21 assets) | B |

### M2 Catch-up
| ID | Task | Suggested |
|---|---|---|
| T05 | Look-away trigger: webcam + Vision face detection; looking away then back fires a catch-up | A |
| T06 | Receipts for screen sources: save the screenshot, set `snapshot` on the timeline line, show it in the card | A |
| T07 | Start speaking the first field as soon as it is complete, not after the whole card | A |

### Performance (the main focus)
| ID | Task | Suggested |
|---|---|---|
| T08 | Cut the screenshot cost (first token is 6 s with an image): smaller or cropped image, or OCR by default and image only for visual questions. Measure each | B |
| T09 | Keep the prompt prefix identical between requests so the server reuses its cache; measure prompt time | B |
| T10 | Grow the test set to about 20 questions and add real recorded audio, not only synthetic speech | B |
| T19 | The forced cut at 8 s can split a word across two lines: overlap chunks or cut at a word boundary | B |

### M3 Call mode
| ID | Task | Suggested |
|---|---|---|
| T11 | Live test of call mode: microphone = You, system audio = Them (needs Microphone permission) | A |
| T12 | Name trigger through the watcher, live: saying the user's name produces a catch-up card | A |
| T13 | Speaker labels at end of session with SpeakerKit on the recorded system audio | B |
| T14 | Resolve speaker names from context ("thanks, Priya") | B |
| T15 | End-of-session notes by speaker, using the names | B |

### Reliability
| ID | Task | Suggested |
|---|---|---|
| T16 | App starts and health-checks the Bonsai servers itself; clear message when one is down | A |
| T17 | Restart capture automatically if the stream stops | A |
| T18 | 20-minute soak test: memory, lag and crashes over a long session | both |

### M5 Ship
| ID | Task | Suggested |
|---|---|---|
| T20 | Finish the HUD: latency per stage, RAM including the servers, tokens per second, network off | A |
| T21 | Demo assets, stored locally: a lecture video, a PDF paper, a 2 to 3 minute multi-speaker call | B |
| T22 | Teammate laptop setup from the README (llama.cpp fork, Bonsai models, Argmax models) | Teammate |
| T23 | Record the demo video, under 2 minutes | both |
| T24 | Final README and the Discord submission | both |
| T25 | Optional: ask a question by voice instead of typing | A |

## Open questions

- Is Apple's built-in OCR fine under the "LLMs must be Bonsai" rule? Ask the organizer.
- Argmax Pro key: requested? received? (decides M4)
- Which laptop runs the live demo? (it must be set up and rehearsed with Wi-Fi off)

## Done

Newest first. One line each; details and numbers are in WORKLOG.md and BENCHMARKS.md.

| Task | Who | When | Where |
|---|---|---|---|
| Team tracking: STATUS.md, WORKLOG.md, workflow rules | Yusuf | Sat 5:25 pm | `main` |
| Answers stream into the card (first words in 0.8 s) | Yusuf | Sat 4:58 pm | PR #1 |
| Live system-audio capture and transcription verified in the app | Yusuf | Sat 4:55 pm | PR #1 |
| Screen Recording permission survives rebuilds (signing fix) | Yusuf | Sat 4:52 pm | PR #1 |
| Method benchmarks: answerer model, watcher model, screen input, audio chunking | Yusuf | Sat 4:10 pm | PR #1, BENCHMARKS.md |
| Study-mode app: capture, floating panel, hotkeys, cards with receipts, HUD basics | Yusuf | Sat 4:00 pm | PR #1 |
| Engine core: timeline, Bonsai client, watcher, answerer, chunked transcription, OCR, speech | Yusuf | Sat 3:50 pm | PR #1 |
| M0 smoke tests: Bonsai 9B text and image, watcher, Argmax transcribe, speak, diarize | Yusuf | Sat 3:40 pm | PR #1, tag `m0` |
| Bonsai servers: llama.cpp fork built from source, 9B/4B/2B models downloaded and checksummed | Yusuf | Sat 3:30 pm | `scripts/servers.sh` |
