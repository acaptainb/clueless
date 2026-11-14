# Clueless: project brief

Hackathon build for the Cornell Local AI Hackathon. Read this fully before writing code.

- Written: Sat Nov 14, 2:30 pm ET
- Deadline: Sun Nov 15, 12:00 noon ET (hard cutoff)
- Team: 2 people, each working with an AI coding tool against this same brief

## 1. What it is

Clueless is a private copilot for the Mac. It watches the screen and listens to system
audio and the microphone, entirely on-device, and catches you up the moment you lose
the thread in a call or a lecture.

- Pitch line: "Cluely tells you what to say. Clueless tells you what you missed."
- Submission sentence: "Clueless is a private copilot that watches your screen and
  listens to your calls and lectures entirely on your Mac, and catches you up the
  moment you lose the thread."

## 2. Hard rules from the organizers

1. Language models: only Bonsai 2 at 2B, 4B or 9B. No other LLM anywhere in the app.
2. Must use Argmax for speech. The SDK is Swift only. The Argmax Local Server API is
   not available to us.
3. Must run on a Mac with Wi-Fi turned off. Nothing may download at run time.
4. Submission in Discord #submissions before noon Sunday: both names, one-sentence
   description, GitHub link, demo video under 2 minutes.
5. Finalists give a 4-minute live demo (own laptop allowed).
6. Judging, in this order: use of Bonsai and Argmax, creativity, wow factor,
   technical impressiveness. Main-track judges are the PrismML and Argmax founders.
7. Organizer note: each Bonsai model takes under 4 GB of RAM, but 2 to 3 times more
   with a large context window. Keep contexts small.

## 3. Scope

Two modes on one engine. Build study mode first.

Study mode
- A lecture video or PDF is on screen. System audio is transcribed live.
- User asks a question (hotkey, typed or spoken). The answer uses the current screen
  plus the last few minutes of transcript. Answer shows as a card and can be spoken.

Call mode
- Microphone = "You". System audio = everyone else.
- Live transcript, end-of-session notes by speaker, names resolved from context
  ("thanks, Priya").

Catch-up (works in both modes, this is the hero feature)
- Triggers: hotkey, the user's name is spoken, or the webcam sees the user look away
  and come back.
- Output card: what you were asked, what you missed, a suggested reply, and sources.

Receipts
- Every answer lists the timeline lines it used. The UI turns them into speaker +
  timestamp or a screen snapshot.

If the Argmax Pro key arrives
- Live speaker labels.
- Custom vocabulary built from words seen on screen (names, jargon).

Out of scope, do not build
- Anything "undetectable" or hidden from screen share. Show a visible recording
  indicator instead.
- Any network call other than localhost.
- Follow-up emails, CRM, pre-call research, flashcards.

## 4. Architecture

Two kinds of process, all on the same Mac.

A. Clueless.app (native macOS, SwiftUI, target macOS 15)
- Capture: ScreenCaptureKit for screen frames, system audio and microphone.
- Speech: Argmax SDK (WhisperKit for transcription, SpeakerKit for speaker labels,
  TTSKit for spoken answers).
- Screen text: Apple Vision text recognition on a screenshot. This is OCR, not a
  language model.
- Presence: webcam through AVFoundation plus Apple Vision face detection.
- Timeline: one numbered, timestamped log (in memory, appended to a JSONL file).
- Triggers, prompts, overlay UI (floating always-on-top panel), HUD.

