// Headless benchmarks for the Clueless engine. No capture permissions needed.
//   clueless-bench chunk  <wav> <reference.txt>     compare live-audio chunking methods
//   clueless-bench screen <image>                    compare OCR text vs screenshot vs both
//   clueless-bench answer [port] [label]             question + catch-up test set on one model
//   clueless-bench watch  [port]                     watcher: code check alone vs code check + 2B
//   clueless-bench tts                               speech latency
import Foundation
import AVFoundation
import CluelessCore

func loadWav16k(_ path: String) throws -> [Float] { try AudioFile.load16k(path) }

func words(_ s: String) -> [String] {
    s.lowercased().replacingOccurrences(of: "[^a-z0-9' ]", with: " ", options: .regularExpression)
        .split(separator: " ").map(String.init)
}

/// Word error rate by edit distance.
func wer(_ hyp: String, _ ref: String) -> Double {
    let h = words(hyp), r = words(ref)
    guard !r.isEmpty else { return 0 }
    var prev = Array(0...h.count)
    for i in 1...r.count {
        var cur = [i] + Array(repeating: 0, count: h.count)
        if !h.isEmpty {
            for j in 1...h.count {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (r[i - 1] == h[j - 1] ? 0 : 1))
            }
        }
        prev = cur
    }
    return Double(prev[h.count]) / Double(r.count)
}

func pad(_ s: String, _ n: Int) -> String { s.count >= n ? s : s + String(repeating: " ", count: n - s.count) }
func f(_ d: Double, _ p: Int = 2) -> String { String(format: "%.\(p)f", d) }

// MARK: chunk

func benchChunk(_ wav: String, _ refPath: String) async throws {
    let samples = try loadWav16k(wav)
    let ref = try String(contentsOfFile: refPath, encoding: .utf8)
    let transcriber = try await Transcriber()
    print("WhisperKit load: \(f(transcriber.loadSeconds))s, audio: \(f(Double(samples.count) / 16000, 1))s\n")
    _ = try await transcriber.transcribe(Array(samples.prefix(16000 * 3)))   // warm up

    let methods: [ChunkMethod] = [
        .fixed(seconds: 3), .fixed(seconds: 5), .fixed(seconds: 10),
        .silence(minSeconds: 2, maxSeconds: 8), .silence(minSeconds: 3, maxSeconds: 12), .silence(minSeconds: 5, maxSeconds: 15),
    ]
    print(pad("method", 18), pad("WER", 7), pad("chunks", 7), pad("avg len", 8), pad("stt/chunk", 10), pad("worst lag", 10), "avg lag")
    for method in methods {
        var chunker = AudioChunker(method: method)
        var text: [String] = [], lens: [Double] = [], stt: [Double] = []
        let step = 1600   // 100 ms, like live capture buffers
        var i = 0
        func run(_ c: AudioChunker.Chunk) async throws {
            let t0 = Date()
            let out = try await transcriber.transcribe(c.samples)
            stt.append(Date().timeIntervalSince(t0)); lens.append(Double(c.samples.count) / 16000)
            if !out.isEmpty { text.append(out) }
        }
        while i < samples.count {
            let slice = Array(samples[i..<min(i + step, samples.count)])
            if let c = chunker.feed(slice) { try await run(c) }
            i += step
        }
        if let c = chunker.flush() { try await run(c) }
        // A word waits at most (chunk length + transcribe time) before it shows up; on average half the chunk.
        let lag = zip(lens, stt).map { $0 + $1 }
        let avgLag = zip(lens, stt).map { $0 / 2 + $1 }.reduce(0, +) / Double(max(lens.count, 1))
        print(pad(method.name, 18), pad(f(wer(text.joined(separator: " "), ref) * 100, 1) + "%", 7),
              pad("\(lens.count)", 7), pad(f(lens.reduce(0, +) / Double(max(lens.count, 1)), 1) + "s", 8),
              pad(f(stt.reduce(0, +) / Double(max(stt.count, 1))) + "s", 10),
              pad(f(lag.max() ?? 0, 1) + "s", 10), f(avgLag, 1) + "s")
    }
}

