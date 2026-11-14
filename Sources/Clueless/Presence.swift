import Foundation
import AVFoundation
import Vision
import CluelessCore

/// Turns a stream of "is the user facing the screen?" observations into two events: the user left,
/// and the user came back. Short glances and single missed frames are ignored.
struct PresenceTracker {
    enum Event: Equatable {
        case left(at: Date)
        /// `since` is when the user stopped facing the screen.
        case returned(awaySeconds: TimeInterval, since: Date)
    }

    /// Not facing the screen for this long counts as away.
    var awayAfter: TimeInterval = 3
    /// Facing the screen again for this long counts as back.
    var backAfter: TimeInterval = 0.6

    private(set) var away = false
    private var awayStart: Date?
    /// Start of the current run of observations that disagree with `away`.
    private var disagreeStart: Date?

    mutating func update(attending: Bool, at now: Date) -> Event? {
        if attending != away { disagreeStart = nil; return nil }   // observation matches the state
        let start = disagreeStart ?? now
        disagreeStart = start
        let held = now.timeIntervalSince(start)
        if !away, held >= awayAfter {
            away = true; awayStart = start; disagreeStart = nil
            return .left(at: start)
        }
        if away, held >= backAfter {
            away = false; disagreeStart = nil
            let since = awayStart ?? start
            return .returned(awaySeconds: start.timeIntervalSince(since), since: since)
        }
        return nil
    }
}

/// Webcam presence: a few frames per second go through Apple Vision face detection (not a language
/// model). Frames are analysed in memory and dropped; nothing is saved or sent anywhere.
final class Presence: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    enum Status: Equatable { case off, present, away, unavailable }

    /// Both are called on the main queue.
    var onStatus: ((Status) -> Void)?
    var onEvent: ((PresenceTracker.Event) -> Void)?

    /// Head turned or tilted further than this (radians, about 30 degrees) is not facing the screen.
    private let maxAngle: Double = 0.52
    /// Seconds between analysed frames.
    private let frameInterval: TimeInterval = 0.3

    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "clueless.presence")
    private let request = VNDetectFaceRectanglesRequest()
    // Everything below is touched on `queue` only.
    private var tracker = PresenceTracker()
    private var configured = false
    private var wanted = false
    private var lastFrame = Date.distantPast

    func start() {
        queue.async { self.wanted = true }
        AVCaptureDevice.requestAccess(for: .video) { granted in
            self.queue.async {
                guard self.wanted else { return }
                guard granted, self.configure() else {
                    Log.write("[presence] camera unavailable (granted: \(granted))")
                    self.report(.unavailable)
                    return
                }
                self.tracker = PresenceTracker()
                self.lastFrame = .distantPast
                if !self.session.isRunning { self.session.startRunning() }
                self.report(.present)
                Log.write("[presence] camera started")
            }
        }
    }

    func stop() {
        queue.async {
            self.wanted = false
            if self.session.isRunning { self.session.stopRunning() }
            self.report(.off)
        }
    }

    private func configure() -> Bool {
        if configured { return true }
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else { return false }
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        // Face detection does not need more than VGA, and small frames keep the CPU cost low.
        if session.canSetSessionPreset(.vga640x480) { session.sessionPreset = .vga640x480 }
        guard session.canAddInput(input), session.canAddOutput(output) else { return false }
        session.addInput(input)
        session.addOutput(output)
        configured = true
        return true
    }

    private func report(_ status: Status) {
        DispatchQueue.main.async { self.onStatus?(status) }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        let now = Date()
        guard wanted, now.timeIntervalSince(lastFrame) >= frameInterval,
              let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastFrame = now
        let handler = VNImageRequestHandler(cvPixelBuffer: pixels, orientation: .up, options: [:])
        guard (try? handler.perform([request])) != nil else { return }
        // The largest face is the person at the keyboard.
        let face = (request.results ?? []).max {
            $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height
        }
        var attending = false
        if let face {
            let yaw = abs(face.yaw?.doubleValue ?? 0), pitch = abs(face.pitch?.doubleValue ?? 0)
            attending = yaw < maxAngle && pitch < maxAngle
        }
        guard let event = tracker.update(attending: attending, at: now) else { return }
        let status: Status = tracker.away ? .away : .present
        DispatchQueue.main.async {
            self.onStatus?(status)
            self.onEvent?(event)
        }
    }
}
