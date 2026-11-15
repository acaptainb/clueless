// Call-mode benchmarks (T13 to T15).
//   clueless-bench names [port]            can Bonsai work out who "Speaker 1", "Speaker 2" are? (bench/names.json)
//   clueless-bench speakers <wav> [count]  SpeakerKit on a recorded call: how many speakers, who talks when
//   clueless-bench notes [port] [wav]      the whole end-of-session path: labels, names, notes
import Foundation
import CluelessCore

struct NamesData: Decodable {
    let user: String
    let lines: [CallData.Line]
    /// Speakers whose name is never given away in the call. The right answer for them is "".
    let unknown: [String]
}

/// bench/names.json as a timeline, with every real name on a "them" line replaced by "Speaker N"
/// (numbered in order of appearance), the way the lines look after SpeakerKit and before name resolution.
private func anonymised(_ data: NamesData) -> (timeline: Timeline, labelOf: [String: String]) {
    let tl = Timeline()
    var labelOf: [String: String] = [:]
    let base = Date().addingTimeInterval(-200)
    for (i, line) in data.lines.enumerated() {
        let source = TimelineLine.Source(rawValue: line.source) ?? .them
        var speaker: String? = nil
        if source == .them, let real = line.speaker {
            if labelOf[real] == nil { labelOf[real] = "Speaker \(labelOf.count + 1)" }
            speaker = labelOf[real]
        }
        tl.append(source, line.text, speaker: speaker, at: base.addingTimeInterval(Double(i) * 8))
    }
    return (tl, labelOf)
}

func benchNames(port: Int) async throws {
    let data: NamesData = loadCases("names")
    let prepared = anonymised(data)
    let lines = prepared.timeline.all
    let labelOf = prepared.labelOf
    let resolver = NameResolver(client: BonsaiClient(port: port))
    print("prompts: \(Prompts.summary)")
    var total = 0
    for run in 1...3 {
        let t0 = Date()
        let names = await resolver.resolve(lines, userName: data.user)
        var good = 0
        var misses: [String] = []
        for real in labelOf.keys.sorted() {
            let label = labelOf[real] ?? ""
            let got = names[label] ?? ""
            let want = data.unknown.contains(real) ? "" : real
            if got.caseInsensitiveCompare(want) == .orderedSame { good += 1 }
            else { misses.append("\(label): got '\(got)', want '\(want)'") }
        }
        total += good
        print("run \(run): \(good)/\(labelOf.count) speakers right, \(f(Date().timeIntervalSince(t0)))s")
        for m in misses { print("   x \(m)") }
    }
    print("== names: \(total)/\(labelOf.count * 3) over 3 runs")
}

func benchSpeakers(_ wav: String, _ count: Int?, _ threshold: Float? = nil) async throws {
    let samples = try AudioFile.load16k(wav)
    print("SpeakerKit models: \(SpeakerLabeler.modelFolder ?? "NOT FOUND on disk (see README setup, step 3)")")
    let labeler = try await SpeakerLabeler()
    print("SpeakerKit load: \(f(labeler.loadSeconds))s, audio: \(f(Double(samples.count) / 16000, 1))s")
    let t0 = Date()
    let turns = try await labeler.turns(samples, speakers: count, threshold: threshold)
    let seconds = Date().timeIntervalSince(t0)
    var talk: [Int: Double] = [:]
    for turn in turns { talk[turn.speaker, default: 0] += turn.end - turn.start }
    print("== speakers: \(talk.count) found in \(turns.count) turns, \(f(seconds))s to label")
    for id in talk.keys.sorted() { print("   speaker \(id): \(f(talk[id] ?? 0, 1))s of speech") }
    for turn in turns.prefix(15) { print("   \(f(turn.start, 1))s to \(f(turn.end, 1))s  speaker \(turn.speaker)") }
}

/// The path the app takes for "Session notes" in call mode. Without a wav the speakers are already labelled
/// "Speaker N" (as in bench/names.json); with one, the audio is transcribed and labelled first.
func benchNotes(port: Int, wav: String?) async throws {
    let answerer = Answerer(client: BonsaiClient(port: port))
    var lines: [TimelineLine] = []
    var audio: SessionAudio? = nil
    var labeler: SpeakerLabeler? = nil
    var whisper: Transcriber? = nil
    var user = ""
    if let wav {
        let samples = try AudioFile.load16k(wav)
        let transcriber = try await Transcriber()
        whisper = transcriber
        user = ProcessInfo.processInfo.environment["CLUELESS_USER"] ?? "Yusuf"
        let recording = SessionAudio()
        let tl = Timeline()
        var chunker = AudioChunker(method: .silence(minSeconds: 2, maxSeconds: 8))
        // Feed the file as if it were live: 100 ms buffers, each stamped with the time it would have arrived.
        let start = Date().addingTimeInterval(-Double(samples.count) / 16000)
        let step = 1600
        var i = 0
        while i < samples.count {
            let slice = Array(samples[i..<min(i + step, samples.count)])
            let now = start.addingTimeInterval(Double(i + slice.count) / 16000)
            recording.append(slice, at: now)
            if let chunk = chunker.feed(slice, at: now) {
                let text = try await transcriber.transcribe(chunk.samples)
                if text.count > 1 { tl.append(.them, text, at: chunk.startedAt) }
            }
            i += step
        }
        if let chunk = chunker.flush() {
            let text = try await transcriber.transcribe(chunk.samples)
            if text.count > 1 { tl.append(.them, text, at: chunk.startedAt) }
        }
        lines = tl.all
        audio = recording
        labeler = try await SpeakerLabeler()
        print("transcribed \(lines.count) lines from \(f(recording.seconds, 1))s of audio")
    } else {
        let data: NamesData = loadCases("names")
        lines = anonymised(data).timeline.all
        user = data.user
    }
    let result = try await SessionNotes.make(lines: lines, audio: audio, labeler: labeler, transcriber: whisper, answerer: answerer, userName: user)
    print("== notes: \(result.speakerCount) speakers heard, names \(result.names), prepare \(f(result.prepareSeconds))s, "
          + "notes \(f(result.card.stats.seconds))s, sources \(result.card.sources)")
    for line in result.lines.prefix(40) { print("   \(line.rendered)") }
    print(result.card.answer)
}
