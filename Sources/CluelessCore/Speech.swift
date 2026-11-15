import Foundation
import WhisperKit
import TTSKit

/// Argmax WhisperKit, loaded once from the local models folder. Never downloads.
public final class Transcriber: @unchecked Sendable {
    private let pipe: WhisperKit
    public private(set) var loadSeconds: Double = 0

    public init() async throws {
        let t0 = Date()
        let config = WhisperKitConfig(
            modelFolder: Paths.whisperModel.path,
            tokenizerFolder: Paths.whisperTokenizer,
            verbose: false,
            logLevel: .error,
            prewarm: false,
            load: true,
            download: false
        )
        pipe = try await WhisperKit(config)
        loadSeconds = Date().timeIntervalSince(t0)
    }

    /// 16 kHz mono Float32 in, text out.
    public func transcribe(_ samples: [Float]) async throws -> String {
        let options = DecodingOptions(language: "en", skipSpecialTokens: true, withoutTimestamps: true)
        let results = try await pipe.transcribe(audioArray: samples, decodeOptions: options)
        return Self.clean(results.map(\.text).joined(separator: " "))
    }

    static func clean(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "\\[[A-Z_ ]+\\]|\\([a-z ]+\\)", with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// How live audio is cut into pieces for transcription. This is one of the things we benchmark.
public enum ChunkMethod: Sendable, Equatable {
    /// Cut every `seconds`, wherever that lands.
    case fixed(seconds: Double)
    /// Cut at the first pause after `minSeconds`, or at `maxSeconds` if nobody pauses.
    case silence(minSeconds: Double, maxSeconds: Double)

    public var name: String {
        switch self {
        case .fixed(let s): return "fixed-\(Int(s))s"
        case .silence(let a, let b): return "silence-\(Int(a))-\(Int(b))s"
        }
    }
}

/// Accumulates 16 kHz mono samples from one source and emits finished chunks.
/// Not thread-safe: feed it from one queue.
public struct AudioChunker {
    public static let sampleRate = 16_000
    public let method: ChunkMethod
    private var buffer: [Float] = []
    private var startedAt: Date?
    /// RMS below this over a 200 ms window counts as a pause.
    public var silenceRMS: Float = 0.006
    /// On a forced cut, how far back from the end to look for a gap between words. 0 cuts at the very end.
    /// 3 s, not 1.5: in unbroken speech the nearest real gap is often further back, and a cut inside a
    /// phrase lost words ("it covers lectures one through eight" became "it cover" / "through 8").
    /// Measured on the demo lecture: audio questions 4/5 -> 5/5, word error and lag unchanged (BENCHMARKS.md).
    /// CLUELESS_CUT_SEARCH overrides it.
    public var forcedCutSearchSeconds: Double = {
        if let s = ProcessInfo.processInfo.environment["CLUELESS_CUT_SEARCH"], let v = Double(s), v >= 0, v <= 6 { return v }
        return 3.0
    }()

    public init(method: ChunkMethod) { self.method = method }

    public struct Chunk { public let samples: [Float]; public let startedAt: Date }

    public mutating func feed(_ samples: [Float], at now: Date = Date()) -> Chunk? {
        if buffer.isEmpty { startedAt = now }
        buffer.append(contentsOf: samples)
        let seconds = Double(buffer.count) / Double(Self.sampleRate)
        switch method {
        case .fixed(let limit):
            return seconds >= limit ? take() : nil
        case .silence(let minS, let maxS):
            if seconds >= maxS { return takeAtQuietest() }
            if seconds >= minS, Self.rms(buffer.suffix(Self.sampleRate / 5)) < silenceRMS { return take() }
            return nil
        }
    }

    /// Emit whatever is left (end of session).
    public mutating func flush() -> Chunk? { buffer.count > Self.sampleRate / 2 ? take() : nil }

    /// Forced cut, when nobody paused before the maximum length. Cutting at the very end splits whatever word
    /// is being said across two timeline lines. Instead, cut at the quietest 50 ms within the last
    /// `forcedCutSearchSeconds` (the gap between two words) and carry what follows into the next chunk.
    private mutating func takeAtQuietest() -> Chunk? {
        let window = Self.sampleRate / 20
        let search = Int(forcedCutSearchSeconds * Double(Self.sampleRate))
        // Keep at least a second before the search area, otherwise just cut at the end.
        guard search > window, buffer.count > search + Self.sampleRate else { return take() }
        var bestStart = buffer.count - window
        var bestRMS = Float.greatestFiniteMagnitude
        var i = buffer.count - search
        while i + window <= buffer.count {
            let level = Self.rms(buffer[i..<(i + window)])
            if level < bestRMS { bestRMS = level; bestStart = i }
            i += window / 2
        }
        let cut = bestStart + window / 2
        let rest = Array(buffer[cut...])
        let restStartedAt = (startedAt ?? Date()).addingTimeInterval(Double(cut) / Double(Self.sampleRate))
        buffer.removeSubrange(cut...)
        let chunk = take()            // emits the part before the cut and empties the buffer
        buffer = rest
        startedAt = restStartedAt
        return chunk
    }

    private mutating func take() -> Chunk? {
        defer { buffer.removeAll(keepingCapacity: true) }
        guard let startedAt else { return nil }
        // Skip chunks that are silent throughout: Whisper invents text on silence.
        guard Self.rms(buffer[...]) >= silenceRMS else { return nil }
        return Chunk(samples: buffer, startedAt: startedAt)
    }

    static func rms(_ s: ArraySlice<Float>) -> Float {
        guard !s.isEmpty else { return 0 }
        var sum: Float = 0
        for v in s { sum += v * v }
        return (sum / Float(s.count)).squareRoot()
    }
}

/// Argmax TTSKit, loaded once from the local models folder.
public final class Speaker: @unchecked Sendable {
    private let tts: TTSKit
    private let lock = NSLock()
    private var current: Task<Void, Never>?
    /// The last "stop the audio" that is still on its way. The next sentence waits for it, so a stop asked
    /// for just before can never cut off what is spoken after it.
    private var stopping: Task<Void, Never>?
    public private(set) var loadSeconds: Double = 0

    public init() async throws {
        let t0 = Date()
        tts = try await TTSKit(TTSKitConfig(
            model: .qwen3TTS_0_6b,
            modelFolder: Paths.ttsModels,
            tokenizerFolder: Paths.ttsTokenizer,
            verbose: false,
            download: false     // never fetch at run time: a missing file must fail here, not download quietly
        ))
        loadSeconds = Date().timeIntervalSince(t0)
    }

    /// Speak, cancelling anything already being spoken.
    public func say(_ text: String) {
        stop()
        let task = Task { [self] in _ = try? await self.sayAndWait(text) }
        setCurrent(task)
    }

    /// Stop at once: nothing more is generated, and what is already playing is cut off. Also stops a
    /// `sayAndWait` in progress, whoever called it (the app's speech queue does).
    public func stop() {
        takeCurrent()?.cancel()
        stopOutput()
    }

    /// Synthesize and play, returning seconds until done. Cancel the calling task to stop it: generation
    /// ends and the audio is cut off.
    public func sayAndWait(_ text: String) async throws -> Double {
        let t0 = Date()
        await pendingStop()?.value
        try Task.checkCancellation()
        let tts = self.tts
        _ = try await withTaskCancellationHandler {
            try await tts.play(text: text)
        } onCancel: { [self] in
            self.stopOutput()
        }
        return Date().timeIntervalSince(t0)
    }

    /// Cancelling the task that called `tts.play` only ends generation. TTSKit hands audio to its player
    /// ahead of time, and that audio went on playing to its end: after Option+S, and into the microphone
    /// while a spoken question was being recorded. So the player is stopped as well, the way TTSKit's own
    /// example app does it (cancel, then `stopPlayback(waitForCompletion: false)`).
    private func stopOutput() {
        let output = tts.audioOutput
        lock.lock(); defer { lock.unlock() }
        let previous = stopping
        stopping = Task {
            await previous?.value
            await output.stopPlayback(waitForCompletion: false)
        }
    }

    // The lock is only taken in these plain functions, never across an `await`.
    private func pendingStop() -> Task<Void, Never>? { lock.lock(); defer { lock.unlock() }; return stopping }
    private func setCurrent(_ task: Task<Void, Never>) { lock.lock(); defer { lock.unlock() }; current = task }
    private func takeCurrent() -> Task<Void, Never>? {
        lock.lock(); defer { lock.unlock() }
        let task = current
        current = nil
        return task
    }
}
