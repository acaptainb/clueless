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

## Status

| Milestone | State |
|---|---|
| M0 smoke tests | Done, except the Wi-Fi-off run |
| M1 study mode | Built. Verified end to end on a played-back lecture file; live capture needs Screen Recording permission to verify |
| M2 catch-up | Hotkey catch-up card with receipts works; look-away trigger not built |
| M3 call mode | Microphone = You and the watcher trigger are wired; untested live. Notes exist; speaker names not built |

Measurements and the method comparisons behind each default are in [BENCHMARKS.md](BENCHMARKS.md).
The full plan is in [BRIEF.md](BRIEF.md).

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
```

## Run (offline)

```sh
./scripts/servers.sh start      # Bonsai 9B on :8080, 4B on :8082, localhost only
./scripts/make_app.sh run       # builds build/Clueless.app and launches it
```

Grant Screen Recording (and Microphone for call mode) when macOS asks, then relaunch. The first launch of a new
build takes a few minutes while Core ML compiles the Whisper model.

- **⌥Space** ask a question about the screen or what was said
- **⌥C** catch me up
- **⌥S** stop speaking

## Layout

```
Sources/CluelessCore   timeline, Bonsai client, watcher, answerer, chunked transcription, OCR, speech
Sources/Clueless       the app: ScreenCaptureKit capture, floating panel, hotkeys, HUD
Sources/clueless-bench headless benchmarks (no permissions needed)
scripts/               servers.sh, make_app.sh, smoke_bonsai.py
```

The shared interface: `TimelineLine`, `Watcher.watch(lines, userName) -> Decision`,
`Answerer.answer(task, lines, screenText, image) -> Card`.
