# Clueless

**Cluely tells you what to say. Clueless tells you what you missed.**

Clueless is a private copilot that watches your screen and listens to your calls and lectures entirely on your Mac,
and catches you up the moment you lose the thread. Built for the Cornell Local AI Hackathon.

Everything runs on-device with Wi-Fi off:

- **Bonsai 2** (PrismML) is the only language model: the 9B answers questions and writes catch-up cards from the
  transcript plus a screenshot; the 4B watches the transcript for moments that need you.
- **Argmax** does all speech: WhisperKit transcribes system audio and the microphone, TTSKit speaks answers,
  SpeakerKit labels speakers.
- Apple Vision OCR reads the screen text. ScreenCaptureKit captures screen and audio.
- A recording indicator is always visible. Clueless does not hide from screen sharing.

## What it does

- **Catch me up.** Look away from the screen and back, press ⌥C, or get called on by name in a call: a card says
  what you were asked, what you missed and what you could say. The look-away trigger uses the webcam with Apple
  Vision face detection; an eye icon shows whenever the webcam is in use.
- **Ask.** Type a question (⌥Space) or ask it out loud (⌥V). The answer uses the last few minutes of transcript
  and what is on the screen.
- **Receipts.** Every card lists the transcript lines it used, with speaker and time, and the screenshot it read.
  The transcript and those screenshots are kept on this Mac under `sessions/` (ignored by git, never sent anywhere).
  A screenshot shows whatever was on screen, passwords included: delete the folder when you no longer need it.
- **Spoken answers.** The card streams in and is read aloud from its first complete sentence. ⌥S stops it.
- **Call mode.** The microphone is "You", system audio is everyone else. At the end, session notes by speaker:
  SpeakerKit separates the voices and the names are worked out from the conversation ("Go ahead, Sam",
  "Thanks, Priya"), so nobody types them in.
- **It looks after itself.** The app starts the Bonsai servers if they are not running, restarts them if the
  answerer dies, and restarts capture if the stream stops. A row in the panel says so when something is down.
- **HUD.** The bottom of the panel shows network on or off, each Bonsai server with its memory, and the time each
  stage took: speech to text, OCR, watcher, first word, whole card, tokens per second, prompt cache reuse.

## Status

Sun Nov 15, 2 am. "Checked" means the build and the benchmark gate passed on the test machine and a scripted run
showed the behaviour in the log. "Seen live" means a person sat in front of it.

