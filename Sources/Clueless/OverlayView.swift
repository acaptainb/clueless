import SwiftUI
import CluelessCore

struct OverlayView: View {
    @ObservedObject var state: AppState
    /// Reports the height the content needs, so the panel can be sized to fit it (App.swift).
    var onHeight: (CGFloat) -> Void = { _ in }
    @FocusState private var questionFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Style.gap) {
            header
            if let issue = state.serverIssue { serverRow(issue) }
            transcript
            askBar
            if state.thinking { thinkingRow }
            if let card = state.card {
                // As tall as the card needs, up to a limit; a longer card (session notes) scrolls
                // instead of pushing the HUD off the panel.
                ScrollView {
                    CardView(title: state.cardTitle, card: card, timeline: state.timeline,
                             screen: state.screenReceipt, toggleScreen: { state.screenReceipt?.enlarged.toggle() },
                             named: state.namedLines)
                }
                    .frame(maxHeight: 380)
                    .fixedSize(horizontal: false, vertical: true)
            }
            hud
        }
        .padding(Style.padding)
        .frame(width: 420)
        // Take the natural height and tell the panel, which resizes to fit. Before this the content
        // could be taller than the window and overflowed at both ends, hiding the HUD.
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onHeight($0) }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(PanelBackground())
        .onChange(of: state.focusQuestion) { questionFocused = true }
    }

    // Always-visible recording indicator: Clueless never hides that it is capturing.
    private var header: some View {
        HStack(spacing: 8) {
            Circle().fill(state.recording ? Style.recording : Style.off).frame(width: 10, height: 10)
                .shadow(color: state.recording ? Style.recording.opacity(0.8) : Color.clear, radius: 4)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text("Clueless").font(Style.wordmark)
                    // Visible whenever the webcam is in use for the look-away trigger.
                    if state.presence != .off {
                        Image(systemName: state.presence == .present ? "eye" : (state.presence == .away ? "eye.slash" : "video.slash"))
                            .font(.caption)
                            .foregroundStyle(state.presence == .away ? Style.warning : Color.secondary)
                            .help(state.presence == .present ? "Webcam on: you are facing the screen"
                                  : state.presence == .away ? "Webcam on: you looked away. Clueless will catch you up when you are back"
                                  : "Camera not available. Allow Camera for Clueless in System Settings › Privacy & Security")
                    }
                }
                Text(state.recording ? "Recording screen + audio · on this Mac only" : state.status)
                    .font(Style.status).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 4)
            Picker("", selection: $state.mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).frame(width: 110).labelsHidden()
            .onChange(of: state.mode) { state.modeChanged() }
            // Opens and closes the camera window (T48): the live picture with Focused / Distracted / No person.
            Button(action: state.toggleCameraWindow) { Image(systemName: state.cameraTest ? "video.fill" : "video") }
                .buttonStyle(GlassIconButtonStyle(symbol: state.cameraTest ? Style.accent : nil))
                .help(state.cameraTest ? "Close the camera window" : "Show the camera window: what the webcam sees")
            Button(action: state.toggle) { Image(systemName: state.recording || state.restartingCapture ? "pause.fill" : "play.fill") }
                .buttonStyle(GlassIconButtonStyle())
                .help(state.recording || state.restartingCapture ? "Pause capture" : "Resume capture")
        }
    }

    // A Bonsai server is down, loading or being started.
    private func serverRow(_ issue: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if state.startingServers { ProgressView().controlSize(.small) }
            else { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Style.warning) }
            Text(issue).font(.caption).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if state.serverCanRestart { Button("Restart", action: state.restartServers).controlSize(.small) }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Style.innerRadius, style: .continuous).fill(Style.warning.opacity(0.14)))
    }

    // Speaker labels as small coloured tags; the newest line is the strongest, older ones fade slightly.
    private var transcript: some View {
        let lines = state.tail
        return VStack(alignment: .leading, spacing: 5) {
            if lines.isEmpty {
                Text(state.recording ? "Listening… the transcript shows up here." : state.status)
                    .font(.callout).foregroundStyle(.tertiary)
            }
            ForEach(lines) { line in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    SpeakerTag(text: line.label, color: line.source == .me ? Style.accent : Color.secondary)
                        .frame(width: 58, alignment: .leading)
                    Text(line.text).font(.callout).lineLimit(3)
                }
                .opacity(line.id == lines.last?.id ? 1 : 0.72)
            }
        }
        .padding(Style.tilePadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass()
    }

    private var askBar: some View {
        HStack(spacing: 6) {
            TextField(state.listening ? "Listening… ask your question out loud" : "Ask about what's on screen or what was said  (⌥Space)",
                      text: $state.question)
                .textFieldStyle(.roundedBorder)
                .focused($questionFocused)
                .onSubmit(state.ask)
            // Ask by voice: the microphone goes through Argmax WhisperKit, on this Mac.
            Button(action: state.toggleVoiceQuestion) { Image(systemName: state.listening ? "mic.fill" : "mic") }
                .buttonStyle(GlassIconButtonStyle(symbol: state.listening ? Style.recording : nil))
                .disabled(state.mode == .call)
                .opacity(state.mode == .call ? 0.4 : 1)
                .help(state.mode == .call ? "Asking by voice is off in call mode: the call would hear you"
                      : state.listening ? "Listening. Stops by itself when you pause, or click to finish"
                      : "Ask by voice  (⌥V)")
            Button("Catch me up", action: state.catchUp)
                .keyboardShortcut("k", modifiers: [.command])
                .buttonStyle(.borderedProminent).tint(Style.accent)
                .help("What did I miss?  (⌥C)")
            Menu {
                Button("Session notes", action: state.notes)
                Toggle("Speak answers", isOn: $state.speak)
                Toggle("Catch me up when I look away (webcam)", isOn: $state.lookAway)
                Toggle("Count eye direction as looking away", isOn: $state.countEyes)
                    .disabled(AppState.eyesForcedOff)
                Button("Camera window") { state.openCameraTest() }
                Picker("Screen input", selection: $state.screenMethodRaw) {
                    Text("Auto: screenshot only for visual questions").tag(ScreenMethod.auto.rawValue)
                    Text("Screenshot + OCR text (most accurate)").tag(ScreenMethod.both.rawValue)
                    Text("OCR text only (fastest)").tag(ScreenMethod.ocr.rawValue)
                    Text("Screenshot only").tag(ScreenMethod.image.rawValue)
                }
                Button("Your name: \(state.userName)…") { state.editUserName() }
            } label: { Image(systemName: "ellipsis").font(Style.icon) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden)
                .frame(width: Style.iconButton, height: Style.iconButton)
                .glass(cornerRadius: Style.iconButton / 2)
        }
    }

    private var thinkingRow: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Bonsai is reading the screen and the last few minutes…").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var hud: some View { HUDView(hud: state.hud) }
}

