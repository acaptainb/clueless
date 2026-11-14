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
            if seconds >= maxS { return take() }
            if seconds >= minS, Self.rms(buffer.suffix(Self.sampleRate / 5)) < silenceRMS { return take() }
            return nil
        }
    }

    /// Emit whatever is left (end of session).
    public mutating func flush() -> Chunk? { buffer.count > Self.sampleRate / 2 ? take() : nil }

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
    private var current: Task<Void, Never>?
    public private(set) var loadSeconds: Double = 0

    public init() async throws {
        let t0 = Date()
        tts = try await TTSKit(TTSKitConfig(
            model: .qwen3TTS_0_6b,
            modelFolder: Paths.ttsModels,
            tokenizerFolder: Paths.ttsTokenizer,
            verbose: false
        ))
        loadSeconds = Date().timeIntervalSince(t0)
    }

    /// Speak, cancelling anything already being spoken.
    public func say(_ text: String) {
        current?.cancel()
        let tts = self.tts
        current = Task { _ = try? await tts.play(text: text) }
    }

    public func stop() { current?.cancel() }

    /// For benchmarks: synthesize and play, returning seconds until done.
    public func sayAndWait(_ text: String) async throws -> Double {
        let t0 = Date()
        _ = try await tts.play(text: text)
        return Date().timeIntervalSince(t0)
    }
}
