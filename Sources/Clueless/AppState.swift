import Foundation
import AVFoundation
import SwiftUI
import Network
import CluelessCore

enum Mode: String, CaseIterable, Identifiable { case study = "Study", call = "Call"; var id: String { rawValue } }

/// The engine: capture -> chunk -> transcribe -> timeline -> (watcher) -> answerer -> card -> speech.
@MainActor
final class AppState: ObservableObject {
    @Published var mode: Mode = .study
    @Published var recording = false { didSet { syncPresence() } }
    @Published var status = "Loading models…" { didSet { Log.write("[status] \(status)") } }
    @Published var tail: [TimelineLine] = []
    // The HUD keeps the numbers of the last finished card (partial cards carry no timings).
    @Published var card: Card? { didSet { if let stats = card?.stats, stats.seconds > 0 { hud.last = stats } } }
    @Published var cardTitle = ""
    @Published var thinking = false
    @Published var question = ""
    @Published var focusQuestion = 0          // bumped by the hotkey to focus the field
    @Published var listening = false          // recording a spoken question (T25)
    @Published var hud = HUD()
    @Published var presence = Presence.Status.off
    /// Shown as a warning row in the panel while a Bonsai server is down, loading or being started.
    @Published var serverIssue: String?
    @Published var serverCanRestart = false
    @Published var startingServers = false
    // Server supervision state (used by the extension in Servers.swift).
    var lastServerStart = Date.distantPast
    var answererDeadChecks = 0
    var autoStartAttempts = 0
    @AppStorage("userName") var userName = "Yusuf"
    @AppStorage("speak") var speak = true
    @AppStorage("lookAway") var lookAway = true { didSet { syncPresence() } }
    @AppStorage("screenMethod") var screenMethodRaw = ScreenMethod.auto.rawValue

    struct HUD {
        var stt = 0.0, ocr = 0.0, llm = 0.0, tps = 0.0, watch = 0.0
        var tokens = 0
        var ramMB = 0
        var online = true
        var answerer = false, watcher = false
        var answererMB = 0, watcherMB = 0      // memory of the two Bonsai servers
        var last = BonsaiStats()               // timings of the last finished card
    }

    let timeline: Timeline
    /// Where this session's screen receipts are saved (next to the session's JSONL file).
    let snapshotDir: URL
    /// The screen the current card was answered from; shown under the card's receipts (Receipts.swift).
    @Published var screenReceipt: ScreenReceipt?
    let capture = Capture()
    // Call notes (CallNotes.swift, T33): the other side's audio is kept so the speakers can be labelled.
    var sessionAudio = SessionAudio()
    /// When call mode was last entered. Call notes cover the call from here on, not the study session before it.
    var callStartedAt = Date.distantPast
    var speakerLabeler: SpeakerLabeler?
    /// Lines with the speaker names found by the last call notes, by line number. Receipts show these.
    @Published var namedLines: [Int: TimelineLine] = [:]
    // Capture supervision state (used by the extension in CaptureRestart.swift).
    var wantRecording = false          // the user wants capture on; false after pause
    var captureLive = false            // a real SCStream is running (not the file test hook)
    var captureStartedAt = Date.distantPast
    var captureRestarts = 0
    @Published var restartingCapture = false
    var captureWatchdog: Timer?
    var transcriber: Transcriber?      // not private: call notes transcribe the recording again per speaker turn (T35)
    private var speaker: Speaker?
    private var speech: SpeechQueue?   // speaks a card sentence by sentence while it streams (T07)
    private let answerer = Answerer()
    private let watcher = Watcher()
    private let work = DispatchQueue(label: "clueless.chunks")
    private var chunkers: [Capture.Source: AudioChunker] = [:]
    private var sttChain: Task<Void, Never>?
    private var lastWatchTrigger = Date.distantPast   // last automatic catch-up (watcher or look-away)
    /// When the other side was last heard speaking (system audio above the chunker's pause level). T38.
    private var lastThemSpeechAt = Date.distantPast
    private let micGate = ProcessInfo.processInfo.environment["CLUELESS_MIC_GATE"] != "0"
    private var starting = false       // a `start()` is in flight: a second one would open a second stream
    private var voiceSession = 0       // counts spoken questions, for the stuck-microphone failsafe
    let webcam = Presence()            // not private: the camera test window reads its frames (T31)
    private let voice = VoiceRecorder()
    private var webcamOn = false
    /// True while the camera test window is open: keeps the webcam on even when paused (CameraTestView.swift).
    var cameraTest = false { didSet { syncPresence() } }
    private let pathMonitor = NWPathMonitor()
    private var hudTimer: Timer?
    private var napGuard: NSObjectProtocol?

