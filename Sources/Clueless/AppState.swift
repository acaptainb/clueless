import Foundation
import SwiftUI
import Network
import CluelessCore

enum Mode: String, CaseIterable, Identifiable { case study = "Study", call = "Call"; var id: String { rawValue } }

/// The engine: capture -> chunk -> transcribe -> timeline -> (watcher) -> answerer -> card -> speech.
@MainActor
final class AppState: ObservableObject {
    @Published var mode: Mode = .study
    @Published var recording = false
    @Published var status = "Loading models…" { didSet { Log.write("[status] \(status)") } }
    @Published var tail: [TimelineLine] = []
    @Published var card: Card?
    @Published var cardTitle = ""
    @Published var thinking = false
    @Published var question = ""
    @Published var focusQuestion = 0          // bumped by the hotkey to focus the field
    @Published var hud = HUD()
    @AppStorage("userName") var userName = "Yusuf"
    @AppStorage("speak") var speak = true
    @AppStorage("screenMethod") var screenMethodRaw = ScreenMethod.both.rawValue

    struct HUD {
        var stt = 0.0, ocr = 0.0, llm = 0.0, tps = 0.0, watch = 0.0
        var tokens = 0
        var ramMB = 0
        var online = true
        var answerer = false, watcher = false
    }

    let timeline: Timeline
    private let capture = Capture()
    private var transcriber: Transcriber?
    private var speaker: Speaker?
    private let answerer = Answerer()
    private let watcher = Watcher()
    private let work = DispatchQueue(label: "clueless.chunks")
    private var chunkers: [Capture.Source: AudioChunker] = [:]
    private var sttChain: Task<Void, Never>?
    private var lastWatchTrigger = Date.distantPast
    private let pathMonitor = NWPathMonitor()
    private var hudTimer: Timer?
    private var napGuard: NSObjectProtocol?

    var screenMethod: ScreenMethod { ScreenMethod(rawValue: screenMethodRaw) ?? .both }

