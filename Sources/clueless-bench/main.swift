// Headless benchmarks for the Clueless engine. No capture permissions needed.
//   clueless-bench chunk  <wav> <reference.txt>     compare live-audio chunking methods
//   clueless-bench screen <image>                    compare OCR text vs screenshot vs both
//   clueless-bench answer [port] [label] [cases]     question + catch-up test set on one model
//                                                    (cases: questions = the 10 in the merge gate, questions_more = 10 harder ones)
//   clueless-bench watch  [port]                     watcher: code check alone vs code check + 2B
//   clueless-bench cache  [port]                     prompt cache reuse: classic vs stable prompt layout
//   clueless-bench names  [port]                     who is "Speaker 1"? names from context (bench/names.json)
//   clueless-bench speakers <wav> [count]            SpeakerKit speaker turns on a recorded call
//   clueless-bench notes  [port] [wav]               end-of-session notes with speaker labels and names
//   clueless-bench selftest                          logic checks, no servers or models needed
//   clueless-bench tts                               speech latency
//   clueless-bench prompts                           which prompt files are in use (needs no servers)
//
// Test cases are data, not code: bench/call.json, questions.json, watch.json, screen.json.
// Prompts are in prompts/*.txt. Edit those and re-run; no Swift change is needed.
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
        // Last row: the same 2 to 8 s method with the old forced cut at the very end (T19 comparison).
        .silence(minSeconds: 2, maxSeconds: 8),
    ]
    print(pad("method", 18), pad("WER", 7), pad("chunks", 7), pad("avg len", 8), pad("stt/chunk", 10), pad("worst lag", 10), "avg lag")
    for (index, method) in methods.enumerated() {
        var chunker = AudioChunker(method: method)
        let hardCut = index == methods.count - 1
        if hardCut { chunker.forcedCutSearchSeconds = 0 }
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
        print(pad(hardCut ? "sil-2-8s hard cut" : method.name, 18), pad(f(wer(text.joined(separator: " "), ref) * 100, 1) + "%", 7),
              pad("\(lens.count)", 7), pad(f(lens.reduce(0, +) / Double(max(lens.count, 1)), 1) + "s", 8),
              pad(f(stt.reduce(0, +) / Double(max(stt.count, 1))) + "s", 10),
              pad(f(lag.max() ?? 0, 1) + "s", 10), f(avgLag, 1) + "s")
    }
}

// MARK: test data (bench/*.json)

struct QA: Decodable { let q: String; let expect: [String] }
struct QuestionCase: Decodable { let q: String; let expect: [String]; let sources: [Int] }
struct CallData: Decodable {
    struct Line: Decodable { let source: String; let speaker: String?; let text: String }
    struct CatchUp: Decodable { let asked: [String]; let source: Int }
    let user: String
    let lines: [Line]
    let catchup: CatchUp
}
struct WatchData: Decodable {
    struct Line: Decodable { let speaker: String; let text: String }
    struct Case: Decodable { let speaker: String; let text: String; let want: Bool }
    let user: String
    let context: [Line]
    let cases: [Case]
}

/// Reads bench/<name>.json from the working copy this tool was built from (or `path` when given).
/// A missing or invalid file stops the run: quietly testing something else would be worse.
func loadCases<T: Decodable>(_ name: String, path: String? = nil) -> T {
    let file = path ?? Prompts.dataRoot.appendingPathComponent("bench").appendingPathComponent(name + ".json").path
    guard var data = FileManager.default.contents(atPath: file) else {
        print("error: cannot read \(file)")
        exit(1)
    }
    if data.starts(with: [0xEF, 0xBB, 0xBF]) { data = Data(data.dropFirst(3)) }   // byte-order mark from Windows editors
    do {
        return try JSONDecoder().decode(T.self, from: data)
    } catch {
        print("error: \(file) is not valid: \(error)")
        exit(1)
    }
}

// MARK: screen

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

    let qas: [QA] = loadCases("screen", path: qaPath)
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

/// The sample call from bench/call.json as a timeline. Line N of the file gets id N (L1, L2, ...).
func sampleCall(_ call: CallData) -> Timeline {
    let tl = Timeline()
    let base = Date().addingTimeInterval(-120)
    for (i, line) in call.lines.enumerated() {
        guard let source = TimelineLine.Source(rawValue: line.source) else {
            print("error: bench/call.json line \(i + 1): unknown source '\(line.source)' (use them, me, screen, webcam or system)")
            exit(1)
        }
        tl.append(source, line.text, speaker: line.speaker, at: base.addingTimeInterval(Double(i) * 9))
    }
    return tl
}

