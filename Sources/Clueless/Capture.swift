import Foundation
import ScreenCaptureKit
import AVFoundation
import CoreMedia
import CluelessCore

/// Owns the one SCStream: system audio ("them") and microphone ("me"), both converted to 16 kHz mono Float32.
/// Screenshots are taken on demand, not from the stream.
final class Capture: NSObject, SCStreamOutput, SCStreamDelegate {
    enum Source { case system, mic }

    /// Called on `queue` with 16 kHz mono samples.
    var onAudio: ((Source, [Float]) -> Void)?
    var onStop: ((Error?) -> Void)?

    private var stream: SCStream?
    private var display: SCDisplay?
    private var ownApp: SCRunningApplication?
    private let queue = DispatchQueue(label: "clueless.capture")
    private var converters: [Source: (AVAudioFormat, AVAudioConverter)] = [:]
    private let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!

    func start(microphone: Bool) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
            throw NSError(domain: "Clueless", code: 1, userInfo: [NSLocalizedDescriptionKey: "No display found"])
        }
        self.display = display
        ownApp = content.applications.first { $0.processID == ProcessInfo.processInfo.processIdentifier }

        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let config = SCStreamConfiguration()
        // We only want audio from the stream. Keep video as cheap as the API allows.
        config.width = 2; config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true     // do not hear our own spoken answers
        config.sampleRate = 48_000
        config.channelCount = 1
        config.captureMicrophone = microphone

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        if microphone { try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: queue) }
        try await stream.startCapture()
        self.stream = stream
    }

    func stop() async {
        try? await stream?.stopCapture()
        stream = nil
    }

    /// Full-resolution screenshot of the main display, without our own windows
    /// (so the model reads the lecture, not our panel).
    func screenshot() async throws -> CGImage {
        guard let display else { throw NSError(domain: "Clueless", code: 2, userInfo: [NSLocalizedDescriptionKey: "Capture not started"]) }
        let filter = SCContentFilter(display: display, excludingApplications: ownApp.map { [$0] } ?? [], exceptingWindows: [])
        let config = SCStreamConfiguration()
        let scale = Int(filter.pointPixelScale)
        config.width = display.width * max(scale, 1)
        config.height = display.height * max(scale, 1)
        config.showsCursor = false
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    // MARK: SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        let source: Source
        switch type {
        case .audio: source = .system
        case .microphone: source = .mic
        default: return   // video frames are ignored
        }
        guard sampleBuffer.isValid, let samples = convert(sampleBuffer, source: source), !samples.isEmpty else { return }
        onAudio?(source, samples)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) { onStop?(error) }

    // MARK: conversion

    private func convert(_ sampleBuffer: CMSampleBuffer, source: Source) -> [Float]? {
        guard let desc = sampleBuffer.formatDescription,
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc),
              let format = AVAudioFormat(streamDescription: asbd) else { return nil }
        let frames = AVAudioFrameCount(sampleBuffer.numSamples)
        guard frames > 0, let input = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        input.frameLength = frames
        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(sampleBuffer, at: 0, frameCount: Int32(frames),
                                                           into: input.mutableAudioBufferList) == noErr else { return nil }

        // System audio and microphone have different formats and clocks: one converter each.
        if converters[source] == nil || converters[source]!.0 != format {
            guard let c = AVAudioConverter(from: format, to: target) else { return nil }
            converters[source] = (format, c)
        }
        let converter = converters[source]!.1
        let capacity = AVAudioFrameCount(Double(frames) * 16_000 / format.sampleRate) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }
        var fed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true; status.pointee = .haveData; return input
        }
        guard error == nil, let data = output.floatChannelData else { return nil }
        return Array(UnsafeBufferPointer(start: data[0], count: Int(output.frameLength)))
    }
}