| Milestone | State |
|---|---|
| M0 smoke tests | Done. The whole app was run with Wi-Fi off (the test machine's only network connection) and worked; a socket check with everything running showed only 127.0.0.1 connections |
| M1 study mode | Checked on our own demo material: paper questions 11/11, lecture slide questions 7/7, questions about what the lecturer said 5/5. Live transcription and spoken answers seen live. Hotkeys and a typed question: not yet tried by a person |
| M2 catch-up | The look-away trigger was seen live: four look-aways of 6 to 9 s each gave a card (first word after 0.8 to 1.0 s), 31 short glances gave none, no crash in 2.5 hours. Screenshot receipts are checked |
| M3 call mode | Checked on the demo call played into the app: the name trigger fires, waits for the end of the question and puts it in the card; the notes name all three speakers. Not yet tried live with a microphone |
| Reliability | Server auto-start and restart after a kill are checked. A 22-minute session played into the app: no crash, memory flat (app about 0.35 GB, 9B 1.2 GB, 4B 0.3 GB). Capture restart has not fired in a test yet |

Measurements and the method comparisons behind each default are in [BENCHMARKS.md](BENCHMARKS.md).
The full plan is in [BRIEF.md](BRIEF.md).
Who is working on what is in [STATUS.md](STATUS.md); the history is in [WORKLOG.md](WORKLOG.md).

## Setup (once, online)

Needs macOS 15+, Apple Silicon, Xcode Command Line Tools and `cmake`. Full Xcode is not required.

```sh
# 1. PrismML's llama.cpp fork (PQ2_0 files do not run on upstream llama.cpp)
git clone --depth 1 -b prism https://github.com/PrismML-Eng/llama.cpp.git vendor/llama.cpp
cmake -S vendor/llama.cpp -B vendor/llama.cpp/build-mac -DCMAKE_BUILD_TYPE=Release -DGGML_METAL=ON \
  -DGGML_METAL_EMBED_LIBRARY=ON -DBUILD_SHARED_LIBS=OFF -DLLAMA_OPENSSL=OFF -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_EXAMPLES=OFF
cmake --build vendor/llama.cpp/build-mac -j 8 --target llama-server

# 2. Bonsai models into models/bonsai/ (from huggingface.co/prism-ml/Ternary-Bonsai-2-{9B,4B}-gguf)
#    Ternary-Bonsai-2-9B-PQ2_0-MTP-Q8_0.gguf, Ternary-Bonsai-2-9B-mmproj-Q8_0.gguf, Ternary-Bonsai-2-4B-PQ2_0.gguf

# 3. Argmax models into models/argmax/
#    WhisperKit: argmax-cli transcribe --audio-path any.wav --model large-v3-v20240930_626MB \
#                  --download-model-path models/argmax --download-tokenizer-path models/argmax
#    TTSKit:     run `argmax-cli tts --text hi --model 0.6b` once, then copy
#                  ~/Documents/huggingface/models/argmaxinc/ttskit-coreml -> models/argmax/ttskit-coreml
#                  ~/Documents/huggingface/models/Qwen/Qwen3-0.6B         -> models/argmax/tts-tokenizer
#    SpeakerKit: run `argmax-cli diarize --audio-path any.wav` once, then copy
#                  ~/Documents/huggingface/models/argmaxinc/speakerkit-coreml -> models/argmax/speakerkit-coreml
#                (the app also looks in the download folder itself, so the copy is optional)
```

## Run (offline)

```sh
./scripts/make_app.sh run       # builds build/Clueless.app and launches it
```

The app starts the two Bonsai servers itself (9B on :8080, 4B on :8082, localhost only) and shows a row in the
panel while they load. To run them by hand: `./scripts/servers.sh start | stop | status`.

Grant Screen Recording when macOS asks, then relaunch. Microphone is asked for in call mode and the first time
you ask by voice; Camera is asked for by the look-away trigger (it can be turned off in the menu). The app is signed so that
the permission survives rebuilds. The first launch of a new
build takes a few minutes while Core ML compiles the Whisper model.

- **⌥Space** ask a question about the screen or what was said
- **⌥C** catch me up
- **⌥S** stop speaking (cuts the voice off at once)
- **⌥V** ask a question out loud (study mode); it stops by itself when you pause

## Try it with the demo material

Everything the demo uses is in `demo/` and was written for this project: a narrated slide lecture, a two-page
paper and a three-person call. Build the audio once with `python3 scripts/make_demo_assets.py --user Yusuf`.

- **Study mode.** Open `demo/lecture/slides.html` full screen and press Start. Look away for ten seconds and
  back: a catch-up card. Ask "Which curve diverges?" (needs the chart) or "When are office hours?" (said on
  slide 1, never shown).
- **Call mode.** Switch to Call and play `demo/call/call.wav`. Twice someone asks Yusuf a question by name:
  a card with the question and a suggested reply. At the end, "…" menu, Session notes: decisions and action
  items by speaker, with the three names worked out from the conversation.

The full run sheet with expected answers is in [demo/README.md](demo/README.md).

## Testing a branch (Mac mini only)

All building and testing happens on one Mac mini; laptops are for writing code.

```sh
./scripts/check.sh <branch>        # build + benchmarks in a separate working copy, prints PASS or FAIL
./scripts/check.sh <branch> app    # the same, then launches that branch's app for a live test
```

## Changing a prompt or a test case

Prompts and test cases are data files, so they can be edited on any machine without touching Swift.

- `prompts/watcher.txt` is the watcher's system prompt. The answerer's is `prompts/answerer_common.txt` followed by
  `answerer_question.txt`, `answerer_catch_up.txt` or `answerer_notes.txt`, depending on the task.
- The files are read on every request: an edit shows up in the next answer, with no rebuild and no restart.
  If a file is missing or empty, the copy built into `Bonsai.swift` is used.
- `bench/call.json` is the sample call (line N becomes `L`N), `bench/questions.json` the 10 questions in the merge gate (`bench/questions_more.json` has 10 harder ones:
  `clueless-bench answer 8080 9B questions_more`), each with expected
  keywords (`"a|b"` means either) and acceptable source lines, `bench/watch.json` the watcher lines with `want`,
  `bench/screen.json` the slide questions.
- `clueless-bench prompts` prints which prompt files are in use. Then push and run `./scripts/check.sh <branch>`.

## Layout

```
Sources/CluelessCore   timeline, Bonsai client, watcher, answerer, chunked transcription, OCR, speech
Sources/Clueless       the app: ScreenCaptureKit capture and its restart, floating panel, hotkeys, HUD,
                       webcam presence, server supervision, speech queue, voice questions, receipts,
                       call notes, a camera test window (testing only)
Sources/clueless-bench headless benchmarks (no permissions needed)
scripts/               servers.sh, make_app.sh, check.sh, make_demo_assets.py, smoke_bonsai.py
demo/                  demo assets generated locally: a multi-speaker call, a narrated lecture, a PDF
prompts/               the prompt text for the watcher and the answerer, one .txt file each
bench/                 benchmark test cases as JSON: sample call, questions, watcher lines, slide questions
```

The shared interface: `TimelineLine`, `Watcher.watch(lines, userName) -> Decision`,
`Answerer.answer(task, lines, screenText, image) -> Card`.