// MARK: screen

struct QA { let q: String; let expect: [String] }

func hit(_ answer: String, _ expect: [String]) -> Bool {
    let a = answer.lowercased()
    return expect.allSatisfy { alt in alt.split(separator: "|").contains { a.contains($0.lowercased()) } }
}

func benchScreen(_ imagePath: String, _ qaPath: String?) async throws {
    guard let image = ScreenText.load(URL(fileURLWithPath: imagePath)) else { fatalError("cannot read image") }
    let t0 = Date()
    let ocr = ScreenText.recognize(image)
    let ocrSeconds = Date().timeIntervalSince(t0)
    let jpeg = ScreenText.jpeg(image)!
    print("OCR: \(f(ocrSeconds))s, \(ocr.count) chars. JPEG: \(jpeg.count / 1024) KB\n--- OCR text ---\n\(ocr)\n---\n")

    var qas = [
        QA(q: "What is the learning rate in this example?", expect: ["0.01"]),
        QA(q: "What batch size is used?", expect: ["64"]),
        QA(q: "When is the homework due?", expect: ["thursday"]),
        QA(q: "What happens if the learning rate is too large?", expect: ["diverge"]),
        QA(q: "Write the update rule shown on the slide.", expect: ["w", "η|eta|learning rate", "∇|gradient|nabla"]),
        QA(q: "Which course and professor is this?", expect: ["4780", "weinberger"]),
    ]
    if let qaPath, let data = FileManager.default.contents(atPath: qaPath),
       let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
        qas = arr.map { QA(q: $0["q"] as! String, expect: $0["expect"] as! [String]) }
    }
    let answerer = Answerer()
    print(pad("method", 8), pad("correct", 9), pad("avg s", 7), pad("prompt tok", 11), "misses")
    for method in [ScreenMethod.ocr, .image, .both] {
        var ok = 0, secs = 0.0, ptok = 0; var misses: [String] = []
        for qa in qas {
            let card = try await answerer.answer(.question, lines: [],
                                                 screenText: method == .image ? "" : ocr,
                                                 image: method == .ocr ? nil : jpeg, question: qa.q)
            secs += card.stats.seconds; ptok = max(ptok, card.stats.promptTokens)
            if hit(card.answer, qa.expect) { ok += 1 } else { misses.append("\(qa.q) -> \(card.answer.prefix(90))") }
        }
        print(pad(method.rawValue, 8), pad("\(ok)/\(qas.count)", 9), pad(f(secs / Double(qas.count)), 7), pad("\(ptok)", 11),
              misses.isEmpty ? "-" : "")
        for m in misses { print("          x \(m)") }
    }
}

// MARK: answer

func sampleCall() -> Timeline {
    let tl = Timeline()
    let base = Date().addingTimeInterval(-120)
    let script: [(TimelineLine.Source, String?, String)] = [
        (.them, "Maya", "Okay, let's start. First item is the launch checklist for the mobile release."),
        (.them, "Sam", "The API changes are merged, but the push notification service is still failing in staging."),
        (.me, nil, "I can look at the push service after this call."),
        (.them, "Maya", "Great. Priya, where are we on the App Store screenshots?"),
        (.them, "Priya", "Screenshots are done. I need the final copy from marketing by Wednesday."),
        (.them, "Sam", "One more thing, the database migration takes about forty minutes, so we need a maintenance window."),
        (.them, "Maya", "Let's do the migration Thursday night at ten p.m. Sam owns it."),
        (.them, "Priya", "Budget wise, we have twelve thousand dollars left for the launch ads."),
        (.them, "Maya", "Good. We decided to cut the tablet layout from this release and ship it in January."),
        (.them, "Sam", "Agreed. That saves us about a week of QA."),
        (.them, "Maya", "Yusuf, can your team still hit Friday for the release candidate, given the push notification bug?"),
    ]
    for (i, s) in script.enumerated() {
        tl.append(s.0, s.2, speaker: s.1, at: base.addingTimeInterval(Double(i) * 9))
    }
    return tl
}

