# Work log

Append-only history of what each person did. Add entries at the bottom, never edit old ones.
Format: `- <day time> | <person> | <task or milestone> | what changed, what was measured, anything the other person must know`
Mark anything that changes the shared interface (`TimelineLine`, `Watcher.watch`, `Answerer.answer`, `Card`) with **CONTRACT**.
Mark anything the other person must do on their machine with **ACTION**.

## Sat Nov 14

- Sat 3:25 pm | Yusuf | setup | Repo cloned, brief saved as BRIEF.md, CLAUDE.md points at it. This Mac: M6, 32 GB, no Xcode (Command Line Tools only).
- Sat 3:30 pm | Yusuf | M0 | Built PrismML's llama.cpp fork from source into `vendor/llama.cpp` (prebuilt binaries not used). Downloaded 9B, 9B-MTP, 4B, 2B models and the 9B/2B vision projectors into `models/bonsai`, checksums verified. Neither folder is in git.
- Sat 3:35 pm | Yusuf | M0 | Built `argmax-cli` from source without Xcode. WhisperKit model `large-v3-v20240930_626MB` and TTSKit 0.6B stored under `models/argmax`.
- Sat 3:40 pm | Yusuf | M0 | Smoke tests pass: 9B text and screenshot, watcher JSON, transcribe, speak, diarize. Wi-Fi-off run still owed (T03).
- Sat 3:50 pm | Yusuf | M1 | Engine core in `Sources/CluelessCore`. **CONTRACT** defined: `TimelineLine`, `Watcher.watch(lines, userName) -> Decision`, `Answerer.answer(task, lines, screenText, image, question, userName, thinking, onPartial) -> Card`.
- Sat 4:00 pm | Yusuf | M1 | App in `Sources/Clueless`: ScreenCaptureKit capture, floating panel with recording indicator, hotkeys, cards with receipts, basic HUD. Built with SwiftPM and `scripts/make_app.sh`, no Xcode project.
- Sat 4:10 pm | Yusuf | bench | `clueless-bench` added. Decisions from the numbers: answerer = 9B MTP file with `draft-mtp` (1.5x faster, same answers); watcher = 4B instead of 2B (16/16 vs 13 to 14/16); screen input = screenshot + OCR (6/6 vs 5/6 for OCR only, but slower); chunking = cut at a pause, 2 to 8 s. BRIEF.md updated to match.
- Sat 4:13 pm | Yusuf | M1 | In-app test on a played-back lecture (`CLUELESS_AUDIO_FILE` hook): transcript keeps pace, question and catch-up correct with receipts. Fixed App Nap throttling and typed questions being read as call speech.
- Sat 4:52 pm | Yusuf | M1 | Screen Recording permission was lost on every rebuild. Fixed in `make_app.sh` by pinning the ad-hoc signature's requirement to the bundle id. **ACTION** if permission gets stuck on your Mac: `tccutil reset ScreenCapture com.clueless.app`, relaunch, grant.
- Sat 4:55 pm | Yusuf | M1 | Live capture verified: lecture played through the speakers is transcribed in real time (0.6 s per chunk). Live question with a real screen capture took 7.5 s; first token 6.1 s because of the image (see T08).
- Sat 4:58 pm | Yusuf | M2 | Streaming: first words of a catch-up card in 0.8 s, whole card about 6 s. App now logs to `.run/app.log`.
- Sat 4:59 pm | Yusuf | repo | PR #1 merged into `main`. Tag `m0` pushed.
- Sat 5:25 pm | Yusuf | team | Added STATUS.md (board), WORKLOG.md (this file) and the team rules in CLAUDE.md. Roles proposed: Yusuf = A (app), teammate = B (engine); not yet confirmed. **ACTION** teammate: fill in your name in STATUS.md and claim T22.
