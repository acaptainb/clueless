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
| Wi-Fi off | **works** (Sun Nov 15, Aziz in person: the whole app ran with Wi-Fi turned off; Wi-Fi is this Mac's only network connection. No timings were taken. Servers run with `--offline`, speech models load from `models/`) |

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

## 5. Streaming the card (`clueless-bench stream`)

Catch-up card on the sample call, 9B-MTP, warm.

| | Time |
|---|---|
| First words visible | 0.8 s |
| "You were asked" complete | 2.1 to 2.5 s |
| Whole card | 6.3 s |

The app streams, so the user reads the first field while the rest is written. Without streaming nothing shows for 6 s.

## 6. In-app end to end

- Played-back file (`CLUELESS_AUDIO_FILE` hook): 18 transcript lines kept pace with real time (0.6 s transcribe
  per chunk); typed question answered correctly in 4.9 s with receipts [15, 17]; catch-up card in 4.8 s.
- Live capture (Screen Recording granted): the lecture played through the speakers was transcribed in real time
  through ScreenCaptureKit system audio, 0.6 s per chunk. A live question with a real full-screen capture took
  7.5 s (OCR 924 characters, 95 KB screenshot, 1146 prompt tokens, first token after 6.1 s). The image is what
  makes the first token slow; OCR-only is the faster setting.
- Not yet verified live: answer correctness against a real lecture on screen, spoken answers, hotkeys,
  call mode with the microphone, Wi-Fi off.

## 7. Second round, Saturday evening (engine work from PRs #6, #7, #8)

Measured Sat Nov 14, 7:10 to 7:40 pm on the Mac mini, `main @ 6e9d4e8`. The machine is much faster than in the
afternoon numbers above: the 9B now generates at about 68 tok/s (15 to 23 before), a question card takes about
0.9 s and a catch-up about 1.6 s. Nothing in the code explains a 3x change; the afternoon runs were made with
27 of 32 GB of memory in use.

Gate: `PASS main @ 6e9d4e8: build ok, questions 10/10, catch-up 3/3, watcher 16/16`, self-test 21/21,
extra question set (`questions_more`) 10/10.

### Screenshot cost (T08, `clueless-bench screencost`)

Correct answers, and seconds to first token, by what is sent. "auto" sends the screenshot only for visual questions.

| What is on screen | ocr | both 1024 | both 768 | both 512 | auto 1024 | auto 768 | auto 512 |
|---|---|---|---|---|---|---|---|
| Test slide alone, 6 questions | 5/6, 0.31 s | 6/6, 1.79 s | 6/6, 1.11 s | 6/6, 0.74 s | 6/6, 0.58 s | 6/6, 0.45 s | 6/6, 0.39 s |
| Same slide in a window on the real 1920x1080 screen | 5/6, 0.69 s | 6/6, 0.94 s | 6/6, 0.82 s | 6/6, 0.76 s | 6/6, 0.70 s | 5/6, 0.69 s | 6/6, 0.68 s |
| Demo lecture slide 4 (chart, 2 colour questions) | 0/2, 0.31 s | 2/2, 1.67 s | 2/2, 1.07 s | 1/2, 0.74 s | 2/2, 1.69 s | 2/2, 1.07 s | 1/2, 0.73 s |
| Demo lecture slides 3, 5, 6 (5 questions) | 5/5 | 5/5 | 5/5 | 5/5 | 5/5 | 5/5 | 5/5 |
| Demo paper page 1 (8 questions) | 8/8, 0.72 s | 8/8, 0.99 s | 8/8, 0.87 s | 8/8, 0.79 s | 8/8, 0.67 s | 8/8, 0.66 s | 8/8, 0.66 s |
| Demo paper page 2 (3 questions, one about the figure) | 3/3, 0.48 s | 3/3, 2.48 s | 3/3, 1.55 s | 3/3, 0.94 s | 3/3, 1.17 s | 3/3, 0.85 s | 3/3, 0.64 s |

- The policy check is 17/17. In the live app, "when is the homework due" went out with no image (0.9 s) and
  "which curve diverges, and what colour is it" attached the screenshot and answered "red" (2.5 s at 1024).
- **Default image size is now 768** (was 1024). 512 loses the colour of the diverging curve on the chart slide;
  768 gets every visual question and reaches the first token about 0.6 s sooner than 1024. The one miss in the
  768 column (real screen, update rule written with "n" for eta) also happens with OCR alone and passed at the
  other sizes, so it is run-to-run variation, not the size.
- OCR alone cannot answer questions about colour or shape (0/2 on the chart slide), which is why auto matters.

### Prompt layout (T09, `clueless-bench cache`)

| Layout | Prompt tokens evaluated | Cached | First token | Whole card |
|---|---|---|---|---|
| classic (old order) | 326 | 208 | 0.47 s | 1.30 s |
| stable (new default) | 412 | 123 | 0.58 s | 1.31 s |

Read on its own this says the new layout is not a win. The next table shows why: classic was being helped by the
server's 8 GB host prompt cache, and stable does not need it.

### Answerer memory and the host prompt cache (`--cache-ram`)

`llama-server` keeps evaluated prompts in host memory, 8 GB by default. Each entry here is 330 to 450 MiB, so the
answerer grew from 2.0 GB at start to 10 GB after about 35 minutes of tests and stayed there (the log fills with
"making room for prompt cache entry"). Measured again with the cache off (`--cache-ram 0`):

| Host cache | Layout | Prompt tokens evaluated | Cached | First token | Whole card | Answerer memory after the runs |
|---|---|---|---|---|---|---|
| 8 GB (default) | classic | 326 | 208 | 0.47 s | 1.30 s | 10 GB |
| 8 GB (default) | stable | 412 | 123 | 0.58 s | 1.31 s | 10 GB |
| off | classic | 467 | 67 | 0.72 s | 1.57 s | 1.6 GB |
| off | stable | 412 | 123 | 0.59 s | 1.32 s | 1.6 GB |

With the cache off the gate still passes (`PASS main @ 3b0b76e`, questions 10/10, extra set 10/10) and the stable
layout is unchanged, because it reuses the live context instead of the host cache. So stable + cache off costs
about 0.1 s to first token against the best case and saves about 8 GB. `scripts/servers.sh` now starts the
answerer with `--cache-ram 0`; `ANSWERER_CACHE_RAM=8192` restores the old behaviour.

### Names and call notes (T13, T14, T15)

- `clueless-bench names`: **7/12** over 3 runs (expected 10 to 12). The resolver gives a name to the person who
  SAID it instead of the person addressed: Sam becomes "Maya", and Maya stays "Speaker 1".
- `clueless-bench speakers demo/call/call.wav 3`: 3 speakers found in 23 turns, 0.31 s to label.
- `clueless-bench notes 8080 demo/call/call.wav`: 36 lines transcribed, but **6 speakers heard and no names
  resolved**, so the notes say "Speaker 4", "Speaker 5". The content is mostly right (Friday release candidate,
  Thursday 10 pm maintenance window, 12k budget, tablet layout cut) with one invented item ("Sam fixed push via
  spy website"). Without a speaker count SpeakerKit over-splits the three synthetic voices, and one chunk can
  hold two people ("Go ahead, Sam! The API changes are merged").
- Setup note: SpeakerKit models must be in `models/argmax/speakerkit-coreml`. On the Mac mini they had been
  downloaded to `models/argmax/models/argmaxinc/speakerkit-coreml` and were copied across.

### Word-safe cuts (T19, `clueless-bench chunk` on the 162 s demo lecture)

| Method | Word error | Chunks | Avg lag | Worst lag |
|---|---|---|---|---|
| Cut at a pause, 2 to 8 s, word-safe forced cut | 10.4% | 44 | 2.2 s | 8.2 s |
| Same, hard forced cut | 10.4% | 44 | 2.2 s | 8.5 s |
| Fixed 5 s | 18.9% | 33 | 2.9 s | 5.6 s |

No measurable difference on this recording: the narrator pauses often, so forced cuts are rare.

### Single-server control (T27)

`servers.sh stop watcher` leaves 8080 up and 8082 down; `start watcher` brings it back and the answerer keeps
the same process id.

### Real material (T04)

Headless, against the demo assets: PDF pages and lecture slides rendered to full-screen images, default policy
(auto, 768 px), plus one full run of the 162 s demo lecture through the app.

| Material | Questions | Result |
|---|---|---|
| Paper, page 1 | 8, from the text | 8/8, about 1.1 s each |
| Paper, page 2 | 3, one about the figure | 3/3 |
| Lecture slides 3, 5, 6 | 5, from the screen | 5/5 |
| Lecture slide 4 (chart) | 2, colour of the curves | 2/2 with the screenshot (0/2 from OCR alone) |
| Lecture audio, "When are office hours this week?" asked at the end | 1 | **MISS**: "The provided timeline does not contain information about office hours" |

The miss is not the model. The line was transcribed correctly ("My office hours this week moved to Tuesday at 3")
but never reached the model: a question sends at most 45 timeline lines, the lecture made 45 lines in 162 s
(chunks average 3.7 s), and the stepped window then drops the oldest ten. The 5-minute window holds about
80 lines at this pace. Fix: raise the cap (about 120 lines is roughly 1,600 tokens, under a second of prompt
time at the current speed) or join consecutive chunks from one speaker into one line. This question is on the
demo run sheet, so it matters. The other four audio questions and the live browser lecture were not run.

## 8. Third round, Saturday night (fixes for what section 7 found)

Measured Sat Nov 14, 8:40 to 9:00 pm on the Mac mini. Gate after all of it:
`PASS aziz/lecture-questions @ 44a6642: build ok, questions 10/10, catch-up 3/3, watcher 16/16`, self-test 24/24.

### Call notes with real speakers and names (T35)

| | Section 7 | Now |
|---|---|---|
| `clueless-bench names` | 7/12, one model call | 12/12, 0.00 s, no model call |
| Notes from `demo/call/call.wav` | 6 to 7 speakers, no names | Maya, Sam and Priya on 18 of 20 lines |
| Time before the notes start | 2.4 s | 8.1 s |
| Notes card | 8.6 s | 4.6 s |

What changed: the recording is transcribed again one speaker turn at a time (a live line could hold two people),
and names come from code: who is addressed and who answers. In the app the same call gives
`names: Speaker 1 = Maya, Speaker 2 = Sam, Speaker 3 = Priya`, 19 of 19 lines labelled, and notes that read
"Maya decided to cut the tablet layout... Sam will fix the push notification service by Wednesday."
Two short lines after the 8 s pauses still land in a fourth cluster ("Speaker 4").

The demo call's voices matter to SpeakerKit. At its default clustering setting:

| Voices (Maya, Sam, Priya) | Speakers found | Notes |
|---|---|---|
| Albert, Daniel, Karen (the script's old pick; Albert is a novelty voice) | 6 | Maya split in three, Priya in two |
| Samantha, Daniel, Karen | 4 | Maya and Priya mixed |
| Samantha, Daniel, Moira | 4 | |
| Samantha, Daniel, Tessa | 5 | |
| **Samantha, Daniel, Tara** | 4 | the three people are separated turn by turn; one small extra cluster |

Raising the clustering threshold is not a fix: for one voice set 1.0 gave exactly 3 and 1.1 collapsed everyone
into one speaker; for another it changed nothing. Real voices have not been tried.

### Catch-up cards from what was said (T34, `clueless-bench grounding`)

| Case, three runs each | Before | After |
|---|---|---|
| Nothing said, terminal on screen | 0/3 | 3/3 (no model call) |
| Lecture playing, terminal on screen | 2/3 | 3/3 |
| Question to the user in a call, terminal on screen | not comparable | 3/3 |
| Lecture playing, matching slide on screen | 3/3 | 3/3 |

The screen text in a catch-up is now labelled as background and cut to 600 characters; average card 1.40 s
(1.65 s before). The third case has no fair "before": the first version of the test banned a word the call uses.

### Lecture audio questions (T04, T10, `clueless-bench lecture`)

162 s demo lecture, 44 lines, all sent with each question: **4/5**, 1.3 s average. Office hours, Cauchy 1847,
"divide the learning rate by 10" and "start at 0.01" are right. The miss, "What does the midterm cover", answers
"lectures through 8": a forced 8 s cut fell inside "it covers lectures one through eight" and Whisper lost
"s lectures one" across the two chunks. The word-safe cut (T19) does not prevent it.

### Words lost at a forced cut (T37)

When nobody pauses for 8 s the chunk is cut at the quietest 50 ms near its end. Looking back 3 s for that gap
instead of 1.5 s:

| Search window | Lecture audio questions | Word error, demo lecture | Word error, short lecture | Avg lag |
|---|---|---|---|---|
| 1.5 s (before) | 4/5 | 10.4% | 4.4% | 2.2 s |
| **3 s (now)** | 5/5 | 10.4% | 4.4% | 2.2 s |
| 4.5 s | 5/5 | 10.4% | 4.4% | 2.2 s |

Padding each chunk with 0.3 or 0.6 s of silence was also tried and did not help (word error 10.6 to 10.8%,
questions 3/5 and 4/5).

### Soak, file-fed (T18, first half)

21.6 minutes of lecture through `CLUELESS_AUDIO_FILE`: no crash, 340 lines. App 300 MB at the start and 325 to
366 MB at the end; answerer 1.2 GB throughout; watcher 0.25 to 0.29 GB; transcription 0.40 s per chunk at the
start and at the end. The question at the end was right, but took 3.4 s to its first token: 120 lines are about
2,600 prompt tokens and none were cached.

### First word late in a long session, and why a background prewarm is not in the app (`clueless-bench prewarm`)

A question after 20 minutes waits 3.4 s for its first word: 120 lines are about 2,600 prompt tokens, none cached.
`Answerer.prewarm` reads the timeline into the server's cache ahead of time. In the bench it works:

| 120-line timeline, same question | Whole card | Prompt tokens read | Cached |
|---|---|---|---|
| Cold (something else was asked before) | 7.9 to 8.8 s | 4,864 | 0 |
| After a prewarm (7.1 s, in the background) | 1.6 s | 577 | 4,287 |
| Three new lines, top-up (0.9 s), then the question | 1.6 to 2.1 s | 577 | 4,361 |

Wired into the app (a prewarm after new lines, at most every 6 s) it did **not** help, measured on an 8-minute
lecture: the question at the end still took 3.45 s to its first token, 54 prewarms cost 0.86 s each (the server
re-reads about 600 tokens from its last checkpoint every time, even for two new lines), and catch-up cards
running at the same moment got slower (first token up to 4.1 s, against 0.5 to 1.4 s). The reason: a catch-up
sends a different slice of the timeline than a question, and the server keeps one cached prompt, so every
catch-up throws away what the prewarm built. The wiring was taken out again; the function and the bench stay.
To make it pay off, questions and catch-ups have to send the same timeline lines (and say in the instructions
which part matters), so one cache serves both.

### Other

- TTSKit loads with `download: false` from `models/argmax` (25 s first load in a new binary) and speaks.
- Closing the camera test window: before the fix the app quit; after it the app keeps running (checked with
  the `CLUELESS_CAMERA_TEST_CLOSE` hook, which closes the window the way the red button does).

## Known issues

- First launch of a new build spends minutes compiling the Whisper Core ML model (6 min in the app, 2 min in the
  bench tool). Later launches take seconds. Launch once before any demo.
- A forced cut at 8 s can split a word across two lines.
- With a screenshot attached the first token takes about 6 s (image encoding). Consider OCR-only by default,
  or a smaller image.
