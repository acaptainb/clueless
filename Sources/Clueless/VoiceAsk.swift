import Foundation
import AVFoundation
import CluelessCore

/// Records one spoken question from the microphone. The audio stays in memory and is handed to
/// Argmax WhisperKit; nothing is saved. Recording ends by itself after a pause.
final class VoiceRecorder {
    /// Called on the main queue when the recording should end (a pause after speech, or a time limit).
    /// It can be called more than once; the receiver decides.
    var onAutoStop: (() -> Void)?

    /// Louder than this counts as speech (RMS of one buffer).
    private let speechLevel: Float = 0.015
    /// Stop this long after the last speech.
    private let pauseSeconds: TimeInterval = 1.4
    /// Give up if nothing is said for this long, and never record longer than `maxSeconds`.
    private let silenceSeconds: TimeInterval = 6
    private let maxSeconds: TimeInterval = 20

    private let engine = AVAudioEngine()
    private let lock = NSLock()
    // Guarded by `lock`: written on the audio thread, read on the main thread.
    private var samples: [Float] = []
    private var heardSpeech = false
    private var lastSpeech = Date()
    private var startedAt = Date()
    private var rate: Double = 48_000
    private var running = false

    func start() throws {
        let input = engine.inputNode
        // Echo cancellation, so the lecture playing through the speakers is not transcribed as the question.
        try? input.setVoiceProcessingEnabled(true)
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw NSError(domain: "Clueless", code: 3, userInfo: [NSLocalizedDescriptionKey: "No microphone found"])
        }
        lock.lock()
        samples = []; heardSpeech = false; startedAt = Date(); lastSpeech = Date(); rate = format.sampleRate
        lock.unlock()
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in self?.take(buffer) }
        engine.prepare()
        try engine.start()
        running = true
    }

    /// Stops and returns the recording as 16 kHz mono, or nothing if no speech was heard.
    func stop() -> [Float] {
        guard running else { return [] }
        running = false
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? engine.inputNode.setVoiceProcessingEnabled(false)
        lock.lock()
        let raw = samples, heard = heardSpeech, rate = rate
        samples = []
        lock.unlock()
        return heard ? Self.resample(raw, from: rate) : []
    }

    private func take(_ buffer: AVAudioPCMBuffer) {
        guard let data = buffer.floatChannelData else { return }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return }
        let chunk = UnsafeBufferPointer(start: data[0], count: count)
        var sum: Float = 0
        for v in chunk { sum += v * v }
        let level = (sum / Float(count)).squareRoot()
        let now = Date()
        lock.lock()
        samples.append(contentsOf: chunk)
        if level > speechLevel { heardSpeech = true; lastSpeech = now }
        let done = (heardSpeech && now.timeIntervalSince(lastSpeech) > pauseSeconds)
            || (!heardSpeech && now.timeIntervalSince(startedAt) > silenceSeconds)
            || now.timeIntervalSince(startedAt) > maxSeconds
        lock.unlock()
        if done { DispatchQueue.main.async { self.onAutoStop?() } }
    }

    private static func resample(_ input: [Float], from rate: Double) -> [Float] {
        guard !input.isEmpty,
              let from = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false),
              let to = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: from, to: to),
              let source = AVAudioPCMBuffer(pcmFormat: from, frameCapacity: AVAudioFrameCount(input.count)),
              let sourceData = source.floatChannelData else { return [] }
        source.frameLength = AVAudioFrameCount(input.count)
        input.withUnsafeBufferPointer { sourceData[0].update(from: $0.baseAddress!, count: input.count) }
        let capacity = AVAudioFrameCount(Double(input.count) * 16_000 / rate) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: to, frameCapacity: capacity) else { return [] }
        var fed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if fed { status.pointee = .endOfStream; return nil }
            fed = true; status.pointee = .haveData; return source
        }
        guard error == nil, let data = output.floatChannelData else { return [] }
        return Array(UnsafeBufferPointer(start: data[0], count: Int(output.frameLength)))
    }
}
