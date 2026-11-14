#!/usr/bin/env python3
"""Build the demo audio on the Mac mini from the scripts in demo/.

    python3 scripts/make_demo_assets.py [--user Yusuf] [--rate 165]

Uses only macOS `say` and `afconvert` plus the Python standard library. Nothing is downloaded and no
language model is involved (`say` is the system speech synthesizer).

Writes (all ignored by git):
    demo/call/call.wav              the three-speaker call, with silent gaps where the user is asked something
    demo/call/call_timeline.json    who speaks when: ground truth for speaker labels
    demo/lecture/audio/slideN.wav   narration for each slide, played by demo/lecture/slides.html
    demo/lecture/lecture.wav        the whole narration in one file (for CLUELESS_AUDIO_FILE and the chunk bench)
    demo/lecture/lecture_ref.txt    the narration text (reference for word error rate)
"""
import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
import wave

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEMO = os.path.join(ROOT, "demo")
RATE = 22050          # samples per second, 16-bit mono
LINE_GAP = 0.35       # silence between two spoken lines of the call
SLIDE_GAP = 1.0       # silence between slides in lecture.wav

# Preferred system voices per speaker, best first. Whatever is installed is used; speakers always differ.
VOICES = {
    "Maya": ["Samantha", "Allison", "Ava", "Susan", "Victoria"],
    "Sam": ["Daniel", "Alex", "Tom", "Oliver", "Fred"],
    "Priya": ["Karen", "Moira", "Tessa", "Veena", "Fiona", "Kathy"],
    "Lecturer": ["Daniel", "Alex", "Tom", "Samantha"],
}


def run(cmd):
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        sys.exit("command failed: %s\n%s" % (" ".join(cmd), result.stderr.strip()))
    return result.stdout


def installed_english_voices():
    """Names of installed English voices, from `say -v '?'` ("Samantha    en_US    # Hello...")."""
    names = []
    for line in run(["say", "-v", "?"]).splitlines():
        m = re.match(r"^(.*?)\s{2,}(en[_-][A-Za-z]+)\s", line)
        if m:
            names.append(m.group(1).strip())
    return names


def pick_voices(speakers, available):
    chosen, used = {}, set()
    for speaker in speakers:
        options = [v for v in VOICES.get(speaker, []) if v in available and v not in used]
        options += [v for v in available if v not in used]
        if not options:
            sys.exit("not enough English voices installed for %d speakers (System Settings > Accessibility > "
                     "Spoken Content > System voice > Manage Voices)" % len(speakers))
        chosen[speaker] = options[0]
        used.add(options[0])
    return chosen


def speak(text, voice, words_per_minute, tmp):
    """Synthesize one line and return its raw 16-bit mono samples at RATE."""
    aiff, wav = os.path.join(tmp, "line.aiff"), os.path.join(tmp, "line.wav")
    run(["say", "-v", voice, "-r", str(words_per_minute), "-o", aiff, text])
    run(["afconvert", "-f", "WAVE", "-d", "LEI16@%d" % RATE, "-c", "1", aiff, wav])
    with wave.open(wav, "rb") as w:
        return w.readframes(w.getnframes())


def silence(seconds):
    return b"\x00\x00" * int(RATE * seconds)


def seconds_of(frames):
    return len(frames) / 2.0 / RATE


def write_wav(path, frames):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(frames)
    print("  %-34s %5.1f s" % (os.path.relpath(path, ROOT), seconds_of(frames)))


def build_call(user, words_per_minute, available, tmp):
    items = []   # ("say", speaker, text) or ("pause", seconds)
    with open(os.path.join(DEMO, "call", "script.txt"), encoding="utf-8") as f:
        for raw in f:
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            pause = re.match(r"^\[pause\s+([0-9.]+)\]$", line)
            if pause:
                items.append(("pause", float(pause.group(1))))
                continue
            speaker, _, text = line.partition(":")
            if not text.strip():
                sys.exit("cannot read this line of demo/call/script.txt: " + line)
            items.append(("say", speaker.strip(), text.strip().replace("{USER}", user)))

    speakers = []
    for item in items:
        if item[0] == "say" and item[1] not in speakers:
            speakers.append(item[1])
    voices = pick_voices(speakers, available)
    print("call voices: " + ", ".join("%s = %s" % (s, voices[s]) for s in speakers))

    frames, timeline = b"", []
    for item in items:
        if item[0] == "pause":
            frames += silence(item[1])
            continue
        _, speaker, text = item
        audio = speak(text, voices[speaker], words_per_minute, tmp)
        start = seconds_of(frames)
        frames += audio + silence(LINE_GAP)
        timeline.append({"start": round(start, 2), "end": round(start + seconds_of(audio), 2),
                         "speaker": speaker, "text": text})
    write_wav(os.path.join(DEMO, "call", "call.wav"), frames)
    with open(os.path.join(DEMO, "call", "call_timeline.json"), "w", encoding="utf-8") as f:
        json.dump({"user": user, "voices": voices, "lines": timeline}, f, indent=2)


def build_lecture(words_per_minute, available, tmp):
    slides, current = [], None
    with open(os.path.join(DEMO, "lecture", "narration.txt"), encoding="utf-8") as f:
        for raw in f:
            line = raw.strip()
            if re.match(r"^##\s*slide\s+\d+", line, re.IGNORECASE):
                current = []
                slides.append(current)
            elif line and not line.startswith("#") and current is not None:
                current.append(line)
    if not slides:
        sys.exit("no '## slide N' sections found in demo/lecture/narration.txt")

    voice = pick_voices(["Lecturer"], available)["Lecturer"]
    print("lecture voice: " + voice)
    whole = b""
    for n, lines in enumerate(slides, start=1):
        audio = speak(" ".join(lines), voice, words_per_minute, tmp)
        write_wav(os.path.join(DEMO, "lecture", "audio", "slide%d.wav" % n), audio)
        whole += audio + silence(SLIDE_GAP)
    write_wav(os.path.join(DEMO, "lecture", "lecture.wav"), whole)
    with open(os.path.join(DEMO, "lecture", "lecture_ref.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(" ".join(lines) for lines in slides) + "\n")


def main():
    parser = argparse.ArgumentParser(description="Build the demo audio from demo/ with the system voices.")
    parser.add_argument("--user", default="Yusuf", help="name the call addresses; must match 'Your name' in the app")
    parser.add_argument("--rate", type=int, default=165, help="speaking rate in words per minute")
    args = parser.parse_args()
    if sys.platform != "darwin":
        sys.exit("this needs macOS (`say` and `afconvert`); run it on the Mac mini")

    available = installed_english_voices()
    with tempfile.TemporaryDirectory() as tmp:
        build_call(args.user, args.rate, available, tmp)
        build_lecture(args.rate, available, tmp)
    print("done. Lecture: open demo/lecture/slides.html   Call: afplay demo/call/call.wav")


if __name__ == "__main__":
    main()