func benchAnswer(port: Int, label: String) async throws {
    let answerer = Answerer(client: BonsaiClient(port: port))
    let lines = sampleCall().all
    let qas: [(String, [String], [Int])] = [   // question, expected keywords, acceptable source lines
        ("When is the database migration happening?", ["thursday", "ten|10"], [7]),
        ("Who owns the migration?", ["sam"], [7]),
        ("How much ad budget is left?", ["12,000|12000|twelve thousand|12k"], [8]),
        ("What was cut from this release?", ["tablet"], [9]),
        ("What does Priya need and by when?", ["copy", "wednesday"], [5]),
        ("What is failing in staging?", ["push"], [2]),
        ("How long does the migration take?", ["forty|40"], [6]),
        ("When will the tablet layout ship?", ["january"], [9]),
        ("What did I say I would do?", ["push"], [3]),
        ("What is the CEO's favorite color?", ["not|no |n't|unknown|doesn"], []),
    ]
    var ok = 0, srcOK = 0, secs = 0.0, tps = 0.0, parsed = 0; var misses: [String] = []
    for (q, expect, src) in qas {
        let card = try await answerer.answer(.question, lines: lines, screenText: "", question: q, userName: "Yusuf")
        secs += card.stats.seconds; tps += card.stats.tokensPerSecond
        if JSONRepair.object(card.raw) != nil { parsed += 1 }
        if hit(card.answer, expect) { ok += 1 } else { misses.append("\(q) -> \(card.answer.prefix(100))") }
        if src.isEmpty ? true : card.sources.contains(where: src.contains) { srcOK += 1 }
        else { misses.append("sources for '\(q)': got \(card.sources), want \(src)") }
    }
    print("== \(label) (port \(port)) questions: correct \(ok)/\(qas.count), receipts \(srcOK)/\(qas.count), valid JSON \(parsed)/\(qas.count), avg \(f(secs / Double(qas.count)))s, \(f(tps / Double(qas.count), 0)) tok/s")
    for m in misses { print("   x \(m)") }

    // Catch-up, three runs: must name the Friday question, mention something missed, cite line 11.
    var cu = 0, cuSecs = 0.0
    for run in 1...3 {
        let card = try await answerer.answer(.catchUp, lines: lines, screenText: "", userName: "Yusuf")
        cuSecs += card.stats.seconds
        let good = hit(card.asked, ["friday"]) && !card.missed.isEmpty && !card.reply.isEmpty && card.sources.contains(11)
        if good { cu += 1 }
        if run == 1 || !good {
            print("   catch-up #\(run) \(good ? "ok" : "MISS") \(f(card.stats.seconds))s\n     asked:  \(card.asked)\n     missed: \(card.missed)\n     reply:  \(card.reply)\n     sources: \(card.sources)")
        }
    }
    print("== \(label) catch-up: \(cu)/3 good, avg \(f(cuSecs / 3))s")

    let notes = try await answerer.answer(.notes, lines: lines, screenText: "", userName: "Yusuf")
    print("== \(label) notes (\(f(notes.stats.seconds))s, sources \(notes.sources)):\n\(notes.answer)\n")
}

// MARK: watch

