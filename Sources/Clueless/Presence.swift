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

    /// Not facing the screen for this long counts as away. Was 3 s: in the in-person test the app
    /// decided "away" too quickly to feel real (T50).
    var awayAfter: TimeInterval = 4.5
    /// Facing the screen again for this long counts as back.
    var backAfter: TimeInterval = 0.6

    private(set) var away = false
    /// Nothing counts as an absence until the user has been seen facing the screen once. Without this
    /// the seconds before the camera delivers its first usable frame looked like "away, then back".
    private var seen = false
    private var awayStart: Date?
    /// Start of the current run of observations that disagree with `away`.
    private var disagreeStart: Date?

    mutating func update(attending: Bool, at now: Date) -> Event? {
        if attending { seen = true }
        guard seen else { return nil }
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
    /// Called on the main queue for every analysed frame with the per-frame decision, before the
    /// debounce. The eye icon in the panel header follows it, so it agrees with the camera window (T50).
    var onLive: ((Bool) -> Void)?

    /// What one analysed frame looked like and what was decided from it. Only the camera test window
    /// (CameraTestView.swift) reads this; the look-away trigger itself uses `onEvent`.
    struct Frame {
        var at: Date
        /// Number of faces Vision found. Only the largest one is used.
        var faces: Int
        /// The largest face, in Vision coordinates (0 to 1, origin at the bottom left of the picture).
        var box: CGRect?
        /// Radians, signed, as Vision reports them. nil when there is no face or Vision gave no angle.
        var yaw: Double?
        var pitch: Double?
        /// The per-frame decision that goes into the tracker: head within the limit and, when eye
        /// direction counts (T48), eyes not turned away.
        var attending: Bool
        /// The head-only part of that decision (the whole decision before T48).
        var headAttending: Bool
        /// True when eye direction was allowed to change the decision for this frame.
        var eyesCount: Bool
        /// The tracker's debounced state after this frame.
        var away: Bool
        var event: PresenceTracker.Event?
        var maxAngle: Double
        /// Pixel size of the analysed picture, to place `box` over a preview.
        var imageSize: CGSize
        /// Eye landmarks and gaze estimate; nil when they were not measured for this frame or Vision
        /// found no landmarks.
        var eyes: EyeGaze?
    }
    /// Called on the main queue for every analysed frame (about 3 a second) while the camera runs.
    var onFrame: ((Frame) -> Void)?
    /// For a live preview layer in the camera test window. Nothing else may touch the session.
    var previewSession: AVCaptureSession { session }

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
    private var trackEyes = false
    private var eyesCount = false

    /// Camera window: measure the eyes on every analysed frame so the tracking view can draw them,
    /// whether or not they count for the decision.
    func setEyeTracking(_ on: Bool) { queue.async { self.trackEyes = on } }

    /// T48: when on, a frame whose eyes are turned sideways or up / down is not attending even if the
    /// head faces the screen. Off gives the head-only rule. Set by AppState (menu toggle, CLUELESS_EYES=0).
    func setEyesCount(_ on: Bool) {
        queue.async {
            guard self.eyesCount != on else { return }
            self.eyesCount = on
            Log.write("[presence] eye direction " + (on ? "counts as looking away" : "is not used"))
        }
    }

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
        var headAttending = false
        if let face {
            let yaw = abs(face.yaw?.doubleValue ?? 0), pitch = abs(face.pitch?.doubleValue ?? 0)
            headAttending = yaw < maxAngle && pitch < maxAngle
        }
        // Eyes: measured when they can change the decision (the head is within the limit) or when the
        // camera window wants to draw them. Closed eyes and missing landmarks leave the head-only rule.
        var eyes: EyeGaze?
        if let face, trackEyes || (eyesCount && headAttending) {
            eyes = EyeGaze.measure(face: face, in: pixels)
        }
        var attending = headAttending
        if eyesCount, let eyes, eyes.lookingAway { attending = false }
        let event = tracker.update(attending: attending, at: now)
        let status: Status = tracker.away ? .away : .present
        let frame = Frame(at: now, faces: request.results?.count ?? 0, box: face?.boundingBox,
                          yaw: face?.yaw?.doubleValue, pitch: face?.pitch?.doubleValue,
                          attending: attending, headAttending: headAttending, eyesCount: eyesCount,
                          away: tracker.away, event: event, maxAngle: maxAngle,
                          imageSize: CGSize(width: CVPixelBufferGetWidth(pixels), height: CVPixelBufferGetHeight(pixels)),
                          eyes: eyes)
        DispatchQueue.main.async {
            self.onFrame?(frame)
            self.onLive?(attending)
            guard let event else { return }
            self.onStatus?(status)
            self.onEvent?(event)
        }
    }
}
