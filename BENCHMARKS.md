# Benchmarks

Measured Sat Nov 14 on an Apple M6 (2 performance + 4 efficiency cores), 32 GB, macOS 27.2,
with other apps running and memory under pressure (27 GB in use). Re-run on the demo laptop.

Reproduce: `./scripts/servers.sh start`, `swift build -c release`, then `.build/release/clueless-bench …`.
Test audio is synthetic (`say`), so word error rates are optimistic; the ranking between methods is what matters.

## M0 smoke tests

| Check | Result |
|---|---|
| 9B text prompt over HTTP | ok, 1.9 s for 33 tokens |
| 9B screenshot prompt (1024 px slide) | ok, all three facts read correctly, 5.3 s cold / 3.3 s warm |
| 2B watcher JSON | ok, 0.3 to 0.6 s |
| `argmax-cli transcribe` (large-v3-v20240930_626MB) | ok, 3.2 s for 10.6 s of audio, warm |
| `argmax-cli tts` (0.6B) | ok, 0.09 s to first audio, faster than real time (RTF 0.72) |
| `argmax-cli diarize` | ok |
| Wi-Fi off | **not yet verified** (servers run with `--offline`, speech models load from `models/`) |

Memory: 9B server 4.0 GB, 2B server 0.8 GB, app about 0.2 GB plus Core ML models.

## 1. Answerer model (`clueless-bench answer`)

10 questions over an 11-line call, then 3 catch-up runs. Each model ran alone.

| Model | Questions correct | Receipts correct | Valid JSON | Avg question | Avg catch-up | Speed |
|---|---|---|---|---|---|---|
| 9B PQ2_0 | 10/10 | 10/10 | 10/10 | 2.22 s | 7.22 s | 14 tok/s |
| **9B PQ2_0-MTP + `draft-mtp`** | 10/10 | 10/10 | 10/10 | 1.94 s | 4.91 s | 20 to 23 tok/s |
| 4B PQ2_0 | 10/10 | 10/10 | 10/10 | 1.59 s | 4.74 s | 21 tok/s |

Chosen: **9B with MTP speculative decoding.** Same answers as plain 9B, about 1.5x faster, and it keeps vision.
The 4B matched it on this small set and wrote thinner session notes (one cited line vs all eleven); keep it as the
fallback for a 16 GB laptop. JSON-constrained output costs nothing measurable (14.0 vs 14.1 tok/s on 9B).

## 2. Watcher (`clueless-bench watch`)

16 lines, 8 that need the user and 8 that do not (other people addressed, name mentioned in passing, rhetorical questions).

| Method | Correct | Latency per model call |
|---|---|---|
| Code check alone (name or "?") | 10/16 | 0 |
| Code check + 2B | 13 to 14/16 | 0.55 s |
| **Code check + 4B** | 16/16 (two runs) | 0.97 s |
| Code check + 9B | 16/16 (two runs) | 1.03 s |

Chosen: **4B as watcher.** The 2B missed group questions ("any questions before we wrap up?") and sometimes
fired on questions aimed at someone else. The code check still skips the model on lines with no name and no question mark.

## 3. Screen input (`clueless-bench screen`)

6 questions about one lecture slide, 9B-MTP.

| Method | Correct | Avg latency | Prompt tokens |
|---|---|---|---|
| OCR text only (Apple Vision) | 5/6 | 1.7 s | 319 |
| Screenshot only (1024 px) | 6/6 | 4.1 s | 696 |
| **Screenshot + OCR text** | 6/6 | 4.4 s | 803 |

OCR alone lost the math (`w ← w − η·∇L(w)` came out as `w = w - n • VL(W)`). The app defaults to screenshot + OCR
and has a menu setting for OCR only when speed matters. Not yet tested on a real full-screen capture, where a
1024 px downscale will make small text unreadable to the vision model and OCR should carry more of the load.

## 4. Live audio chunking (`clueless-bench chunk`)

67 s lecture, WhisperKit large-v3-v20240930_626MB. Lag = how long a word waits before it appears in the timeline.

| Method | Word error | Avg lag | Worst lag | Transcribe time per chunk |
|---|---|---|---|---|
| Fixed 3 s | 9.7% | 2.0 s | 3.7 s | 0.57 s |
| Fixed 5 s | 5.7% | 3.0 s | 5.7 s | 0.62 s |
| Fixed 10 s | 4.4% | 5.6 s | 10.9 s | 0.78 s |
| **Cut at a pause, 2 to 8 s** | 4.4% | 2.5 s | 8.7 s | 0.60 s |
| Cut at a pause, 3 to 12 s | 4.8% | 3.4 s | 12.8 s | 0.60 s |
| Cut at a pause, 5 to 15 s | 4.4% | 4.0 s | 13.6 s | 0.67 s |

Chosen: **cut at the first pause after 2 s, forced cut at 8 s.** It matches the accuracy of 10 s windows at less
than half the lag. Fixed short windows cut words in half. WhisperKit's built-in `AudioStreamTranscriber` only reads
from a microphone device, so system audio needs this chunk loop.

## 5. In-app end to end

Test lecture played into the app through the `CLUELESS_AUDIO_FILE` hook: 18 transcript lines kept pace with real
time (0.6 s transcribe per chunk); typed question answered correctly in 4.9 s with receipts [15, 17]; catch-up card
in 4.8 s. Real screen and audio capture is untested until Screen Recording permission is granted.

## Known issues

- First launch of a new build spends minutes compiling the Whisper Core ML model (6 min in the app, 2 min in the
  bench tool). Later launches take seconds. Launch once before any demo.
- A forced cut at 8 s can split a word across two lines.
- Cards appear all at once after 2 to 8 s. Streaming the answer into the card would make it feel much faster.
