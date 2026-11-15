import AppKit
import SwiftUI

/// The look of the app in one place (T49): colours, corner radii, spacing and fonts. The views use these
/// and hard-code nothing. Visual only: nothing here changes what a control does.
enum Style {
    // Colours. Status colours keep their meaning everywhere.
    /// Interactive things and the "You could say" line.
    static let accent = Color(red: 0.27, green: 0.58, blue: 1.0)
    static let recording = Color.red
    static let good = Color.green        // focused, server up
    static let warning = Color.orange    // distracted, a server is down
    static let off = Color.gray
    /// Thin light edge of a tile when real glass is not available.
    static let hairline = Color.white.opacity(0.16)
    /// Darkens the blurred desktop behind the panel so text stays readable over any window.
    static let panelShade = Color.black.opacity(0.30)

    // Corner radii: larger outside, smaller inside.
    static let tileRadius: CGFloat = 14
    static let innerRadius: CGFloat = 8

    // Spacing.
    static let padding: CGFloat = 14
    static let tilePadding: CGFloat = 12
    static let gap: CGFloat = 10
    /// Diameter of the round icon buttons (camera, eye, pause, microphone, "…").
    static let iconButton: CGFloat = 26

    // Fonts.
    static let wordmark = Font.system(size: 13, weight: .bold, design: .rounded)
    static let status = Font.system(size: 10)
    static let cardTitle = Font.system(size: 15, weight: .semibold)
    static let sectionLabel = Font.system(size: 9, weight: .bold)
    static let sectionTracking: CGFloat = 0.9
    static let tag = Font.system(size: 9, weight: .bold)
    static let icon = Font.system(size: 11, weight: .semibold)
    static let hudStatus = Font.system(size: 10, design: .monospaced)
    static let hudValue = Font.system(size: 11, weight: .medium, design: .monospaced)
    static let hudLabel = Font.system(size: 8)
    static let stateLabel = Font.system(size: 20, weight: .bold, design: .rounded)

    /// CLUELESS_GLASS=0 uses the plain material everywhere, without a rebuild, if Liquid Glass looks wrong.
    static let glassEnabled = ProcessInfo.processInfo.environment["CLUELESS_GLASS"] != "0"
}

/// A rounded tile: Apple's Liquid Glass on macOS 26 and later, a thin material with a light edge before.
/// The Liquid Glass call is compiled only by a toolchain that ships the macOS 26 SDK (Swift 6.2, Xcode 26
/// or its Command Line Tools); an older one builds the material version alone.
struct GlassTile: ViewModifier {
    var cornerRadius: CGFloat
    var tint: Color?

    #if compiler(>=6.2)
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            if Style.glassEnabled {
                content.glassEffect(Glass.regular.tint(tint),
                                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            } else {
                material(content)
            }
        } else {
            material(content)
        }
    }
    #else
    func body(content: Content) -> some View {
        material(content)
    }
    #endif

    private func material(_ content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return content
            .background(shape.fill((tint ?? Color.clear).opacity(0.22)))
            .background(shape.fill(.ultraThinMaterial))
            .overlay(shape.stroke(Style.hairline, lineWidth: 1))
    }
}

extension View {
    /// The one way to draw a glass tile.
    func glass(cornerRadius: CGFloat = Style.tileRadius, tint: Color? = nil) -> some View {
        modifier(GlassTile(cornerRadius: cornerRadius, tint: tint))
    }
}

/// Round glass icon button, one size for the whole app.
struct GlassIconButtonStyle: ButtonStyle {
    /// Colour of the symbol; nil is the normal text colour.
    var symbol: Color?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Style.icon)
            .foregroundStyle(symbol ?? Color.primary)
            .frame(width: Style.iconButton, height: Style.iconButton)
            .glass(cornerRadius: Style.iconButton / 2)
            .contentShape(Circle())
            .opacity(configuration.isPressed ? 0.55 : 1)
    }
}

/// Small coloured tag for a speaker label in the transcript.
struct SpeakerTag: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(Style.tag)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(color)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.20)))
    }
}

/// Small, spaced capitals above a section of a card.
struct SectionLabel: View {
    let text: String
    var color: Color = Color.secondary

    var body: some View {
        Text(text.uppercased()).font(Style.sectionLabel).tracking(Style.sectionTracking).foregroundStyle(color)
    }
}

/// The dark, translucent background of the panel and the camera window: the desktop behind the window,
/// blurred by AppKit, with a dark shade on top. Not hidden from screen sharing.
struct PanelBackground: View {
    var body: some View {
        ZStack {
            BehindWindowBlur()
            Style.panelShade
        }
        .ignoresSafeArea()
    }
}

struct BehindWindowBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