struct CardView: View {
    let title: String
    let card: Card
    let timeline: Timeline
    /// The screen this card was answered from, if one was read (T06).
    var screen: ScreenReceipt? = nil
    /// Enlarges or shrinks the screen receipt. The flag lives in AppState: `@State` does not compile on
    /// the Mac mini (Command Line Tools only, no Xcode).
    var toggleScreen: () -> Void = {}
    /// Lines with speaker names from the call notes (T33); used for receipts when a line has one.
    var named: [Int: TimelineLine] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(Style.cardTitle).lineLimit(2)
            if card.task == .catchUp {
                row("You were asked", card.asked.isEmpty ? "Nothing directed at you." : card.asked)
                row("You missed", card.missed)
                if !card.reply.isEmpty { row("You could say", card.reply, highlight: true) }
            } else {
                Text(card.answer).font(.body).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
            if !card.sources.isEmpty || screen != nil {
                Divider()
                SectionLabel(text: "Receipts")
                ForEach(card.sources.prefix(4), id: \.self) { id in
                    if let line = named[id] ?? timeline.line(id: id) {
                        Text("\(line.clockTime)  \(line.label): \(line.text)")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                // The model cites spoken lines by number; the screen it was shown is listed with them.
                if let screen { ScreenReceiptRow(receipt: screen, toggle: toggleScreen) }
            }
        }
        .padding(Style.tilePadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass()
    }

    // "You could say" is the line the user acts on: it gets the accent tint.
    private func row(_ label: String, _ text: String, highlight: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: Style.innerRadius, style: .continuous)
        return VStack(alignment: .leading, spacing: 3) {
            SectionLabel(text: label, color: highlight ? Style.accent : Color.secondary)
            Text(text).font(.body).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
        .padding(highlight ? 8 : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(highlight ? Style.accent.opacity(0.18) : Color.clear))
        .overlay(shape.stroke(highlight ? Style.accent.opacity(0.45) : Color.clear, lineWidth: 1))
    }
}
