import AppKit
import SwiftUI
import Carbon.HIToolbox
import CluelessCore

@main
enum Main {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
}

/// Floating panel that can take keyboard focus for the question field.
final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: OverlayPanel!
    private var state: AppState!
    private var hotKeys: [HotKey] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        state = AppState()
        panel = OverlayPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 420),
                             styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        panel.title = "Clueless"
        panel.titlebarAppearsTransparent = true
        // T49, visual only: the name is a wordmark in the panel header, and the panel is always dark so
        // text stays readable over the blurred desktop behind it.
        panel.titleVisibility = .hidden
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        // Deliberately NOT hidden from screen sharing: sharingType stays at its default.
        panel.contentView = NSHostingView(rootView: OverlayView(state: state, onHeight: { [weak self] height in
            // Not during the layout pass that measured it.
            DispatchQueue.main.async { self?.fitPanel(toContentHeight: height) }
        }))
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: f.maxX - 440, y: f.maxY - 460))
        }
        panel.orderFrontRegardless()
        installMainMenu()
        // Test hook: CLUELESS_CAMERA_TEST=1 opens the camera test window at launch (CameraTestView.swift).
        if ProcessInfo.processInfo.environment["CLUELESS_CAMERA_TEST"] == "1" { state.openCameraTest() }
        // Test hook: CLUELESS_TEST_T41=<seconds> exercises three T41 fixes with nobody at the Mac (TestHooks.swift).
        state.runT41TestIfAsked()
        // Pay for the slow first screenshot of a launch before the first card needs it (Warmup.swift).
        state.warmUpScreenWhenReady()
        // Test hook: CLUELESS_CAMERA_TEST_CLOSE=<seconds> closes that window again after a delay, the way the
        // red button does, so "closing it must not quit the app" can be checked with nobody at the Mac.
        if let s = ProcessInfo.processInfo.environment["CLUELESS_CAMERA_TEST_CLOSE"], let seconds = Double(s) {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
                Log.write("[camera test] closing the window (test hook)")
                CameraTestWindow.current?.closeLikeTheButton()
            }
        }

        // Global hotkeys (Carbon: no Accessibility permission needed).
        hotKeys = [
            HotKey(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey)) { [weak self] in
                guard let self else { return }
                NSApp.activate(ignoringOtherApps: true)
                self.panel.makeKeyAndOrderFront(nil)
                self.state.focusQuestion += 1
            },
            HotKey(keyCode: UInt32(kVK_ANSI_C), modifiers: UInt32(optionKey)) { [weak self] in self?.state.catchUp() },
            HotKey(keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(optionKey)) { [weak self] in self?.state.stopSpeaking() },
            HotKey(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(optionKey)) { [weak self] in self?.state.toggleVoiceQuestion() },
        ]
    }

    /// Without a main menu, Cmd+V, Cmd+C, Cmd+X and Cmd+A do nothing in the question field (they are menu
    /// key equivalents), and Cmd+Q does not quit.
    private func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Clueless", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    /// Resize the panel to its content, keeping the top edge where it is so it grows downwards.
    private func fitPanel(toContentHeight height: CGFloat) {
        guard let panel, height > 50 else { return }
        let visible = (panel.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        // The content starts below the transparent title bar.
        let titleBar = panel.contentView?.safeAreaInsets.top ?? 28
        var wanted = height + titleBar
        if visible.height > 220 { wanted = min(wanted, visible.height - 20) }
        var frame = panel.frame
        guard abs(frame.height - wanted) > 0.5 else { return }
        frame.origin.y = frame.maxY - wanted
        frame.size.height = wanted
        if visible.height > 0, frame.minY < visible.minY { frame.origin.y = visible.minY }   // stay on screen
        panel.setFrame(frame, display: true)
    }

    /// Quit when the Clueless panel itself is closed, not when a secondary window is. The camera test window
    /// is the app's only regular window (the panel is an NSPanel, which AppKit does not count), so closing it
    /// used to end the whole session.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !(panel?.isVisible ?? false)
    }
}

/// Minimal Carbon global hotkey.
final class HotKey {
    private var ref: EventHotKeyRef?
    private let action: () -> Void
    private static var handlers: [UInt32: () -> Void] = [:]
    private static var nextID: UInt32 = 1
    private static var installed = false

    init(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        self.action = action
        let id = HotKey.nextID; HotKey.nextID += 1
        HotKey.handlers[id] = action
        if !HotKey.installed {
            HotKey.installed = true
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
                var hk = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                  nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
                DispatchQueue.main.async { HotKey.handlers[hk.id]?() }
                return noErr
            }, 1, &spec, nil, nil)
        }
        let status = RegisterEventHotKey(keyCode, modifiers, EventHotKeyID(signature: OSType(0x434C5553), id: id),
                                         GetApplicationEventTarget(), 0, &ref)
        // A key another app already owns fails here without any other sign: say so in the log.
        Log.write(status == noErr ? "[hotkey] registered Option + key code \(keyCode)"
                  : "[hotkey] could NOT register Option + key code \(keyCode) (OSStatus \(status)): another app may own it")
    }

    deinit { if let ref { UnregisterEventHotKey(ref) } }
}
