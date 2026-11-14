# Work log

Append-only history of what each person did. Add entries at the bottom, never edit old ones.
Format: `- <day time> | <person> | <task or milestone> | what changed, what was measured, anything the other person must know`
Mark anything that changes the shared interface (`TimelineLine`, `Watcher.watch`, `Answerer.answer`, `Card`) with **CONTRACT**.
Mark anything the other person must do on their machine with **ACTION**.

## Sat Nov 14

- Sat 3:25 pm | Aziz | setup | Repo cloned, brief saved as BRIEF.md, CLAUDE.md points at it. This Mac: M6, 32 GB, no Xcode (Command Line Tools only).
- Sat 3:30 pm | Aziz | M0 | Built PrismML's llama.cpp fork from source into `vendor/llama.cpp` (prebuilt binaries not used). Downloaded 9B, 9B-MTP, 4B, 2B models and the 9B/2B vision projectors into `models/bonsai`, checksums verified. Neither folder is in git.
- Sat 3:35 pm | Aziz | M0 | Built `argmax-cli` from source without Xcode. WhisperKit model `large-v3-v20240930_626MB` and TTSKit 0.6B stored under `models/argmax`.
- Sat 3:40 pm | Aziz | M0 | Smoke tests pass: 9B text and screenshot, watcher JSON, transcribe, speak, diarize. Wi-Fi-off run still owed (T03).
- Sat 3:50 pm | Aziz | M1 | Engine core in `Sources/CluelessCore`. **CONTRACT** defined: `TimelineLine`, `Watcher.watch(lines, userName) -> Decision`, `Answerer.answer(task, lines, screenText, image, question, userName, thinking, onPartial) -> Card`.
- Sat 4:00 pm | Aziz | M1 | App in `Sources/Clueless`: ScreenCaptureKit capture, floating panel with recording indicator, hotkeys, cards with receipts, basic HUD. Built with SwiftPM and `scripts/make_app.sh`, no Xcode project.
- Sat 4:10 pm | Aziz | bench | `clueless-bench` added. Decisions from the numbers: answerer = 9B MTP file with `draft-mtp` (1.5x faster, same answers); watcher = 4B instead of 2B (16/16 vs 13 to 14/16); screen input = screenshot + OCR (6/6 vs 5/6 for OCR only, but slower); chunking = cut at a pause, 2 to 8 s. BRIEF.md updated to match.
- Sat 4:13 pm | Aziz | M1 | In-app test on a played-back lecture (`CLUELESS_AUDIO_FILE` hook): transcript keeps pace, question and catch-up correct with receipts. Fixed App Nap throttling and typed questions being read as call speech.
- Sat 4:52 pm | Aziz | M1 | Screen Recording permission was lost on every rebuild. Fixed in `make_app.sh` by pinning the ad-hoc signature's requirement to the bundle id. **ACTION** if permission gets stuck on your Mac: `tccutil reset ScreenCapture com.clueless.app`, relaunch, grant.
- Sat 4:55 pm | Aziz | M1 | Live capture verified: lecture played through the speakers is transcribed in real time (0.6 s per chunk). Live question with a real screen capture took 7.5 s; first token 6.1 s because of the image (see T08).
- Sat 4:58 pm | Aziz | M2 | Streaming: first words of a catch-up card in 0.8 s, whole card about 6 s. App now logs to `.run/app.log`.
- Sat 4:59 pm | Aziz | repo | PR #1 merged into `main`. Tag `m0` pushed.
- Sat 5:25 pm | Aziz | team | Added STATUS.md (board), WORKLOG.md (this file) and the team rules in CLAUDE.md. Roles proposed, not yet confirmed.
- Sat 5:40 pm | Aziz | team | New setup: laptops are for coding only; ALL building and testing happens on the one Mac mini (Aziz's laptop is Windows and cannot build). Added `scripts/check.sh <branch>`: builds a pushed branch in a separate working copy on the Mac mini and runs the answer and watcher benchmarks, PASS or FAIL. Added the "Mac mini test queue" to STATUS.md and `team/aziz/`, `team/yusuf/` notes folders. `servers.sh` now keeps the servers alive after the starting shell exits. **ACTION** both: after pushing a branch, add it to the test queue; do not call anything done until it passes on the Mac mini.
- Sat 5:50 pm | Aziz | team | Correction: every entry above was first logged under Yusuf by mistake; it was all Aziz, working at the Mac mini (GitHub `acaptainb`). The merged branch `yusuf/mac-mini-workflow` (PR #2) was also Aziz's. Added "Roles in detail" to STATUS.md. **ACTION** Yusuf: add your GitHub name to STATUS.md and confirm your role.
