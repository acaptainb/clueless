import AppKit
import SwiftUI
import AVFoundation
import CluelessCore

// Camera window (T31, made a demo window in T48). It never opens by itself: open it with the camera button
// in the panel header, from the "…" menu, or launch with CLUELESS_CAMERA_TEST=1.
// Normal view: the live webcam picture and one label, Focused / Distracted / No person.
// Tracking view (the eye button): also the face Vision picked, the eye outlines and pupils, and the numbers
// behind the decision. The label is the per-frame decision the look-away trigger uses (head angle and,
// unless turned off, eye direction: EyeGaze.swift), so the window and the trigger always agree.
// It reads the frames of the same `Presence` object the trigger uses, so there is no second detector.
// Apple Vision face detection only; nothing is saved or sent. The window is not hidden from screen sharing.

/// What the window shows in big letters.
enum CameraTestState: Equatable {
    case unavailable, waiting, noPerson, distracted, focused

    var title: String {
        switch self {
        case .unavailable: return "Camera unavailable"
        case .waiting: return "Waiting for the camera…"
        case .noPerson: return "No person"
        case .distracted: return "Distracted"
        case .focused: return "Focused"
        }
    }

    var color: NSColor {
        switch self {
        case .unavailable, .waiting, .noPerson: return .systemGray
        case .distracted: return .systemOrange
        case .focused: return .systemGreen
        }
    }

    init(frame: Presence.Frame) {
        if frame.faces == 0 { self = .noPerson } else { self = frame.attending ? .focused : .distracted }
    }
}

@MainActor
final class CameraTestModel: ObservableObject {
    @Published var frame: Presence.Frame?
    @Published var frames = 0
    @Published var lastEvent = "none yet"
    /// When the per-frame state (focused / distracted / no person) last changed.
    @Published var rawSince = Date()
    /// When the tracker last switched between present and away.
    @Published var trackerSince = Date()
    /// false = normal view (picture and one label), true = tracking view (overlays and numbers).
    /// Lives here and not in `@State`: `@State` does not compile on the Mac mini (no Xcode).
    @Published var tracking = false
    /// Set by the window, which changes its size to fit the view.
    var onTracking: (@MainActor (Bool) -> Void)?

    func toggleTracking() {
        tracking.toggle()
        onTracking?(tracking)
    }

    func ingest(_ new: Presence.Frame) {
        if let old = frame {
            if CameraTestState(frame: old) != CameraTestState(frame: new) { rawSince = new.at }
            if old.away != new.away { trackerSince = new.at }
        } else {
            rawSince = new.at; trackerSince = new.at
        }
        if let event = new.event {
            let clock = DateFormatter.localizedString(from: new.at, dateStyle: .none, timeStyle: .medium)
            switch event {
            case .left: lastEvent = "left (\(clock))"
            case .returned(let seconds, _): lastEvent = "returned after \(String(format: "%.1f", seconds)) s (\(clock))"
            }
        }
        frame = new
        frames += 1
    }
}

struct CameraTestView: View {
    @ObservedObject var state: AppState
    @ObservedObject var model: CameraTestModel

