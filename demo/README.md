# Demo assets

Everything the demo plays or shows, stored in the repo and usable with Wi-Fi off. All of it was written
for this project: nothing is downloaded and nothing is someone else's lecture or paper. The course, the
professor, the meeting and the experiment numbers are made up.

| Asset | Files | Used for |
|---|---|---|
| Multi-speaker call, about 2 min 15 s | `call/script.txt` → `call/call.wav` | Call mode: name trigger, catch-up card, speaker names, session notes |
| Narrated slide lecture, about 3 min | `lecture/slides.html`, `lecture/narration.txt` → `lecture/audio/` | Study mode with a lecture on screen |
| PDF paper, 2 pages | `paper/learning-rate-note.pdf` | Study mode with a document on screen |

Each folder also has the expected answers, for checking quality (T04) and for the benchmarks:
`call/expected.json`, `lecture/questions.json`, `paper/questions.json`.

## Build the audio (Mac mini, once)

The audio is generated from the text scripts with the macOS system voices, so it is not committed.

```
python3 scripts/make_demo_assets.py --user Yusuf
```

`--user` is the name the call addresses. It must be the same as "Your name" in the app menu, or the name
trigger will not fire. The script prints which voice it gave each speaker and how long each file is.

The PDF is committed. To change it, edit `paper/make_pdf.js` and run `node demo/paper/make_pdf.js`.

## Run sheet

**Study mode, lecture.** Open `demo/lecture/slides.html` in a browser, make it full screen, press Start.
It plays like a video: each slide advances when its narration ends (Space pauses, arrow keys move).

| When | Ask | What it shows |
|---|---|---|
| Slide 3 | "What is the new weight in the example?" | Answer from the screen text: 1.6 |
| Slide 3 | "What is the update rule?" | A visual question: the screenshot is attached because OCR loses η and ∇ |
| Slide 4 | "Which curve diverges?" | A visual question about a chart: the red one, η = 1.0 |
| Slide 4 | "What should I do if the loss goes up?" | Answer from the transcript only: divide the rate by ten |
| Slide 6 | "When are office hours?" | Said on slide 1, never shown: Tuesday at 3, room 204 |
| Any | look away for 10 s, look back | Catch-up card for what the professor said meanwhile |

**Study mode, PDF.** Open `demo/paper/learning-rate-note.pdf`. Ask "Which learning rate was best?" (0.01,
loss 0.27, 14 epochs) or "Why is 0.1 worse?" (it settles at a higher loss, 0.34).

**Call mode.** Switch to Call, then `afplay demo/call/call.wav` (or play it from another app so it comes
through system audio).

| Time | What happens | What it shows |
|---|---|---|
| about 1:10 | Maya: "Yusuf, can your team still hit Friday for the release candidate?" then 8 s of silence | Name trigger: a catch-up card with the question, what was missed, a suggested reply. Answer out loud; the microphone line shows as "You" |
| about 1:35 | Priya: "Yusuf, who should review the release notes?" then 8 s of silence | A second trigger |
| end | Press "Session notes" | Notes by speaker with names worked out from "Go ahead, Sam", "Thanks, Priya", "Got it, Maya" |

The times are estimates until the audio is built; `call/call_timeline.json` has the real ones.

## Headless checks

```
CLUELESS_AUDIO_FILE=demo/call/call.wav        # plays the call into the app as system audio
CLUELESS_AUDIO_FILE=demo/lecture/lecture.wav  # the same for the lecture narration
.build/release/clueless-bench chunk demo/lecture/lecture.wav demo/lecture/lecture_ref.txt
```

## Using a real lecture or paper instead

Put your own files in `demo/local/` (ignored by git) and play them the same way. Check the licence before
showing someone else's lecture or paper in the submission video.