    var screenMethod: ScreenMethod { ScreenMethod(rawValue: screenMethodRaw) ?? .auto }

    init() {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        timeline = Timeline(jsonl: Paths.sessions.appendingPathComponent("\(stamp).jsonl"))
        snapshotDir = Paths.sessions.appendingPathComponent("\(stamp)-screens")
        // Test hook: CLUELESS_TEST_MODE=call starts in call mode, so call mode can be checked with nobody at the Mac.
        if ProcessInfo.processInfo.environment["CLUELESS_TEST_MODE"] == "call" { mode = .call; callStartedAt = Date() }
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
        webcam.onStatus = { [weak self] status in self?.presence = status }
        webcam.onEvent = { [weak self] event in self?.presenceChanged(event) }
        // Test hook: CLUELESS_TEST_LOOKAWAY=<seconds> pretends the user looked away for that long, then
        // came back, so the trigger-to-card path can be checked without a person at the webcam.
        if let seconds = Double(ProcessInfo.processInfo.environment["CLUELESS_TEST_LOOKAWAY"] ?? "") {
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64((30 + seconds) * 1e9))
                self?.presenceChanged(.returned(awaySeconds: seconds, since: Date().addingTimeInterval(-seconds)))
            }
        }
        Task { await load() }
    }

    // MARK: lifecycle

    private func load() async {
        // Bring the Bonsai servers up while the speech models load.
        Task { await checkServers(); if !hud.answerer, !startingServers { await checkServers() } }
        do {
            // Keep every model loaded for the life of the app.
            transcriber = try await Transcriber()
            status = "Loading voice…"
            speaker = try? await Speaker()
            if let speaker { speech = SpeechQueue(speaker: speaker) }
            await refreshHUD()
            status = "Ready"
            await start()
            // SpeakerKit is only needed for call notes: load it once the app is already listening.
            Task { await loadSpeakerLabeler() }
            // Test hook: CLUELESS_TEST_VOICE=<seconds> starts a voice question that long after launch, so the
            // microphone path can be checked from the log without anyone pressing the hotkey.
            if let delay = Double(ProcessInfo.processInfo.environment["CLUELESS_TEST_VOICE"] ?? "") {
                Task { [weak self] in
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1e9))
                    self?.toggleVoiceQuestion()
                }
            }
        } catch {
            status = "Could not load speech models: \(error.localizedDescription)"
        }
    }

    func start() async {
        guard !recording, !restartingCapture, !starting, transcriber != nil else { return }
        starting = true
        defer { starting = false }
        wantRecording = true
        captureRestarts = 0
        resetChunkers()
        capture.onAudio = { [weak self] source, samples in self?.ingest(source, samples) }
        // If the stream dies, bring it back (CaptureRestart.swift).
        capture.onStop = { [weak self] error in
            Task { @MainActor in self?.captureStopped(error) }
        }
        // Test hook: CLUELESS_AUDIO_FILE plays a file into the pipeline as system audio, in real time.
        if let path = ProcessInfo.processInfo.environment["CLUELESS_AUDIO_FILE"] {
            recording = true; status = "Listening (file: \(path))"
            Task.detached { [weak self] in
                guard let samples = try? AudioFile.load16k(path) else { return }
                var i = 0
                let began = Date()
                while i < samples.count {
                    self?.ingest(.system, Array(samples[i..<min(i + 1600, samples.count)]))
                    i += 1600
                    // Sleep until this point of the file is due, so the file plays in real time. A fixed
                    // 100 ms sleep per buffer ran 3 to 4% slow and put speaker labels slightly off.
                    let wait = began.addingTimeInterval(Double(i) / 16_000).timeIntervalSinceNow
                    if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1e9)) }
                }
                // trailing silence so the last chunk is cut
                for _ in 0..<30 { self?.ingest(.system, [Float](repeating: 0, count: 1600)); try? await Task.sleep(nanoseconds: 100_000_000) }
                if let q = ProcessInfo.processInfo.environment["CLUELESS_TEST_QUESTION"] {
                    await MainActor.run { self?.question = q; self?.ask() }
                    try? await Task.sleep(nanoseconds: 15_000_000_000)
                    await MainActor.run { self?.catchUp() }
                }
                // Test hook: CLUELESS_TEST_NOTES asks for session notes once the file has played and no
                // card is being written (with CLUELESS_TEST_MODE=call these are the call notes, T33).
                if ProcessInfo.processInfo.environment["CLUELESS_TEST_NOTES"] != nil {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    while await MainActor.run(body: { self?.thinking ?? false }) {
                        try? await Task.sleep(nanoseconds: 500_000_000)
                    }
                    await MainActor.run { self?.notes() }
                }
            }
            return
        }
        do {
            try await capture.start(microphone: mode == .call)
            captureDidStart()
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
            status = mode == .call
                ? "Could not start capture. Check Screen Recording and Microphone in System Settings › Privacy & Security, then press play. \(error.localizedDescription)"
                : "Screen Recording permission needed (System Settings › Privacy & Security), then relaunch. \(error.localizedDescription)"
        }
    }

    func resetChunkers() {
        // Pause-based chunks: best accuracy/lag trade-off in our benchmark (BENCHMARKS.md).
        chunkers = [.system: AudioChunker(method: .silence(minSeconds: 2, maxSeconds: 8)),
                    .mic: AudioChunker(method: .silence(minSeconds: 2, maxSeconds: 8))]
    }

    func stop() async {
        wantRecording = false
        captureLive = false
        await capture.stop()
        recording = false
        status = "Paused"
        // The last few seconds are still waiting in the chunkers for a pause in the speech. `start()` resets
        // the chunkers, so without this a sentence said just before Pause never reached the transcript.
        cutBufferedAudio()
    }

    /// Cut whatever audio is waiting in the chunkers and queue it for transcription. Returns how many
    /// chunks were cut. Does not wait for the transcription.
    @discardableResult
    func cutBufferedAudio() -> Int {
        var cut = 0
        for source in [Capture.Source.system, .mic] {
            guard var chunker = chunkers[source], let chunk = chunker.flush() else { continue }
            chunkers[source] = chunker
            enqueue(chunk, source: source)
            cut += 1
        }
        return cut
    }

    // While a restart is in progress the button means "stop trying".
    func toggle() { Task { (recording || restartingCapture) ? await stop() : await start() } }

    func modeChanged() {
        // Entering call mode starts a new call: its notes must not include the study session before it,
        // or the recording of an earlier call.
        if mode == .call {
            callStartedAt = Date()
            sessionAudio = SessionAudio()
            Log.write("[notes] call mode entered: call notes start here")
        }
        Task {
            // A start in flight was made for the old mode (with or without the microphone): let it finish.
            while starting { try? await Task.sleep(nanoseconds: 100_000_000) }
            // `wantRecording`: also after a start that failed, so switching back to Study resumes by itself.
            if recording || (wantRecording && !restartingCapture) { await stop(); await start() }
        }
    }

    // MARK: audio -> timeline

    /// Called on the capture queue.
    nonisolated private func ingest(_ source: Capture.Source, _ samples: [Float]) {
        work.async { [weak self] in
            guard let self else { return }
            // Is somebody on the other side speaking in this buffer? Same level the chunker calls a pause.
            var energy: Float = 0
            if source == .system { for v in samples { energy += v * v } }
            let speaking = !samples.isEmpty && (energy / Float(samples.count)).squareRoot() >= 0.006
            Task { @MainActor in
                if speaking { self.lastThemSpeechAt = Date() }
                if source == .mic, self.micGate, self.micHearsSpeakers { return }
                // In a call, keep the other side's audio for the speaker labels in the notes (T33).
                if source == .system, self.mode == .call { self.sessionAudio.append(samples) }
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
            if Self.isSilenceFiller(text) {
                Log.write("[stt] dropped \"\(text)\": Whisper writes this on near-silent audio")
                return
            }
            let line = self.timeline.append(source == .mic ? .me : .them, text, at: chunk.startedAt)
            Log.write("[stt \(String(format: "%.2f", self.hud.stt))s] \(line.rendered)")
            self.tail = self.timeline.last(40).filter { $0.source == .them || $0.source == .me }.suffix(5).map { $0 }
            if self.mode == .call, line.source == .them { self.runWatcher() }
        }
    }

    /// With nothing playing, Whisper turns faint noise into "you", "Thank you." or "Thank" (four such lines in
    /// two quiet hours on the Mac mini). A whole chunk that is only one of these is dropped, so it does not
    /// land in the transcript or the notes.
    static func isSilenceFiller(_ text: String) -> Bool {
        let plain = text.lowercased().filter { $0.isLetter || $0 == " " }.trimmingCharacters(in: .whitespaces)
        return ["you", "thank", "thank you", "thanks for watching", "thank you for watching"].contains(plain)
    }

    /// Bring the timeline up to the present: transcribe whatever audio is still sitting in the chunkers
    /// and wait for the transcription queue, so a card is not built without the last few seconds.
    /// Never waits longer than `maxWait`.
    private func flushAudio(maxWait: TimeInterval = 2) async {
        let t0 = Date()
        let flushed = cutBufferedAudio()
        guard let chain = sttChain else { return }
        // Waiting on a task cannot be cancelled, so poll a flag against the deadline instead.
        final class Flag: @unchecked Sendable { var done = false }
        let flag = Flag()
        Task { @MainActor in await chain.value; flag.done = true }
        while !flag.done, Date().timeIntervalSince(t0) < maxWait {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        Log.write("[flush] \(flushed) chunk(s) cut early, waited \(String(format: "%.2f", Date().timeIntervalSince(t0)))s\(flag.done ? "" : " (gave up waiting)")")
    }

    private func runWatcher() {
        let lines = timeline.last(8).filter { $0.source == .them || $0.source == .me }
        Task {
            let decision = await watcher.watch(lines, userName: userName)
            if decision.usedModel { hud.watch = decision.seconds }
            // One automatic catch-up per 20 s at most, and never on top of one in progress.
            if decision.needsUser, !thinking, Date().timeIntervalSince(lastWatchTrigger) > 20 {
                lastWatchTrigger = Date()
                let title = decision.reason == "name" ? "You were called on" : "A question for you"
                if Date().timeIntervalSince(lastThemSpeechAt) < 0.8 {
                    // The speaker is still talking: say so at once instead of showing nothing for seconds.
                    var waiting = Card(task: .question)
                    waiting.answer = "Listening to the rest of the question…"
                    screenReceipt = nil; cardTitle = title; card = waiting
                }
                await waitForThemToFinish()
                await run(.catchUp, title: title)
            }
        }
    }

    /// In a call on loudspeakers the microphone also hears the other side and Clueless's own voice, and each
    /// would come back as a "You" line and land in the cards and the notes. So microphone audio is dropped
    /// while either is playing, and for half a second after (the room's echo). With headphones this is not
    /// needed: CLUELESS_MIC_GATE=0 turns it off.
    private var micHearsSpeakers: Bool {
        Date().timeIntervalSince(lastThemSpeechAt) < 0.5 || speech?.speaking == true
            || Date().timeIntervalSince(speech?.lastSpokeAt ?? .distantPast) < 0.5
    }

    /// The name is often said before the question ("One more question. Yusuf." and only then the question),
    /// and a card built at once does not have it (seen on the Mac mini). Wait until the other side has been
    /// quiet for a moment, so the card is built when the speaker has finished. A question that ended with the
    /// name is already followed by silence and does not wait at all.
    private func waitForThemToFinish(quiet: TimeInterval = 0.8, maxWait: TimeInterval = 6) async {
        let t0 = Date()
        while !thinking, Date().timeIntervalSince(lastThemSpeechAt) < quiet, Date().timeIntervalSince(t0) < maxWait {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        let waited = Date().timeIntervalSince(t0)
        Log.write("[watcher] needs you; waited \(String(format: "%.1f", waited)) s for the speaker to finish\(waited >= maxWait ? " (still speaking, gave up)" : "")")
    }

    // MARK: look-away trigger

    /// The webcam runs only while recording and while the setting is on.
    private func syncPresence() {
        let wanted = (recording && lookAway) || cameraTest
        guard wanted != webcamOn else { return }
        webcamOn = wanted
        if wanted { webcam.start() } else { webcam.stop() }
    }

    private func presenceChanged(_ event: PresenceTracker.Event) {
        switch event {
        case .left(let at):
            timeline.append(.webcam, "Looked away", at: at)
        case .returned(let seconds, let since):
            timeline.append(.webcam, "Looked back after \(Int(seconds)) s")
            // `lookAway`: the camera test window can keep the webcam on while the setting is off.
            guard recording, lookAway, seconds >= 5, !thinking, Date().timeIntervalSince(lastWatchTrigger) > 20 else {
                let why = !recording ? "not recording" : !lookAway ? "the look-away setting is off"
                    : seconds < 5 ? "under 5 s" : thinking ? "a card is being written" : "another automatic card under 20 s ago"
                Log.write("[presence] back after \(Int(seconds)) s, no card (\(why))")
                return
            }
            Task {
                // What was said while away may still be in the audio buffer: transcribe it before counting.
                await flushAudio()
                // Only worth a card if somebody said something meanwhile.
                let missed = timeline.recent(seconds: Date().timeIntervalSince(since), maxLines: 200)
                    .filter { $0.source == .them }
                Log.write("[presence] back after \(Int(seconds)) s, \(missed.count) lines missed")
                // One short line is not worth a card, and with almost nothing to go on the model makes one up.
                let enough = missed.count >= 2 || missed.reduce(0) { $0 + $1.text.count } >= 60
                guard enough, !thinking else { return }
                lastWatchTrigger = Date()
                // Only the absence plus a short lead-in for context. A wider window made the card summarise
                // everything said so far instead of what was missed (seen in the Mac mini test).
                let window = min(600, Date().timeIntervalSince(since) + 20)
                await run(.catchUp, title: "While you looked away (\(Int(seconds)) s)", window: window)
            }
        }
    }

    // MARK: answers

    func ask() {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        question = ""
        timeline.append(.system, "User asked: \(q)")   // .system lines are logged but never sent to the model
        Task {
            // A card may be in progress (a look-away catch-up starts by itself): wait for it. Before, the
            // question was cleared from the field and silently dropped.
            let waitStart = Date()
            while thinking, Date().timeIntervalSince(waitStart) < 20 {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            await run(.question, title: q, question: q)
        }
    }

    func catchUp() { Task { await run(.catchUp, title: "Catch-up") } }

    func notes() { Task { await run(.notes, title: "Session notes") } }

    private func run(_ task: AnswerTask, title: String, question: String? = nil,
                     window: TimeInterval? = nil) async {
        guard !thinking else { return }
        screenReceipt = nil   // it belonged to the previous card
        if startingServers {
            var waiting = Card(task: task)
            waiting.answer = "The Bonsai servers are still starting. Try again in a few seconds."
            cardTitle = title; card = waiting
            return
        }
        thinking = true; cardTitle = title; card = nil
        defer { thinking = false }
        let started = Date()
        var firstSpeech: TimeInterval?
        speech?.begin()   // also stops anything still being said

        // Screen: OCR text and/or a downscaled screenshot, depending on the method setting.
        var screenText = "", image: Data?
        let method: ScreenMethod = task == .notes ? .none : screenMethod
        var shot: CGImage?
        // While the screen is being read, finish transcribing the audio that is still buffered.
        async let audioFlushed: Void = flushAudio()
        if method != .none {
            do { shot = try await capture.screenshot() } catch { Log.write("[screenshot failed] \(error.localizedDescription)") }
        }
        if let shot {
            // The core decides what to send. With "auto" the screenshot is only attached when the question
            // is about something visual, because an image makes the first token take about 6 s (T08).
            let input = await Task.detached {
                ScreenInput.prepare(shot, method: method, task: task, question: question)
            }.value
            screenText = input.text
            image = input.image
            hud.ocr = input.ocrSeconds
            // Receipt: save the screenshot and record it on the timeline with `snapshot` set (T06).
            keepReceipt(of: shot, text: screenText)
        }

        await audioFlushed
        // Default windows are stepped (T09): the first line only changes once a minute, so the Bonsai server
        // reuses its cache between requests. A window given by the caller (look-away) is kept exact.
        let step: TimeInterval = window == nil ? 60 : 0
        let window: TimeInterval = window ?? (task == .notes ? 3600 : (task == .catchUp ? 150 : 300))
        // A question may be about anything in the window, so it gets more lines than a catch-up. With 45,
        // a question at the end of a 162 s lecture could not see its first lines (seen on the Mac mini).
        let maxLines = task == .notes ? 200 : (task == .question ? 120 : 45)
        let lines = timeline.recent(seconds: window, maxLines: maxLines, step: step)
            .filter { $0.source == .them || $0.source == .me }
        do {
            let onPartial: @Sendable (Card) -> Void = { [weak self] partial in
                // Show the card growing as tokens arrive, and start speaking as soon as a sentence is whole.
                Task { @MainActor in
                    guard let self, self.thinking else { return }
                    self.card = partial
                    if self.speak, self.speech?.update(partial.spoken, final: false) == true, firstSpeech == nil {
                        firstSpeech = Date().timeIntervalSince(started)
                    }
                }
            }
            // In a call the notes are by speaker, with names: speakers are labelled and named first (T33).
            let result = task == .notes && mode == .call
                ? try await callNotes(lines.filter { $0.t >= callStartedAt }, answerer: answerer, onPartial: onPartial)
                : try await answerer.answer(task, lines: lines, screenText: screenText, image: image,
                                            question: question, userName: userName, onPartial: onPartial)
            card = result
            Log.write("[card \(task.rawValue) \(String(format: "%.2f", result.stats.seconds))s, first token \(String(format: "%.2f", result.stats.firstTokenSeconds))s, ocr \(screenText.count) chars, image \(image?.count ?? 0) bytes] \(result.raw)")
            hud.llm = result.stats.seconds; hud.tps = result.stats.tokensPerSecond
            hud.tokens = result.stats.promptTokens + result.stats.outputTokens
            // Whatever has not been spoken yet (everything, if nothing streamed).
            if speak, speech?.update(result.spoken, final: true) == true, firstSpeech == nil {
                firstSpeech = Date().timeIntervalSince(started)
            }
            if let firstSpeech {
                Log.write("[speech] first words queued \(String(format: "%.2f", firstSpeech))s after the trigger; whole card took \(String(format: "%.2f", Date().timeIntervalSince(started)))s")
            }
        } catch {
            var failed = Card(task: task)
            failed.answer = "Bonsai did not answer (\(error.localizedDescription)). Clueless is checking the servers; try again in a few seconds."
            card = failed
            Log.write("[card failed] \(error.localizedDescription)")
            // Check right away instead of waiting for the next timer tick.
            Task { await checkServers() }
        }
    }

    func stopSpeaking() { speech?.stop(); speaker?.stop() }

    /// "Your name" in the menu: a text field inside a macOS menu cannot be typed into, so ask in a dialog.
    func editUserName() {
        let alert = NSAlert()
        alert.messageText = "Your name"
        alert.informativeText = "In a call, Clueless catches you up when someone says this name."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = userName
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        objectWillChange.send()
        userName = name
        Log.write("[settings] user name set to \(name)")
    }

    // MARK: ask by voice (T25)

    /// Start listening for a spoken question, or finish one that is being recorded. Study mode only:
    /// in a call the other people would hear the question, and the microphone is already "You".
    func toggleVoiceQuestion() {
        if listening { finishVoiceQuestion(); return }
        guard mode == .study, transcriber != nil, !thinking else { return }
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            Task { @MainActor in
                guard granted else {
                    self.voiceProblem("Clueless needs the microphone to hear a spoken question. Allow it in System Settings › Privacy & Security › Microphone.")
                    return
                }
                self.stopSpeaking()   // do not record our own voice
                self.voice.onAutoStop = { [weak self] in self?.finishVoiceQuestion() }
                do {
                    try self.voice.start()
                    self.listening = true
                    Log.write("[voice] listening")
                    // Auto-stop is decided inside the microphone callback. If the microphone stops delivering
                    // (another audio engine starting can do that), finish anyway instead of listening forever.
                    self.voiceSession += 1
                    let session = self.voiceSession
                    Task { [weak self] in
                        try? await Task.sleep(nanoseconds: 22_000_000_000)
                        guard let self, self.listening, self.voiceSession == session else { return }
                        Log.write("[voice] no auto-stop after 22 s: finishing")
                        self.finishVoiceQuestion()
                    }
                } catch {
                    self.voiceProblem("Could not start the microphone: \(error.localizedDescription)")
                }
            }
        }
    }

    private func finishVoiceQuestion() {
        guard listening else { return }
        listening = false
        let samples = voice.stop()
        Log.write("[voice] \(voice.summary)")
        guard samples.count > 8_000, let transcriber else {   // under half a second: nothing was said
            Log.write("[voice] nothing heard")
            return
        }
        // Whisper runs one job at a time: wait for the chunks already queued, and make later chunks wait for this.
        let previous = sttChain
        let t0 = Date()
        let job = Task { () -> String? in
            await previous?.value
            return try? await transcriber.transcribe(samples)
        }
        sttChain = Task { _ = await job.value }
        Task {
            let text = (await job.value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            Log.write("[voice \(String(format: "%.2f", Date().timeIntervalSince(t0)))s, \(String(format: "%.1f", Double(samples.count) / 16_000))s of audio] \(text)")
            guard text.count > 2 else { return }
            // If a card is being written (a look-away catch-up can fire at the same moment), wait for it
            // instead of losing the question.
            let waitStart = Date()
            while thinking, Date().timeIntervalSince(waitStart) < 20 {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            question = text
            ask()
        }
    }

    private func voiceProblem(_ message: String) {
        Log.write("[voice] \(message)")
        var problem = Card(task: .question)
        problem.answer = message
        cardTitle = "Ask by voice"; card = problem
    }

    // MARK: HUD

    private func refreshHUD() async {
        await checkServers()
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        if kr == KERN_SUCCESS { hud.ramMB = Int(info.phys_footprint / 1_048_576) }
        refreshServerMemory()
    }
}