B. Bonsai servers (PrismML's llama.cpp fork, OpenAI-compatible HTTP on localhost)
- 9B "answerer" on port 8080, started with the vision projector (mmproj). Uses the MTP file with
  `draft-mtp` speculation (1.5x faster, same answers; see BENCHMARKS.md).
- 4B "watcher" on port 8082. (Changed from 2B on Nov 14: 16/16 vs 13-14/16 on the watcher test set.)
- The app calls POST /v1/chat/completions on each. Localhost works with Wi-Fi off.

Fallback if neither teammate can work in Swift: keep a small Swift helper that owns
capture and speech and exposes them over a localhost WebSocket, and build the UI and
logic in TypeScript or Python. Decide this during milestone 0 and do not switch later.

### Timeline line

```
id        Int, monotonic
t         timestamp
source    "them" | "me" | "screen" | "webcam" | "system"
speaker   optional string ("Speaker 2", later a real name)
text      string
snapshot  optional path to a saved screenshot
```

Rendered into prompts as: `[L215 14:03:10] Maya: Yusuf, can your team still hit Friday?`

### Watcher (Bonsai 4B, was 2B)

- Runs on new "them" lines only, and only after a cheap code check passes (the
  user's name or a question mark is present). Do not call a model when a regex will do.
- Input: the last ~6 lines and the user's name.
- Output JSON: `{"needs_user": true|false, "reason": "name"|"question"|"none"}`
- Thinking off, small max_tokens.

### Answerer (Bonsai 9B)

- Runs only when triggered.
- Input: task type (catch_up | question | notes), the last few minutes of numbered
  timeline lines, current screen text, optionally one downscaled screenshot.
- Output JSON for catch-up:
  `{"asked": "...", "missed": "...", "reply": "...", "sources": [215, 212, 213]}`
- Thinking off for cards (speed). Thinking on is optional for hard study questions.

### The interface the two teammates share

Agree on these before splitting work:
- the timeline line format above
- `watch(lines, userName) -> Decision`
- `answer(task, lines, screenText, image?) -> Card`

## 5. Technical notes gathered from the docs on Nov 14

Treat these as leads to confirm, not gospel. Links are in section 9.

Bonsai 2
- GGUF repos: `prism-ml/Ternary-Bonsai-2-9B-gguf` and `prism-ml/Ternary-Bonsai-2-2B-gguf`.
- 9B files: `Ternary-Bonsai-2-9B-PQ2_0.gguf` (2.42 GB) and
  `Ternary-Bonsai-2-9B-mmproj-Q8_0.gguf` (0.62 GB).
- 2B files: `Ternary-Bonsai-2-2B-PQ2_0.gguf` (0.52 GB) and
  `Ternary-Bonsai-2-2B-mmproj-Q8_0.gguf` (0.36 GB).
- PQ2_0 and PTQ1_0 files need PrismML's llama.cpp fork. Only the Q2_0 file runs on
  upstream llama.cpp (b11556 or newer; older builds give wrong output silently).
- Confirmed Nov 14: the fork builds from source with Command Line Tools + cmake in about a minute
  (`git clone -b prism https://github.com/PrismML-Eng/llama.cpp.git`, see README). Model files download
  directly from the Hugging Face `resolve/main/` URLs; `SHA256SUMS` is in each repo.
- Alternative way to get the fork binaries and a model (not used):
  `git clone https://github.com/PrismML-Eng/Bonsai-demo.git`, then
  `export BONSAI_MODEL=9B` and `./setup.sh`. Setting `BONSAI_OPENWEBUI=0` and
  `BONSAI_CODE_INTERPRETER=0` skips extras. If setup starts pulling the 27B (about
  7.8 GB), stop it and download the files above with `hf download` instead.
- Server command from the model card:
  `./bin/llama-server -m Ternary-Bonsai-2-9B-PQ2_0.gguf --mmproj Ternary-Bonsai-2-9B-mmproj-Q8_0.gguf -ngl 99 -fa on -c 32768 --port 8080`
  Use a smaller `-c` (8192 to 16384) to save RAM.
- Images: OpenAI-style `image_url` content parts on `/v1/chat/completions`. The
  server must be started with `--mmproj`. Use the Q8_0 projector; the BF16 one can
  crash under concurrent image requests.
- For small or dense text in images, try `--image-min-tokens 1024`.
- Thinking is on by default. Turn it off per request with
  `"chat_template_kwargs": {"enable_thinking": false}`.
- Sampling, thinking off: temperature 0.7, top_p 0.8, top_k 20, presence_penalty 1.5.
- Sampling, thinking on: temperature 1.0, top_p 0.95, top_k 20, presence_penalty 1.0,
  and allow at least 8192 output tokens. Do not use temperature 0 with thinking on.
- Tool calls use the native OpenAI `tool_calls` format.
- Speedup on 9B and 4B: the `...-PQ2_0-MTP-Q8_0.gguf` file with
  `--spec-type draft-mtp --spec-draft-n-max 2`. Confirmed on 9B: 14 -> 20-23 tok/s, works with `--mmproj`.
- LM Studio is optional: PrismML's guide says it needs the Q2_0 file and a llama.cpp
  runtime of b11555 or later, otherwise output is gibberish.

Argmax
- Swift package: `https://github.com/argmaxinc/argmax-oss-swift`. Products:
  `ArgmaxOSS` (everything) or `WhisperKit`, `SpeakerKit`, `TTSKit` individually.
- Requirements: macOS 14+, Xcode 16+. TTSKit needs macOS 15+.
- WhisperKit: `let pipe = try await WhisperKit()` then
  `try await pipe.transcribe(audioPath:)` or `transcribe(audioArray:)`.
- SpeakerKit: `try await speakerKit.diarize(audioArray:)`, then
  `diarization.addSpeakerInfo(to: transcription)` for "who said what".
- TTSKit: `let tts = try await TTSKit()` then `try await tts.play(text:)`. Models:
  0.6B (about 1 GB) and 1.7B (about 2.2 GB, macOS only). Nine voices, ten languages.
- Confirmed: `swift build -c release --product argmax-cli` works without full Xcode. So does our app
  (SwiftPM + `scripts/make_app.sh`); no Xcode project is needed.
- `AudioStreamTranscriber` only records from a microphone device. For system audio we chunk buffers
  ourselves and call `transcribe(audioArray:)` (pause-based chunks, see BENCHMARKS.md).
- TTSKit downloads to `~/Documents/huggingface/models/...`; we copy that into `models/argmax/` and load
  with `modelFolder:` / `tokenizerFolder:`.
- A new build's first launch spends minutes compiling the Whisper Core ML model. Launch before demos.
- CLI for smoke tests (built from the repo): `argmax-cli transcribe --stream`,
  `argmax-cli tts --text "..." --play`, `argmax-cli diarize --audio-path ...`.
  Homebrew also has `whisperkit-cli`.
- Models are fetched from Hugging Face on first run. Pre-download them and load from
  a local folder so nothing touches the network during the demo.
- Keep every model loaded for the life of the app. Reloading per utterance is the
  classic cause of lag in local voice loops.
- Pro SDK (only if the organizer sends a key): real-time transcription with speakers,
  and custom vocabulary via
  `WhisperKitProConfig(customVocabularyConfig: .init(words: [...]))` or
  `try whisperKitPro.setCustomVocabulary([...])`. Alpha feature, English letters
  only, up to 1000 keywords.
- Without Pro: transcribe short chunks as they arrive, and compute speaker labels
  once at the end of the session with SpeakerKit on the recorded system audio.

ScreenCaptureKit and macOS
- One `SCStream` can deliver three outputs: `.screen`, `.audio` (system audio,
  `capturesAudio = true`) and `.microphone` (`captureMicrophone = true`, macOS 15+).
- System audio and microphone arrive as separate buffers with different formats and
  clocks. Convert each to 16 kHz mono Float32 before transcription.
- Set `excludesCurrentProcessAudio = true` so the app does not hear its own speech.
- One-off screenshots: `SCScreenshotManager.captureImage(contentFilter:configuration:)`.

## 6. Unverified, check these first

- Whether `./setup.sh` in Bonsai-demo honors `BONSAI_MODEL=9B` and ships macOS
  binaries of the fork. If not, build the fork from source.
- The WhisperKit Swift API for streaming raw audio buffers. Look in the package
  source for a stream transcriber before writing a chunking loop by hand.
- 9B latency on this Mac for one 1024-pixel-wide screenshot plus a short prompt.
- TTSKit time to first audio on this Mac (0.6B vs 1.7B).
- RAM on both laptops (`sysctl hw.memsize`). On 16 GB, consider 4B as the answerer.
- Likely macOS gotchas: Screen Recording, Microphone and Camera permissions need
  usage strings in Info.plist; permissions can reset when the code signature changes,
  so set a signing team and keep the bundle ID stable; the App Sandbox gets in the
  way of talking to local servers and should probably be removed for this build.
- Ask the organizer: is Apple's built-in OCR fine under the "LLMs must be Bonsai" rule?
- Argmax Pro key: requested by DM? received?

## 7. Milestones

Times are targets. After each milestone, confirm it works with Wi-Fi off and tag the
commit (`git tag m1`). Never leave main broken.

| Milestone | Target | Done when |
|---|---|---|
| M0 Smoke tests | Sat 4:00 pm | 9B answers a text prompt and a screenshot prompt over curl; 2B answers; argmax-cli transcribes a wav and speaks a sentence; all with Wi-Fi off; latencies written down |
| M1 Study mode | Sat 7:30 pm | App transcribes system audio into the timeline; hotkey question gets an answer using screen text; answer is shown and spoken |
| M2 Catch-up | Sat 10:30 pm | Hotkey and look-away triggers produce a catch-up card with receipts |
| M3 Call mode | Sun 1:30 am | Mic = You, system audio = Them; name trigger through the watcher; end-of-session notes by speaker with names |
| M4 Pro features | only if key arrived | Live speaker labels; vocabulary from screen words |
| M5 Ship | Sun 8:00 to 11:30 am | HUD (latency per stage, RAM, tokens per second, network off), README, video under 2 minutes recorded, submitted by 11:30 |

Feature freeze: Sun 2:00 am at the latest. After that, only fixes and the demo.

## 8. Workstreams

Person A, the app
- Xcode project, permissions, ScreenCaptureKit capture, audio conversion
- timeline store, overlay panel, hotkeys, webcam presence, HUD

Person B, the models
- Bonsai servers, watcher and answerer prompts, JSON contracts and parsing
- a small test set (about 20 questions over a sample timeline) to compare 2B, 4B, 9B
  on accuracy and latency
- Argmax speech output, speaker labels, notes

Demo assets, all stored locally
- a lecture video file and a PDF paper for study mode
- a 2 to 3 minute recorded multi-speaker call for call mode

## 9. Working rules for the coding agent

- Work one milestone at a time. Do the smallest thing that satisfies "done when".
- Build after every change and fix errors before moving on.
- No network calls except localhost. No new dependencies without asking.
- Do not commit model files; add them to .gitignore.
- Keep the README current; the judges get the GitHub link.
- If a note in section 5 turns out wrong, fix this file.

References
- Bonsai docs: https://docs.prismml.com/get-started/introduction
- Bonsai server: https://docs.prismml.com/run/server
- Bonsai in LM Studio: https://docs.prismml.com/integrations/lmstudio
- Bonsai 9B model card: https://huggingface.co/prism-ml/Ternary-Bonsai-2-9B-gguf
- Bonsai demo repo: https://github.com/PrismML-Eng/Bonsai-demo
- Argmax open-source SDK: https://github.com/argmaxinc/argmax-oss-swift
- Argmax Pro docs: https://app.argmaxinc.com/docs
- Argmax custom vocabulary: https://app.argmaxinc.com/docs/examples/custom-vocabulary
- ScreenCaptureKit: https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos
