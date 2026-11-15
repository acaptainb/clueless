# Sunday: what is left, in order

Written Sun Nov 15, 1:55 am by Yusuf's MacBook session (updated 2:50 am), from STATUS.md, WORKLOG.md and the in-person log
of Sat night. Deadline: submit by 11:30 am (hard cutoff 12:00 noon). Feature freeze 2:00 am: after that,
fixes only.

## Where things stand

| Area | State | Seen by a person? |
|---|---|---|
| Study mode: live transcript, typed question, screen answers | Works in scripted runs; paper 11/11, lecture slides 7/7, lecture audio 5/5 | Transcript yes. A typed question: no |
| Look-away catch-up (the hero feature) | Works with a real person: 4 of 4 cards, 31 short glances ignored, no crash in 2.5 h | Yes (Aziz, Sat 10:45 pm) |
| Spoken answers | Queued 1.7 to 2.0 s after the trigger; not transcribed back | Yes (Aziz, Sat night) |
| Hotkeys ⌥Space, ⌥C, ⌥S, ⌥V | Wired | No |
| Spoken question (⌥V) | Wired; never tried with a real voice | No |
| Call mode: You / Them, name trigger, notes with names | Works on the demo call through the file hook (Maya, Sam, Priya named) | No: needs the microphone and the speakers |
| Servers restart, capture restart | Server restart seen in a scripted kill; capture restart has never fired | No |
| Wi-Fi off (hard rule 3) | Ran fine with Wi-Fi off (Aziz, Sat night; Wi-Fi is the Mac mini's only connection). No timings written down; repeat once on the final build | Yes |
| Soak | 22 min through the file hook: no crash, memory flat | Live half not done |

Open code: PR #35 (T39, small fixes) and PR #37 (T41, nine fixes from an independent review of the app
code, stacked on #35), both waiting for the Mac mini. T38 is merged (PR #34): on the demo call the
name-first question now gives a card with the question in it. Nothing else is planned. T40 (slow first
word after 20 minutes) is not worth the risk now: the video is 2 minutes and the live demo 4.

## 1. In-person session at the Mac mini (about 45 min, in this order)

Before: `git pull`, `./scripts/make_app.sh run`, wait for the red dot and two green dots in the HUD.
"Your name" in the "…" menu is Yusuf. If the build is new, launch it once beforehand (Whisper compiles
for minutes on the first launch). Write each result into WORKLOG.md as you go.

**A. Study mode with the lecture (12 min).** Open `demo/lecture/slides.html` full screen, press Start.

1. T02: with the browser in front, press ⌥Space: the ask field gets the cursor. Type "What is the new
   weight in the example?" on slide 3. Expect 1.6.
2. T01: the answer is read aloud, and what it says does not show up as a transcript line.
3. T07: the voice starts before the card is finished, sentences in order, none twice. ⌥S: the voice
   finishes the sentence it is in and does not start again (stopping mid-word needs a core change,
   see the work log, Sun 2:40 am). A new question cuts off the old speech the same way.
   T41: paste a question with Cmd+V. Type a question while a look-away card is still being written:
   it is answered when that card is done, not lost.
4. T02: ⌥C gives a catch-up card.
5. T25: press ⌥V and ask out loud "What should I do if the loss goes up?" while the lecture plays. The
   field shows your question, not the lecturer's words. Expect: divide the rate by ten. Then ask again
   by voice while a card is still being written: it is answered afterwards, not lost.
6. T06: slide 4, "Which curve diverges?" Expect red. Click the thumbnail under RECEIPTS: it enlarges
   inside the card and the HUD stays visible; click again to shrink; the arrow opens the file.
7. T05: look away for 10 s and back: a card. A 1 to 2 s glance: nothing. Pause: the eye icon goes away.
8. Slide 6: "When are office hours?" Expect Tuesday at 3, room 204 (said on slide 1, never shown).

**B. Call mode (8 min).** Switch to Call, allow the microphone, then `afplay demo/call/call.wav`.

9. T11: answer out loud in the 8 s gap after each question: your line shows as "You". T41: the
   call's own voices and the spoken card must NOT show up as "You" lines. If "You" never appears at
   all, the new microphone gate is too strict for this room: quit, and launch with
   `CLUELESS_MIC_GATE=0 ./scripts/make_app.sh run` (or use headphones), and write that down.
10. T12 and T38: both questions to Yusuf give a card, and "You were asked" holds the question itself.
    While a question is still being said the panel shows "Listening to the rest of the question…".
11. T20 and T33: "…" menu, Session notes: by speaker, with Maya, Sam and Priya; the title ends
    "3 speakers, 3 named"; the long card scrolls inside the panel and the HUD stays visible.

**C. Things going wrong (8 min).**

12. T16: `./scripts/servers.sh stop` in a terminal. An orange row appears, the HUD dots turn red, and
    the servers come back by themselves within about 30 s. Ask a question meanwhile: the card says the
    servers are still starting. Stop them again and use the Restart button.
13. T17: click "Stop sharing" in the macOS menu bar: capture stays stopped and the panel says so; play
    resumes it. Then let the display sleep and wake it: capture comes back by itself and the timeline
    gets a "Capture restarted" line.

Also, 1 min: click pause, then play twice quickly: the transcript is not doubled. "…" menu, "Your name:
Yusuf…" opens a dialog. `grep hotkey .run/app.log` shows four "registered" lines.

**D. Wi-Fi off again on the final build (10 min). Aziz ran it once Sat night and it worked; this run is
for the timings and for the default Hugging Face folder.**

14. Check `models/argmax/speakerkit-coreml` exists. Quit the app, `./scripts/servers.sh stop`.
15. `mv ~/Documents/huggingface ~/Documents/huggingface.off`, then turn Wi-Fi off.
16. Launch again. The HUD says "network off" in green. Repeat steps 1, 4, 7, 10 and 11.
17. `mv ~/Documents/huggingface.off ~/Documents/huggingface`. Record the result in BENCHMARKS.md and
    tag `m1`, `m2`, `m3` on `main`.

**E. Live soak, T18.** Leave the lecture looping for 20 minutes during the README work, with speech on
and the webcam on. Note the three memory numbers in the HUD at the start and the end.

## 2. Video, under 2 minutes (T23)

Record the Mac mini's screen with Wi-Fi off and the Wi-Fi icon visible in the menu bar. Judging order is
use of Bonsai and Argmax first, so say which model does what while it happens.

| Time | On screen | Say |
|---|---|---|
| 0:00 to 0:12 | The panel over the lecture; Wi-Fi off in the menu bar | "Cluely tells you what to say. Clueless tells you what you missed. Everything you see runs on this Mac, with Wi-Fi off." |
| 0:12 to 0:40 | Lecture playing. Look away for 8 s (show the camera, or the eye icon turning orange), look back: the card appears and is read aloud | "I looked away. Argmax WhisperKit transcribed what I missed, Bonsai 9B wrote the catch-up, Argmax TTSKit reads it. Every card lists its receipts." |
| 0:40 to 1:00 | ⌥V: "Which curve diverges?" then "When are office hours?" | "I can ask out loud. The first answer needs the chart, so the screenshot goes to Bonsai. The second was said minutes ago and never shown." |
| 1:00 to 1:35 | Call mode, the demo call from just before "Yusuf, can your team still hit Friday…": the "You were called on" card; then Session notes | "In a call, Bonsai 4B watches every line. When someone says my name, I get the question and a suggested reply. At the end, SpeakerKit and Bonsai give notes by speaker, with names nobody typed in." |
| 1:35 to 1:55 | Zoom on the HUD | "Two Bonsai models and three Argmax models, under 3 GB together, first word in about a second, network off." |

Record the call part and the study part as separate takes and cut them together. Keep the recording
indicator (red dot) in frame: the project does not hide from screen sharing.

## 3. Submission (T24), Discord #submissions, by 11:30 am

- Both names.
- "Clueless is a private copilot that watches your screen and listens to your calls and lectures
  entirely on your Mac, and catches you up the moment you lose the thread."
- https://github.com/acaptainb/clueless (public; checked Sun 1:50 am)
- The video.

Before posting: README status table updated from the in-person results (it still says Sat 8 pm), the
BENCHMARKS.md "Known issues" list is current, `main` passes `./scripts/check.sh main`.

## 4. Still unanswered by the organizers

- Is Apple's built-in OCR fine under the "LLMs must be Bonsai" rule? If not: the "…" menu has
  "Screenshot only", which uses no OCR.
- Can the Mac mini be brought to the finals? If not, the live demo needs a laptop with 16 GB or more;
  Yusuf's 8 GB MacBook cannot run it.
- Argmax Pro: a key arrived Sat night without the SDK download token, so M4 is skipped.
