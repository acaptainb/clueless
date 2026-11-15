import AppKit
import SwiftUI
import AVFoundation
import CluelessCore

// Camera test window (T31). FOR TESTING ONLY: it never opens by itself. Open it from the "…" menu or
// launch with CLUELESS_CAMERA_TEST=1. It shows what the look-away trigger sees: the live webcam
// picture, the face Vision picked, the per-frame decision and the debounced tracker state.
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
        case .distracted: return "Distracted / looking away"
        case .focused: return "Focused"
        }
    }

    var color: NSColor {
        switch self {
        case .unavailable, .waiting: return .systemGray
        case .noPerson: return .systemRed
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
        .frame(minWidth: 760, minHeight: 400)
    }

    private func current(now: Date) -> CameraTestState {
        if state.presence == .unavailable { return .unavailable }
        guard let frame = model.frame, now.timeIntervalSince(frame.at) < 2 else { return .waiting }
        return CameraTestState(frame: frame)
    }

    private func content(now: Date) -> some View {
        let shown = current(now: now)
        let frame = shown == .waiting || shown == .unavailable ? nil : model.frame
        return HStack(alignment: .top, spacing: 14) {
            CameraPreview(session: state.webcam.previewSession, box: frame?.box,
                          imageSize: frame?.imageSize ?? .zero, color: shown.color)
                .frame(minWidth: 440, minHeight: 330)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 8) {
                Text(shown.title)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: shown.color)))
                    .fixedSize(horizontal: false, vertical: true)
                if shown == .unavailable {
                    Text("Allow Camera for Clueless in System Settings › Privacy & Security, then reopen this window.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                if let frame, frame.faces > 1 {
                    Text("\(frame.faces) faces visible. Only the largest (boxed) is used.")
                        .font(.callout.bold()).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
                Divider()
                numbers(frame: frame, now: now)
                Spacer(minLength: 0)
                Text("Testing only. Apple Vision face detection on this Mac; nothing is saved or sent.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 290)
        }
        .padding(14)
    }

    private func numbers(frame: Presence.Frame?, now: Date) -> some View {
        let limit = frame?.maxAngle
        let defaults = PresenceTracker()
        return VStack(alignment: .leading, spacing: 5) {
            row("Yaw (left / right)", degrees(frame?.yaw), over: isOver(frame?.yaw, limit))
            row("Pitch (up / down)", degrees(frame?.pitch), over: isOver(frame?.pitch, limit))
            row("Limit (maxAngle)", limit.map { String(format: "±%.0f° (%.2f rad)", $0 * 180 / .pi, $0) } ?? "–")
            row("Faces found", frame.map { "\($0.faces)" } ?? "–")
            row("This frame counts as", frame.map { $0.attending ? "facing the screen" : "not facing" } ?? "–")
            row("  for", frame == nil ? "–" : seconds(now.timeIntervalSince(model.rawSince)))
            Divider()
            row("Tracker (debounced)", frame.map { $0.away ? "AWAY" : "present" } ?? "–", over: frame?.away == true)
            row("  for", frame == nil ? "–" : seconds(now.timeIntervalSince(model.trackerSince)))
            row("Away after / back after", String(format: "%.1f s / %.1f s", defaults.awayAfter, defaults.backAfter))
            row("Last event", model.lastEvent)
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
                .foregroundStyle(over ? Color.orange : Color.primary)
                .multilineTextAlignment(.trailing)
        }
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
    var imageSize: CGSize
    var color: NSColor

    func makeNSView(context: Context) -> CameraPreviewView { CameraPreviewView(session: session) }

    func updateNSView(_ view: CameraPreviewView, context: Context) {
        view.show(box: box, imageSize: imageSize, color: color)
    }
}

final class CameraPreviewView: NSView {
    private let preview: AVCaptureVideoPreviewLayer
    private let boxLayer = CAShapeLayer()
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
        layer = root
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layout() {
        super.layout()
        redraw()
    }

    func show(box: CGRect?, imageSize: CGSize, color: NSColor) {
        self.box = box
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

    init(state: AppState) {
        self.state = state
        model = CameraTestModel()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 420),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        super.init()
        window.title = "Clueless camera test (testing only)"
        window.isReleasedWhenClosed = false
        // Deliberately NOT hidden from screen sharing: sharingType stays at its default.
        window.delegate = self
        window.contentView = NSHostingView(rootView: CameraTestView(state: state, model: model))
        window.center()
        let sink = model
        state.webcam.onFrame = { [weak sink] frame in sink?.ingest(frame) }
        state.cameraTest = true   // turns the webcam on even when capture is paused
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        closed = true
        state?.webcam.onFrame = nil
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
}