func benchWatch(port: Int) async throws {
    let watcher = Watcher(client: BonsaiClient(port: port))
    let context: [(String, String)] = [("Maya", "The design review went fine."), ("Sam", "We still need the API changes merged.")]
    let cases: [(String, String, Bool)] = [   // speaker, newest line, should it need the user (Yusuf)?
        ("Maya", "Yusuf, can your team still hit Friday?", true),
        ("Sam", "What do you think, Yusuf?", true),
        ("Maya", "Yusuf, are you still there?", true),
        ("Maya", "Does anyone have concerns about the timeline?", true),
        ("Sam", "Can everyone confirm they've read the doc?", true),
        ("Maya", "Priya, where are we on the screenshots?", false),
        ("Sam", "Sam here, I'll take the migration.", false),
        ("Maya", "I talked to Yusuf yesterday about the budget.", false),
        ("Sam", "Why does this keep happening? Anyway, moving on.", false),
        ("Maya", "The deadline is Friday.", false),
        ("Priya", "Thanks, Priya here, I sent the copy to marketing.", false),
        ("Maya", "Priya, did marketing reply?", false),
        ("Sam", "So what's the takeaway? The takeaway is that caching works.", false),
        ("Maya", "Yusuf already fixed that last week.", false),
        ("Sam", "Yusuf, could you share your screen?", true),
        ("Maya", "Okay, any questions before we wrap up?", true),
    ]
    var codeOK = 0, modelOK = 0, calls = 0, secs = 0.0; var misses: [String] = []
    for (speaker, text, want) in cases {
        let tl = Timeline()
        for c in context { tl.append(.them, c.1, speaker: c.0) }
        let newest = tl.append(.them, text, speaker: speaker)
        if Watcher.precheck(newest, userName: "Yusuf") == want { codeOK += 1 }
        let d = await watcher.watch(tl.all, userName: "Yusuf")
        if d.usedModel { calls += 1; secs += d.seconds }
        if d.needsUser == want { modelOK += 1 } else { misses.append("\(text) -> got \(d.needsUser) (\(d.reason)), want \(want)") }
    }
    print("code check alone:   \(codeOK)/\(cases.count) correct")
    print("code check + model: \(modelOK)/\(cases.count) correct, model called on \(calls)/\(cases.count) lines, avg \(f(secs / Double(max(calls, 1))))s per call")
    for m in misses { print("   x \(m)") }
}

// MARK: main

final class Box: @unchecked Sendable { var value: Double? }

let args = Array(CommandLine.arguments.dropFirst())
do {
    switch args.first {
    case "chunk": try await benchChunk(args[1], args[2])
    case "screen": try await benchScreen(args[1], args.count > 2 ? args[2] : nil)
    case "screencost": try await benchScreenCost(args[1], args.count > 2 ? args[2] : nil, args.count > 3 ? args[3] : nil)
    case "answer": try await benchAnswer(port: args.count > 1 ? Int(args[1])! : 8080, label: args.count > 2 ? args[2] : "9B")
    case "stream":
        // How soon does the user see something when the card streams?
        let lines = sampleCall().all
        for run in 1...3 {
            let t0 = Date()
            let firstText = Box(), askedDone = Box()
            let card = try await Answerer().answer(.catchUp, lines: lines, screenText: "", userName: "Yusuf") { partial in
                if firstText.value == nil, !partial.asked.isEmpty { firstText.value = Date().timeIntervalSince(t0) }
                if askedDone.value == nil, !partial.missed.isEmpty { askedDone.value = Date().timeIntervalSince(t0) }
            }
            print("run \(run): first words on screen \(f(firstText.value ?? -1))s, 'asked' complete \(f(askedDone.value ?? -1))s, whole card \(f(card.stats.seconds))s | asked: \(card.asked.prefix(60)) | sources \(card.sources)")
        }
    case "watch": try await benchWatch(port: args.count > 1 ? Int(args[1])! : 8082)
    case "tts":
        let speaker = try await Speaker()
        print("TTSKit load: \(f(speaker.loadSeconds))s")
        for text in ["You were asked whether your team can still hit Friday.",
                     "The learning rate is zero point zero one. Homework three is due Thursday at eleven fifty nine p.m."] {
            print("spoke \(text.count) chars in \(f(try await speaker.sayAndWait(text)))s")
        }
    default:
        print("usage: clueless-bench chunk <wav> <ref.txt> | screen <image> [qa.json] | answer [port] [label] | watch [port] | tts")
    }
} catch {
    print("error: \(error.localizedDescription)")
    exit(1)
}
