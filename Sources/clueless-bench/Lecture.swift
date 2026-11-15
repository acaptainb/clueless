// clueless-bench lecture <wav> <questions.json> [port]
// Plays a recording into a timeline the way the app hears it (pause-based chunks, WhisperKit), then asks
// the questions whose answer is only in the audio ("from": "audio" in demo/lecture/questions.json).
// This is the no-person version of "ask at the end of the lecture" (T04) and the real-audio half of T10.
import Foundation
import CluelessCore

struct LectureQuestion: Decodable {
    let q: String
    let expect: [String]
    let from: String?
}

func benchLecture(_ wav: String, _ questionsPath: String, port: Int) async throws {
    let questions: [LectureQuestion] = loadCases("", path: questionsPath)
    let spoken = questions.filter { $0.from == nil || $0.from == "audio" }
    let samples = try AudioFile.load16k(wav)
    let transcriber = try await Transcriber()
    let tl = Timeline()
    var chunker = AudioChunker(method: .silence(minSeconds: 2, maxSeconds: 8))
    // Feed the file as if it were live and had just ended: 100 ms buffers, stamped with their arrival time.
    let start = Date().addingTimeInterval(-Double(samples.count) / 16000)
    var i = 0
    while i < samples.count {
        let slice = Array(samples[i..<min(i + 1600, samples.count)])
        if let chunk = chunker.feed(slice, at: start.addingTimeInterval(Double(i + slice.count) / 16000)) {
            let text = try await transcriber.transcribe(chunk.samples)
            if text.count > 1 { tl.append(.them, text, at: chunk.startedAt) }
        }
        i += 1600
    }
    if let chunk = chunker.flush() {
        let text = try await transcriber.transcribe(chunk.samples)
        if text.count > 1 { tl.append(.them, text, at: chunk.startedAt) }
    }
    // The window the app uses for a question: the last 5 minutes, at most 120 lines.
    let lines = tl.recent(seconds: 300, maxLines: 120, step: 60)
    print("prompts: \(Prompts.summary)")
    print("\(tl.all.count) lines from \(f(Double(samples.count) / 16000, 1))s of audio; \(lines.count) sent with each question")
    let answerer = Answerer(client: BonsaiClient(port: port))
    var ok = 0, seconds = 0.0, first = 0.0
    for question in spoken {
        let card = try await answerer.answer(.question, lines: lines, screenText: "", question: question.q)
        seconds += card.stats.seconds; first += card.stats.firstTokenSeconds
        let good = hit(card.answer, question.expect)
        if good { ok += 1 }
        print("\(good ? "ok  " : "MISS") \(f(card.stats.seconds))s  \(question.q)\n       -> \(card.answer.prefix(150))  \(card.sources)")
    }
    let n = Double(max(spoken.count, 1))
    print("== lecture: \(ok)/\(spoken.count) audio questions right, avg \(f(seconds / n))s")
}
