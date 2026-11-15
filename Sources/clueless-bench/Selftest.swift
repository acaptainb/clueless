// clueless-bench selftest
//
// Logic checks that need no servers, no models and no permissions. They cover the parts of the engine that
// were written without a compiler: the timeline window (T09), the forced audio cut (T19), the session
// recording and speaker assignment (T13), name validation (T14) and the prompt files (T26).
// Prints one line per check and "== selftest: N/M passed"; exits 1 if anything failed.
import Foundation
import CluelessCore

private final class Tally: @unchecked Sendable {
    var passed = 0
    var total = 0
    func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        total += 1
        if ok { passed += 1 }
        print((ok ? "ok    " : "FAIL  ") + name + (ok || detail.isEmpty ? "" : "  (" + detail + ")"))
    }
}

private func tone(seconds: Double, amplitude: Float) -> [Float] {
    let n = Int(seconds * 16000)
    var out = [Float](repeating: 0, count: n)
    for i in 0..<n { out[i] = amplitude * Float(sin(2.0 * Double.pi * 220.0 * Double(i) / 16000.0)) }
    return out
}

func runSelftest() {
    let t = Tally()
    // A fixed moment that is a whole number of minutes, so window rounding is predictable.
    let base = Date(timeIntervalSince1970: 1_800_000_000)

    // T09: the timeline window starts at the same line for requests a few seconds apart.
    let tl = Timeline()
    for i in 0..<40 { tl.append(.them, "line \(i + 1)", speaker: "Maya", at: base.addingTimeInterval(Double(i) * 5)) }
    let first = tl.recent(seconds: 100, maxLines: 60, step: 60, now: base.addingTimeInterval(205))
    let second = tl.recent(seconds: 100, maxLines: 60, step: 60, now: base.addingTimeInterval(212))
    t.check("recent: same first line 7 s later", first.first?.id == 13 && second.first?.id == 13,
            "first ids \(first.first?.id ?? -1) and \(second.first?.id ?? -1), expected 13")
    t.check("recent: newest line included", first.last?.id == 40 && second.last?.id == 40)
    let exact = tl.recent(seconds: 100, maxLines: 60, now: base.addingTimeInterval(205))
    t.check("recent: the default is the exact window", exact.first?.id == 22, "first id \(exact.first?.id ?? -1), expected 22")
    let capped = tl.recent(seconds: 100, maxLines: 20, step: 60, now: base.addingTimeInterval(205))
    t.check("recent: cap trims to a multiple of 10", capped.first?.id == 30 && capped.count == 11,
            "first id \(capped.first?.id ?? -1), count \(capped.count), expected 30 and 11")

    // T19: 8 s of speech with a 100 ms gap at 7.0 s. The forced cut should land in the gap.
    var signal = tone(seconds: 7.0, amplitude: 0.1)
    signal += [Float](repeating: 0, count: 1600)
    signal += tone(seconds: 2.9, amplitude: 0.1)
    for searchSeconds in [1.5, 0.0] {
        var chunker = AudioChunker(method: .silence(minSeconds: 2, maxSeconds: 8))
        chunker.forcedCutSearchSeconds = searchSeconds
        var firstChunk: AudioChunker.Chunk? = nil
        var i = 0
        while i < signal.count, firstChunk == nil {
            let slice = Array(signal[i..<min(i + 1600, signal.count)])
            firstChunk = chunker.feed(slice, at: base.addingTimeInterval(Double(i + slice.count) / 16000))
            i += 1600
        }
        let length = Double(firstChunk?.samples.count ?? 0) / 16000
        if searchSeconds > 0 {
            t.check("chunker: forced cut lands in the gap between words", length >= 7.0 && length <= 7.1,
                    "chunk is \(length) s, expected 7.0 to 7.1")
            let rest = chunker.flush()
            let restLength = Double(rest?.samples.count ?? 0) / 16000
            t.check("chunker: audio after the cut is kept for the next chunk", restLength > 0.85 && restLength < 1.05,
                    "carried \(restLength) s, expected about 0.95")
        } else {
            t.check("chunker: search 0 cuts at the end as before", length == 8.0, "chunk is \(length) s, expected 8.0")
        }
    }

    // T13: the recording maps a clock time to a position in the audio, across a silent gap.
    let audio = SessionAudio()
    let buffer = [Float](repeating: 0.05, count: 1600)
    for k in 0..<20 { audio.append(buffer, at: base.addingTimeInterval(Double(k) * 0.1)) }
    for k in 0..<10 { audio.append(buffer, at: base.addingTimeInterval(12 + Double(k) * 0.1)) }
    t.check("session audio: length", abs(audio.seconds - 3.0) < 0.001, "\(audio.seconds) s, expected 3.0")
    let early = audio.offset(of: base.addingTimeInterval(1.0)) ?? -1
    t.check("session audio: time to offset", abs(early - 1.0) < 0.01, "\(early), expected 1.0")
    let late = audio.offset(of: base.addingTimeInterval(12.5)) ?? -1
    t.check("session audio: offset after a silent gap", abs(late - 2.5) < 0.01, "\(late), expected 2.5")
    t.check("session audio: before the recording", audio.offset(of: base.addingTimeInterval(-5)) == nil)
    t.check("session audio: samples round-trip", audio.samples().count == 48000 && abs((audio.samples().first ?? 0) - 0.05) < 0.001)

    // T13: each "them" line gets the speaker who talks most during it.
    let call = Timeline()
    call.append(.them, "First point.", at: base)
    call.append(.them, "Second point.", at: base.addingTimeInterval(4))
    call.append(.me, "My reply.", at: base.addingTimeInterval(6))
    call.append(.them, "Third point.", at: base.addingTimeInterval(8))
    let turns = [
        SpeakerTurn(speaker: 7, start: 0, end: 3.5),
        SpeakerTurn(speaker: 2, start: 3.8, end: 7.5),
        SpeakerTurn(speaker: 7, start: 7.9, end: 12),
    ]
    let labelled = Speakers.assign(call.all, turns: turns, offset: { $0.timeIntervalSince(base) })
    let labels = labelled.map { $0.speaker ?? "-" }
    t.check("speakers: labels by who talks most", labels == ["Speaker 1", "Speaker 2", "-", "Speaker 1"], "\(labels)")
    let renamed = Speakers.rename(labelled, names: ["Speaker 2": "Priya"]).map { $0.speaker ?? "-" }
    t.check("speakers: rename", renamed == ["Speaker 1", "Priya", "-", "Speaker 1"], "\(renamed)")

    // T14: only names that can be trusted survive.
    let answer: [String: Any] = ["Speaker 1": "Maya", "Speaker 2": "Yusuf", "Speaker 3": "Zed", "Speaker 4": "maya", "Speaker 5": ""]
    let names = NameResolver.validate(answer, labels: ["Speaker 1", "Speaker 2", "Speaker 3", "Speaker 4", "Speaker 5"],
                                      transcript: "Thanks, Maya. Yusuf, are you there?", userName: "Yusuf")
    t.check("names: drops the user, unsaid names and duplicates", names == ["Speaker 1": "Maya"], "\(names)")

    // T35: turns of one speaker are joined across short pauses; very short ones are dropped.
    let joined = Speakers.utterances([
        SpeakerTurn(speaker: 1, start: 0, end: 2), SpeakerTurn(speaker: 1, start: 2.6, end: 5),
        SpeakerTurn(speaker: 2, start: 5.2, end: 5.4), SpeakerTurn(speaker: 1, start: 8, end: 9),
    ])
    t.check("speakers: utterances joined and filtered",
            joined == [SpeakerTurn(speaker: 1, start: 0, end: 5), SpeakerTurn(speaker: 1, start: 8, end: 9)], "\(joined)")

    // T35: names from who is addressed and who answers, no model.
    let talk = Timeline()
    let said: [(String, String)] = [
        ("Speaker 1", "Okay, let's get started. Sam, can you start with the backend?"),
        ("Speaker 2", "Sure. The export job is fixed."),
        ("Speaker 1", "Thanks, Sam. Priya, how is the onboarding flow?"),
        ("Speaker 3", "The design is final. Yusuf, can you write the copy?"),
        ("Speaker 4", "Quick note from support: ticket volume doubled on Thursday, honestly."),
        ("Speaker 2", "That matches what I see in the logs, Maya."),
        ("Speaker 1", "Okay, then we need to look at that email."),
        ("Speaker 5", "Got it, Maya."),
    ]
    for (i, line) in said.enumerated() { talk.append(.them, line.1, speaker: line.0, at: base.addingTimeInterval(Double(i) * 5)) }
    let clues = NameClues.resolve(talk.all, userName: "Yusuf")
    t.check("names: from address and answer", clues == ["Speaker 1": "Maya", "Speaker 2": "Sam", "Speaker 3": "Priya"], "\(clues)")
    let own = NameClues.addressedBy(talk.all, userName: "Yusuf")
    t.check("names: nobody is given a name they use for someone else",
            own["Speaker 2"] == ["maya"] && own["Speaker 1"] == ["sam", "priya"], "\(own)")

    // T43: call notes keep what the user said early in the call, not only their lines in the capped list.
    let noteRebuilt = [
        TimelineLine(id: 10_001, t: base, source: .them, speaker: "Speaker 1", text: "Can you own the launch checklist?"),
        TimelineLine(id: 10_002, t: base.addingTimeInterval(20), source: .them, speaker: "Speaker 2", text: "Next topic."),
    ]
    let noteEarly = TimelineLine(id: 3, t: base.addingTimeInterval(5), source: .me, text: "Yes, I will own it by Friday.")
    let noteLate = TimelineLine(id: 250, t: base.addingTimeInterval(30), source: .me, text: "Sounds good.")
    let noteStale = TimelineLine(id: 240, t: base.addingTimeInterval(25), source: .them, text: "A live line the rebuilt transcript replaces.")
    let noteFull = SessionNotes.merge(rebuilt: noteRebuilt, lines: [noteStale, noteLate], ownLines: [noteEarly, noteLate]).map(\.id)
    t.check("notes: the user's early lines are kept", noteFull == [10_001, 3, 10_002, 250], "\(noteFull)")
    let noteShort = SessionNotes.merge(rebuilt: noteRebuilt, lines: [noteStale, noteLate], ownLines: nil).map(\.id)
    t.check("notes: without them, as before", noteShort == [10_001, 10_002, 250], "\(noteShort)")

    // T26: every prompt file is found and matches the copy built into the code.
    for line in Prompts.report() {
        t.check("prompt " + line, line.hasSuffix("same as built-in"))
    }

    print("== selftest: \(t.passed)/\(t.total) passed")
    if t.passed != t.total { exit(1) }
}
