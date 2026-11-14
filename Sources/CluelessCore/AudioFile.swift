import Foundation
import AVFoundation

public enum AudioFile {
    /// Read any audio file as 16 kHz mono Float32.
    public static func load16k(_ path: String) throws -> [Float] {
    let file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
    let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
    let inBuf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
    try file.read(into: inBuf)
    let converter = AVAudioConverter(from: file.processingFormat, to: format)!
    let cap = AVAudioFrameCount(Double(file.length) * 16_000 / file.processingFormat.sampleRate) + 1024
    let outBuf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: cap)!
    var fed = false
    var err: NSError?
    converter.convert(to: outBuf, error: &err) { _, status in
        if fed { status.pointee = .endOfStream; return nil }
        fed = true; status.pointee = .haveData; return inBuf
    }
    if let err { throw err }
    return Array(UnsafeBufferPointer(start: outBuf.floatChannelData![0], count: Int(outBuf.frameLength)))
}
}