    var body: some View {
        // Redrawn twice a second as well as on every frame, so the timers run and a stalled camera shows.
        TimelineView(.periodic(from: Date(), by: 0.5)) { context in
            content(now: context.date)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func current(now: Date) -> CameraTestState {
        if state.presence == .unavailable { return .unavailable }
        guard let frame = model.frame, now.timeIntervalSince(frame.at) < 2 else { return .waiting }
        return CameraTestState(frame: frame)
    }

    private func content(now: Date) -> some View {
        let shown = current(now: now)
        let frame = shown == .waiting || shown == .unavailable ? nil : model.frame
        let tracking = model.tracking
        let shape = RoundedRectangle(cornerRadius: Style.tileRadius, style: .continuous)
        return HStack(alignment: .top, spacing: Style.padding) {
            VStack(spacing: 0) {
                // Normal view: the picture only. The face box and the eyes are drawn in the tracking view.
                // The border follows the state; the state label is a glass pill over the bottom of the picture.
                CameraPreview(session: state.webcam.previewSession, box: tracking ? frame?.box : nil,
                              eyes: tracking ? frame?.eyes : nil,
                              imageSize: frame?.imageSize ?? .zero, color: shown.color)
                    .aspectRatio(4.0 / 3.0, contentMode: .fit)
                    .clipShape(shape)
                    .overlay(shape.stroke(Color(nsColor: shown.color), lineWidth: 3))
                    .overlay(alignment: .bottom) { statePill(shown).padding(.bottom, 10) }
                    .overlay(alignment: .topTrailing) { viewButton.padding(8) }
                Spacer(minLength: 0)
            }
            if tracking {
                VStack(alignment: .leading, spacing: 8) {
                    if shown == .unavailable {
                        Text("Allow Camera for Clueless in System Settings › Privacy & Security, then reopen this window.")
                            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    if let frame, frame.faces > 1 {
                        Text("\(frame.faces) faces visible. Only the largest (boxed) is used.")
                            .font(.callout.bold()).foregroundStyle(Style.warning).fixedSize(horizontal: false, vertical: true)
                    }
                    if let frame, frame.faces > 0 { eyeLabel(frame) }
                    numbers(frame: frame, now: now)
                    Spacer(minLength: 0)
                    Text("Apple Vision face detection on this Mac; nothing is saved or sent.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .padding(Style.tilePadding)
                .frame(width: 300)
                .glass()
            }
        }
        .padding(10)
        .background(PanelBackground())
    }

    /// The one large label: a glass pill tinted with the state colour.
    private func statePill(_ shown: CameraTestState) -> some View {
        Text(shown.title)
            .font(Style.stateLabel)
            .foregroundStyle(.white)
            .shadow(color: Color.black.opacity(0.5), radius: 2)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 16).padding(.vertical, 7)
            .glass(cornerRadius: 20, tint: Color(nsColor: shown.color))
            .padding(.horizontal, 10)
    }

    /// The eye button: switches between the normal and the tracking view.
    private var viewButton: some View {
        Button(action: model.toggleTracking) { Image(systemName: model.tracking ? "eye.fill" : "eye") }
            .buttonStyle(GlassIconButtonStyle(symbol: model.tracking ? Style.accent : nil))
            .help(model.tracking ? "Hide the tracking details" : "Show the tracking details: face box, eyes and numbers")
    }

    private func numbers(frame: Presence.Frame?, now: Date) -> some View {
        let limit = frame?.maxAngle
        let defaults = PresenceTracker()
        return VStack(alignment: .leading, spacing: 5) {
            row("Yaw (left / right)", degrees(frame?.yaw), over: isOver(frame?.yaw, limit))
            row("Pitch (up / down)", degrees(frame?.pitch), over: isOver(frame?.pitch, limit))
            row("Limit (maxAngle)", limit.map { String(format: "±%.0f° (%.2f rad)", $0 * 180 / .pi, $0) } ?? "–")
            row("Faces found", frame.map { "\($0.faces)" } ?? "–")
            row("Head alone", frame.map { $0.headAttending ? "facing the screen" : "not facing" } ?? "–")
            row("Eye direction", state.eyesCount ? "counts as looking away"
                : AppState.eyesForcedOff ? "not used (CLUELESS_EYES=0)" : "not used (setting off)")
            row("This frame counts as", frame.map { $0.attending ? "focused" : "not focused" } ?? "–")
            row("  for", frame == nil ? "–" : seconds(now.timeIntervalSince(model.rawSince)))
            Divider()
            row("Tracker (debounced)", frame.map { $0.away ? "AWAY" : "present" } ?? "–", over: frame?.away == true)
            row("  for", frame == nil ? "–" : seconds(now.timeIntervalSince(model.trackerSince)))
            row("Away after / back after", String(format: "%.1f s / %.1f s", defaults.awayAfter, defaults.backAfter))
            row("Last event", model.lastEvent)
            Divider()
            row("Eyes left / right", signed(frame?.eyes?.horizontal),
                over: isOver(frame?.eyes?.horizontal, EyeGaze.horizontalLimit))
            row("Eyes up / down", signed(frame?.eyes?.vertical),
                over: isOver(frame?.eyes?.vertical, EyeGaze.verticalLimit))
            row("Eye limits (left-right / up-down)",
                String(format: "±%.2f / ±%.2f", EyeGaze.horizontalLimit, EyeGaze.verticalLimit))
            row("Eye openness (closed below)",
                (frame?.eyes?.openness).map { String(format: "%.2f (%.2f)", $0, EyeGaze.closedBelow) } ?? "–",
                over: (frame?.eyes?.openness ?? 1) < EyeGaze.closedBelow)
            Divider()
            row("Frames analysed", "\(model.frames)")
            row("\"Look away\" setting", state.lookAway ? "on" : "off (no cards)")
            row("Capture", state.recording ? "recording" : "paused (no cards)")
        }
    }

    private func row(_ name: String, _ value: String, over: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(name).font(.callout).foregroundStyle(.secondary)
            Spacer(minLength: 6)
            Text(value).font(.callout.monospacedDigit().weight(over ? .bold : .regular))
                .foregroundStyle(over ? Style.warning : Color.primary)
                .multilineTextAlignment(.trailing)
        }
    }

    /// Second, smaller label: what the eyes are doing, and whether that counts for the decision.
    private func eyeLabel(_ frame: Presence.Frame) -> some View {
        let eyes = frame.eyes
        let verdict = eyes?.verdict ?? .unknown
        let text: String
        let color: NSColor
        switch verdict {
        case .onScreen: text = "Eyes: on the screen"; color = .systemGreen
        case .sideways:
            text = (eyes?.horizontal ?? 0) < 0 ? "Eyes: turned to picture left" : "Eyes: turned to picture right"
            color = .systemOrange
        case .upOrDown:
            text = (eyes?.vertical ?? 0) < 0 ? "Eyes: looking down" : "Eyes: looking up"
            color = .systemOrange
        case .closed: text = "Eyes: closed"; color = .systemRed
        case .unknown: text = "Eyes: not found"; color = .systemGray
        }
        return Text(text + (frame.eyesCount ? "" : "  (not counted)"))
            .font(.callout.bold())
            .foregroundStyle(Color(nsColor: color))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func signed(_ value: Double?) -> String {
        guard let value else { return "–" }
        return String(format: "%+.2f", value)
    }

    private func degrees(_ radians: Double?) -> String {
        guard let radians else { return "–" }
        return String(format: "%+.0f°", radians * 180 / .pi)
    }

    private func isOver(_ radians: Double?, _ limit: Double?) -> Bool {
        guard let radians, let limit else { return false }
        return abs(radians) >= limit
    }

    private func seconds(_ interval: TimeInterval) -> String { String(format: "%.1f s", max(0, interval)) }
}

/// Live camera picture with the face box on top.
struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    var box: CGRect?
    var eyes: EyeGaze?
    var imageSize: CGSize
    var color: NSColor

    func makeNSView(context: Context) -> CameraPreviewView { CameraPreviewView(session: session) }

    func updateNSView(_ view: CameraPreviewView, context: Context) {
        view.show(box: box, eyes: eyes, imageSize: imageSize, color: color)
    }
}

final class CameraPreviewView: NSView {
    private let preview: AVCaptureVideoPreviewLayer
    private let boxLayer = CAShapeLayer()
    private let eyeLayer = CAShapeLayer()     // eye outlines
    private let pupilLayer = CAShapeLayer()   // pupil dots
    private var eyes: EyeGaze?
    private var box: CGRect?
    private var imageSize = CGSize.zero

    init(session: AVCaptureSession) {
        preview = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: .zero)
        let root = CALayer()
        root.backgroundColor = NSColor.black.cgColor
        preview.videoGravity = .resizeAspect
        boxLayer.fillColor = nil
        boxLayer.lineWidth = 3
        root.addSublayer(preview)
        root.addSublayer(boxLayer)
        eyeLayer.fillColor = nil
        eyeLayer.lineWidth = 1.5
        eyeLayer.strokeColor = NSColor.systemYellow.cgColor
        pupilLayer.fillColor = NSColor.systemRed.cgColor
        root.addSublayer(eyeLayer)
        root.addSublayer(pupilLayer)
        layer = root
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layout() {
        super.layout()
        redraw()
    }

    func show(box: CGRect?, eyes: EyeGaze?, imageSize: CGSize, color: NSColor) {
        self.box = box
        self.eyes = eyes
        self.imageSize = imageSize
        boxLayer.strokeColor = color.cgColor
        redraw()
    }

    private func redraw() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)   // no implicit animation: the box must not lag the face
        defer { CATransaction.commit() }
        preview.frame = bounds
        boxLayer.frame = bounds
        eyeLayer.frame = bounds
        pupilLayer.frame = bounds
        eyeLayer.path = nil
        pupilLayer.path = nil
        guard let box, imageSize.width > 0, imageSize.height > 0, bounds.width > 0, bounds.height > 0 else {
            boxLayer.path = nil
            return
        }
        // Where the picture sits inside the view (aspect fit), then the Vision box inside the picture.
        // Vision and this layer both count from the bottom left, so no flip is needed.
        let picture = AVMakeRect(aspectRatio: imageSize, insideRect: bounds)
        let rect = CGRect(x: picture.minX + box.minX * picture.width,
                          y: picture.minY + box.minY * picture.height,
                          width: box.width * picture.width, height: box.height * picture.height)
        boxLayer.path = CGPath(rect: rect, transform: nil)
        guard let eyes else { return }
        func place(_ p: CGPoint) -> CGPoint {
            CGPoint(x: picture.minX + p.x * picture.width, y: picture.minY + p.y * picture.height)
        }
        let outlines = CGMutablePath()
        for outline in [eyes.leftEye, eyes.rightEye] where outline.count > 1 {
            outlines.addLines(between: outline.map(place))
            outlines.closeSubpath()
        }
        eyeLayer.path = outlines
        let dots = CGMutablePath()
        for pupil in [eyes.leftPupil, eyes.rightPupil] {
            guard let pupil else { continue }
            let c = place(pupil)
            dots.addEllipse(in: CGRect(x: c.x - 3, y: c.y - 3, width: 6, height: 6))
        }
        pupilLayer.path = dots
    }
}

/// Owns the window. One at a time.
@MainActor
final class CameraTestWindow: NSObject, NSWindowDelegate {
    static var current: CameraTestWindow?