func benchAnswer(port: Int, label: String, cases: String = "questions") async throws {
    let answerer = Answerer(client: BonsaiClient(port: port))
    let call: CallData = loadCases("call")
    let lines = sampleCall(call).all
    // Each case: question, expected keywords ("a|b" = either), acceptable source lines ([] = no receipt needed).
    let qas: [QuestionCase] = loadCases(cases)
    print("== prompts: \(Prompts.summary)")
    var ok = 0, srcOK = 0, secs = 0.0, tps = 0.0, parsed = 0; var misses: [String] = []
    for qa in qas {
        let q = qa.q, expect = qa.expect, src = qa.sources
        let card = try await answerer.answer(.question, lines: lines, screenText: "", question: q, userName: call.user)
        secs += card.stats.seconds; tps += card.stats.tokensPerSecond
        if JSONRepair.object(card.raw) != nil { parsed += 1 }
        if hit(card.answer, expect) { ok += 1 } else { misses.append("\(q) -> \(card.answer.prefix(100))") }
        if src.isEmpty ? true : card.sources.contains(where: src.contains) { srcOK += 1 }
        else { misses.append("sources for '\(q)': got \(card.sources), want \(src)") }
    }
    print("== \(label) (port \(port)) questions: correct \(ok)/\(qas.count), receipts \(srcOK)/\(qas.count), valid JSON \(parsed)/\(qas.count), avg \(f(secs / Double(qas.count)))s, \(f(tps / Double(qas.count), 0)) tok/s")
    for m in misses { print("   x \(m)") }

    // Catch-up, three runs: "asked" must contain the keywords in call.json ("friday"), something must be
    // missed, a reply suggested, and the line in call.json (11) cited.
    var cu = 0, cuSecs = 0.0
    for run in 1...3 {
        let card = try await answerer.answer(.catchUp, lines: lines, screenText: "", userName: call.user)
        cuSecs += card.stats.seconds
        let good = hit(card.asked, call.catchup.asked) && !card.missed.isEmpty && !card.reply.isEmpty
            && card.sources.contains(call.catchup.source)
        if good { cu += 1 }
        if run == 1 || !good {
            print("   catch-up #\(run) \(good ? "ok" : "MISS") \(f(card.stats.seconds))s\n     asked:  \(card.asked)\n     missed: \(card.missed)\n     reply:  \(card.reply)\n     sources: \(card.sources)")
        }
    }
    print("== \(label) catch-up: \(cu)/3 good, avg \(f(cuSecs / 3))s")

    let notes = try await answerer.answer(.notes, lines: lines, screenText: "", userName: call.user)
    print("== \(label) notes (\(f(notes.stats.seconds))s, sources \(notes.sources)):\n\(notes.answer)\n")
}

// MARK: watch

func benchWatch(port: Int) async throws {
    let watcher = Watcher(client: BonsaiClient(port: port))
    // bench/watch.json: a few context lines, then cases. Each case is the newest line and whether it
    // should need the user ("want").
    let data: WatchData = loadCases("watch")
    let cases = data.cases
    print("prompts: \(Prompts.summary)")
    var codeOK = 0, modelOK = 0, calls = 0, secs = 0.0; var misses: [String] = []
    for item in cases {
        let text = item.text, want = item.want
        let tl = Timeline()
        for c in data.context { tl.append(.them, c.text, speaker: c.speaker) }
        let newest = tl.append(.them, text, speaker: item.speaker)
        if Watcher.precheck(newest, userName: data.user) == want { codeOK += 1 }
        let d = await watcher.watch(tl.all, userName: data.user)
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
    case "answer": try await benchAnswer(port: args.count > 1 ? Int(args[1])! : 8080, label: args.count > 2 ? args[2] : "9B",
                                         cases: args.count > 3 ? args[3] : "questions")
    case "stream":
        // How soon does the user see something when the card streams?
        let call: CallData = loadCases("call")
        let lines = sampleCall(call).all
        for run in 1...3 {
            let t0 = Date()
            let firstText = Box(), askedDone = Box()
            let card = try await Answerer().answer(.catchUp, lines: lines, screenText: "", userName: call.user) { partial in
                if firstText.value == nil, !partial.asked.isEmpty { firstText.value = Date().timeIntervalSince(t0) }
                if askedDone.value == nil, !partial.missed.isEmpty { askedDone.value = Date().timeIntervalSince(t0) }
            }
            print("run \(run): first words on screen \(f(firstText.value ?? -1))s, 'asked' complete \(f(askedDone.value ?? -1))s, whole card \(f(card.stats.seconds))s | asked: \(card.asked.prefix(60)) | sources \(card.sources)")
        }
    case "watch": try await benchWatch(port: args.count > 1 ? Int(args[1])! : 8082)
    case "cache": try await benchCache(port: args.count > 1 ? Int(args[1])! : 8080)
    case "names": try await benchNames(port: args.count > 1 ? Int(args[1])! : 8080)
    case "speakers": try await benchSpeakers(args[1], args.count > 2 ? Int(args[2]) : nil)
    case "notes": try await benchNotes(port: args.count > 1 ? Int(args[1])! : 8080, wav: args.count > 2 ? args[2] : nil)
    case "selftest": runSelftest()
    case "tts":
        let speaker = try await Speaker()
        print("TTSKit load: \(f(speaker.loadSeconds))s")
        for text in ["You were asked whether your team can still hit Friday.",
                     "The learning rate is zero point zero one. Homework three is due Thursday at eleven fifty nine p.m."] {
            print("spoke \(text.count) chars in \(f(try await speaker.sayAndWait(text)))s")
        }
    case "prompts":
        print("data folder: \(Prompts.dataRoot.path)")
        for line in Prompts.report() { print(line) }
    default:
        print("usage: clueless-bench chunk <wav> <ref.txt> | screen <image> [qa.json] | answer [port] [label] [cases] | watch [port] | cache [port] | names [port] | speakers <wav> [count] | notes [port] [wav] | tts | prompts | selftest")
    }
} catch {
    print("error: \(error.localizedDescription)")
    exit(1)
}
