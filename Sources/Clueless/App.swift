import AppKit
import SwiftUI
import Carbon.HIToolbox

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
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        // Deliberately NOT hidden from screen sharing: sharingType stays at its default.
        panel.contentView = NSHostingView(rootView: OverlayView(state: state))
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: f.maxX - 440, y: f.maxY - 460))
        }
        panel.orderFrontRegardless()

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
        ]
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
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
        RegisterEventHotKey(keyCode, modifiers, EventHotKeyID(signature: OSType(0x434C5553), id: id),
                            GetApplicationEventTarget(), 0, &ref)
    }

    deinit { if let ref { UnregisterEventHotKey(ref) } }
}