    init() {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        timeline = Timeline(jsonl: Paths.sessions.appendingPathComponent("\(stamp).jsonl"))
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in self?.hud.online = path.status == .satisfied }
        }
        pathMonitor.start(queue: .global())
        hudTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshHUD() }
        }
        // Keep transcribing at full speed while another app is in front (no App Nap).
        napGuard = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical],
                                                         reason: "Live transcription")
        Task { await load() }
    }

    // MARK: lifecycle

    private func load() async {
        do {
            // Keep every model loaded for the life of the app.
            transcriber = try await Transcriber()
            status = "Loading voice…"
            speaker = try? await Speaker()
            await refreshHUD()
            status = hud.answerer ? "Ready" : "Bonsai servers are not running: ./scripts/servers.sh start"
            await start()
        } catch {
            status = "Could not load speech models: \(error.localizedDescription)"
        }
    }

    func start() async {
        guard !recording, transcriber != nil else { return }
        // Pause-based chunks: best accuracy/lag trade-off in our benchmark (BENCHMARKS.md).
        chunkers = [.system: AudioChunker(method: .silence(minSeconds: 2, maxSeconds: 8)),
                    .mic: AudioChunker(method: .silence(minSeconds: 2, maxSeconds: 8))]
        capture.onAudio = { [weak self] source, samples in self?.ingest(source, samples) }
        capture.onStop = { [weak self] error in
            Task { @MainActor in
                self?.recording = false
                self?.status = "Capture stopped: \(error?.localizedDescription ?? "")"
            }
        }
        // Test hook: CLUELESS_AUDIO_FILE plays a file into the pipeline as system audio, in real time.
        if let path = ProcessInfo.processInfo.environment["CLUELESS_AUDIO_FILE"] {
            recording = true; status = "Listening (file: \(path))"
            Task.detached { [weak self] in
                guard let samples = try? AudioFile.load16k(path) else { return }
                var i = 0
                while i < samples.count {
                    self?.ingest(.system, Array(samples[i..<min(i + 1600, samples.count)]))
                    i += 1600
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
                // trailing silence so the last chunk is cut
                for _ in 0..<30 { self?.ingest(.system, [Float](repeating: 0, count: 1600)); try? await Task.sleep(nanoseconds: 100_000_000) }
                if let q = ProcessInfo.processInfo.environment["CLUELESS_TEST_QUESTION"] {
                    await MainActor.run { self?.question = q; self?.ask() }
                    try? await Task.sleep(nanoseconds: 15_000_000_000)
                    await MainActor.run { self?.catchUp() }
                }
            }
            return
        }
        do {
            try await capture.start(microphone: mode == .call)
            recording = true
            status = "Listening"
            timeline.append(.system, "Session started in \(mode.rawValue.lowercased()) mode")
            // Test hook for live capture: ask a question after a delay, then a catch-up.
            if let q = ProcessInfo.processInfo.environment["CLUELESS_TEST_QUESTION"] {
                let delay = Double(ProcessInfo.processInfo.environment["CLUELESS_TEST_DELAY"] ?? "") ?? 45
                Task { [weak self] in
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1e9))
                    self?.question = q; self?.ask()
                    try? await Task.sleep(nanoseconds: 25_000_000_000)
                    self?.catchUp()
                }
            }
        } catch {
            status = "Screen Recording permission needed (System Settings › Privacy & Security), then relaunch. \(error.localizedDescription)"
        }
    }

    func stop() async {
        await capture.stop()
        recording = false
        status = "Paused"
    }

    func toggle() { Task { recording ? await stop() : await start() } }

    func modeChanged() { Task { if recording { await stop(); await start() } } }

    // MARK: audio -> timeline

    /// Called on the capture queue.
    nonisolated private func ingest(_ source: Capture.Source, _ samples: [Float]) {
        work.async { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                guard var chunker = self.chunkers[source] else { return }
                let chunk = chunker.feed(samples)
                self.chunkers[source] = chunker
                if let chunk { self.enqueue(chunk, source: source) }
            }
        }
    }

    /// Transcribe chunks one at a time, in order.
    private func enqueue(_ chunk: AudioChunker.Chunk, source: Capture.Source) {
        let previous = sttChain
        sttChain = Task { [weak self] in
            await previous?.value
            guard let self, let transcriber = self.transcriber else { return }
            let t0 = Date()
            guard let text = try? await transcriber.transcribe(chunk.samples), text.count > 1 else { return }
            self.hud.stt = Date().timeIntervalSince(t0)
            let line = self.timeline.append(source == .mic ? .me : .them, text, at: chunk.startedAt)
            Log.write("[stt \(String(format: "%.2f", self.hud.stt))s] \(line.rendered)")
            self.tail = self.timeline.last(40).filter { $0.source == .them || $0.source == .me }.suffix(5).map { $0 }
            if self.mode == .call, line.source == .them { self.runWatcher() }
        }
    }

    private func runWatcher() {
        let lines = timeline.last(8).filter { $0.source == .them || $0.source == .me }
        Task {
            let decision = await watcher.watch(lines, userName: userName)
            if decision.usedModel { hud.watch = decision.seconds }
            // One automatic catch-up per 20 s at most, and never on top of one in progress.
            if decision.needsUser, !thinking, Date().timeIntervalSince(lastWatchTrigger) > 20 {
                lastWatchTrigger = Date()
                await run(.catchUp, title: decision.reason == "name" ? "You were called on" : "A question for you")
            }
        }
    }

    // MARK: answers

    func ask() {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        question = ""
        timeline.append(.system, "User asked: \(q)")   // .system lines are logged but never sent to the model
        Task { await run(.question, title: q, question: q) }
    }

    func catchUp() { Task { await run(.catchUp, title: "Catch-up") } }

    func notes() { Task { await run(.notes, title: "Session notes") } }

    private func run(_ task: AnswerTask, title: String, question: String? = nil) async {
        guard !thinking else { return }
        thinking = true; cardTitle = title; card = nil
        defer { thinking = false }
        speaker?.stop()

        // Screen: OCR text and/or a downscaled screenshot, depending on the method setting.
        var screenText = "", image: Data?
        let method: ScreenMethod = task == .notes ? .none : screenMethod
        var shot: CGImage?
        if method != .none {
            do { shot = try await capture.screenshot() } catch { Log.write("[screenshot failed] \(error.localizedDescription)") }
        }
        if let shot {
            let t0 = Date()
            if method != .image { screenText = await Task.detached { ScreenText.recognize(shot) }.value }
            hud.ocr = Date().timeIntervalSince(t0)
            if method != .ocr { image = ScreenText.jpeg(shot) }
            if !screenText.isEmpty { timeline.append(.screen, String(screenText.prefix(300))) }
        }

        let window: TimeInterval = task == .notes ? 3600 : (task == .catchUp ? 150 : 300)
        let lines = timeline.recent(seconds: window, maxLines: task == .notes ? 200 : 45)
            .filter { $0.source == .them || $0.source == .me }
        do {
            let result = try await answerer.answer(task, lines: lines, screenText: screenText, image: image,
                                                   question: question, userName: userName) { [weak self] partial in
                // Show the card growing as tokens arrive.
                Task { @MainActor in if self?.thinking == true { self?.card = partial } }
            }
            card = result
            Log.write("[card \(task.rawValue) \(String(format: "%.2f", result.stats.seconds))s, first token \(String(format: "%.2f", result.stats.firstTokenSeconds))s, ocr \(screenText.count) chars, image \(image?.count ?? 0) bytes] \(result.raw)")
            hud.llm = result.stats.seconds; hud.tps = result.stats.tokensPerSecond
            hud.tokens = result.stats.promptTokens + result.stats.outputTokens
            if speak, !result.spoken.isEmpty { speaker?.say(result.spoken) }
        } catch {
            var failed = Card(task: task)
            failed.answer = "Bonsai did not answer. Is ./scripts/servers.sh start running? (\(error.localizedDescription))"
            card = failed
        }
    }

    func stopSpeaking() { speaker?.stop() }

    // MARK: HUD

    private func refreshHUD() async {
        hud.answerer = await answerer.client.isUp()
        hud.watcher = await watcher.client.isUp()
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        if kr == KERN_SUCCESS { hud.ramMB = Int(info.phys_footprint / 1_048_576) }
    }
}