    private let window: NSWindow
    private let model: CameraTestModel
    private weak var state: AppState?
    private(set) var closed = false

    /// Content sizes: the normal view is a 320 x 240 picture with the label on it; the tracking view adds the numbers.
    static let normalSize = NSSize(width: 340, height: 260)
    static let trackingSize = NSSize(width: 790, height: 600)

    init(state: AppState) {
        self.state = state
        model = CameraTestModel()
        window = NSWindow(contentRect: NSRect(origin: .zero, size: CameraTestWindow.normalSize),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        super.init()
        window.title = "Clueless camera"
        window.isReleasedWhenClosed = false
        // Stays above other windows like the panel, so it can sit beside it during a recording.
        window.level = .floating
        window.appearance = NSAppearance(named: .darkAqua)   // T49: dark like the panel
        // Deliberately NOT hidden from screen sharing: sharingType stays at its default.
        window.delegate = self
        let hosting = NSHostingView(rootView: CameraTestView(state: state, model: model))
        // The window decides its own size (two fixed sizes, below); the content fills whatever it gets.
        hosting.sizingOptions = []
        window.contentView = hosting
        window.center()
        let sink = model
        state.webcam.onFrame = { [weak sink] frame in sink?.ingest(frame) }
        model.onTracking = { [weak self] on in self?.resize(tracking: on) }
        state.webcam.setEyeTracking(true)   // draw the eyes while this window is open, even if they do not count
        state.cameraTest = true   // turns the webcam on even when capture is paused
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Resize for the view, keeping the top left corner where it is.
    private func resize(tracking: Bool) {
        let size = tracking ? CameraTestWindow.trackingSize : CameraTestWindow.normalSize
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        frame.origin = NSPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
        window.setFrame(frame, display: true)
    }

    /// Close exactly as the red button does. Used by the CLUELESS_CAMERA_TEST_CLOSE test hook.
    func closeLikeTheButton() { window.performClose(nil) }

    func windowWillClose(_ notification: Notification) {
        closed = true
        state?.webcam.onFrame = nil
        state?.webcam.setEyeTracking(false)
        state?.cameraTest = false   // the webcam goes back to following recording + the look-away setting
        // Let the close finish before the window is released.
        DispatchQueue.main.async { if CameraTestWindow.current === self { CameraTestWindow.current = nil } }
    }
}

extension AppState {
    func openCameraTest() {
        if CameraTestWindow.current?.closed != false { CameraTestWindow.current = CameraTestWindow(state: self) }
        CameraTestWindow.current?.show()
    }

    /// Buttons under the question field (T50).
    func toggleSpeak() {
        objectWillChange.send()   // make sure the button redraws: the value lives in @AppStorage
        speak.toggle()
        if !speak { stopSpeaking() }
    }

    func toggleShowReply() {
        objectWillChange.send()
        showReply.toggle()
    }

    /// The camera button in the panel header: opens the window, or closes it if it is open.
    func toggleCameraWindow() {
        if let open = CameraTestWindow.current, !open.closed { open.closeLikeTheButton() } else { openCameraTest() }
    }
}
