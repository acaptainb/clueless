import SwiftUI
import CluelessCore

struct OverlayView: View {
    @ObservedObject var state: AppState
    /// Reports the height the content needs, so the panel can be sized to fit it (App.swift).
    var onHeight: (CGFloat) -> Void = { _ in }
    @FocusState private var questionFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if let issue = state.serverIssue { serverRow(issue) }
            transcript
            askBar
            if state.thinking { thinkingRow }
            if let card = state.card {
                // As tall as the card needs, up to a limit; a longer card (session notes) scrolls
                // instead of pushing the HUD off the panel.
                ScrollView { CardView(title: state.cardTitle, card: card, timeline: state.timeline) }
                    .frame(maxHeight: 380)
                    .fixedSize(horizontal: false, vertical: true)
            }
            hud
        }
        .padding(14)
        .frame(width: 420)
        // Take the natural height and tell the panel, which resizes to fit. Before this the content
        // could be taller than the window and overflowed at both ends, hiding the HUD.
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onHeight($0) }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.regularMaterial)
        .onChange(of: state.focusQuestion) { questionFocused = true }
    }

    // Always-visible recording indicator: Clueless never hides that it is capturing.
    private var header: some View {
        HStack(spacing: 8) {
            Circle().fill(state.recording ? Color.red : Color.gray).frame(width: 10, height: 10)
            // Visible whenever the webcam is in use for the look-away trigger.
            if state.presence != .off {
                Image(systemName: state.presence == .present ? "eye" : (state.presence == .away ? "eye.slash" : "video.slash"))
                    .font(.caption)
                    .foregroundStyle(state.presence == .away ? Color.orange : Color.secondary)
                    .help(state.presence == .present ? "Webcam on: you are facing the screen"
                          : state.presence == .away ? "Webcam on: you looked away. Clueless will catch you up when you are back"
                          : "Camera not available. Allow Camera for Clueless in System Settings › Privacy & Security")
            }
            Text(state.recording ? "Recording screen + audio · on this Mac only" : state.status)
                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            Spacer()
            Picker("", selection: $state.mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).frame(width: 110).labelsHidden()
            .onChange(of: state.mode) { state.modeChanged() }
            Button(action: state.toggle) { Image(systemName: state.recording || state.restartingCapture ? "pause.fill" : "play.fill") }
                .buttonStyle(.borderless).help(state.recording || state.restartingCapture ? "Pause capture" : "Resume capture")
        }
    }

    // A Bonsai server is down, loading or being started.
    private func serverRow(_ issue: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if state.startingServers { ProgressView().controlSize(.small) }
            else { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
            Text(issue).font(.caption).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if state.serverCanRestart { Button("Restart", action: state.restartServers).controlSize(.small) }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
    }

    private var transcript: some View {
        VStack(alignment: .leading, spacing: 3) {
            if state.tail.isEmpty {
                Text(state.recording ? "Listening… the transcript shows up here." : state.status)
                    .font(.callout).foregroundStyle(.tertiary)
            }
            ForEach(state.tail) { line in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(line.label).font(.caption2.bold())
                        .foregroundStyle(line.source == .me ? Color.accentColor : Color.secondary)
                        .frame(width: 44, alignment: .leading)
                    Text(line.text).font(.callout).lineLimit(3)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var askBar: some View {
        HStack(spacing: 6) {
            TextField("Ask about what's on screen or what was said  (⌥Space)", text: $state.question)
                .textFieldStyle(.roundedBorder)
                .focused($questionFocused)
                .onSubmit(state.ask)
            Button("Catch me up", action: state.catchUp)
                .keyboardShortcut("k", modifiers: [.command])
                .help("What did I miss?  (⌥C)")
            Menu {
                Button("Session notes", action: state.notes)
                Toggle("Speak answers", isOn: $state.speak)
                Toggle("Catch me up when I look away (webcam)", isOn: $state.lookAway)
                Picker("Screen input", selection: $state.screenMethodRaw) {
                    Text("Auto: screenshot only for visual questions").tag(ScreenMethod.auto.rawValue)
                    Text("Screenshot + OCR text (most accurate)").tag(ScreenMethod.both.rawValue)
                    Text("OCR text only (fastest)").tag(ScreenMethod.ocr.rawValue)
                    Text("Screenshot only").tag(ScreenMethod.image.rawValue)
                }
                TextField("Your name", text: $state.userName)
            } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).frame(width: 28)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline).lineLimit(2)
            if card.task == .catchUp {
                row("You were asked", card.asked.isEmpty ? "Nothing directed at you." : card.asked)
                row("You missed", card.missed)
                if !card.reply.isEmpty { row("You could say", card.reply, highlight: true) }
            } else {
                Text(card.answer).font(.body).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
            if !card.sources.isEmpty {
                Divider()
                Text("RECEIPTS").font(.caption2.bold()).foregroundStyle(.secondary)
                ForEach(card.sources.prefix(4), id: \.self) { id in
                    if let line = timeline.line(id: id) {
                        Text("\(line.clockTime)  \(line.label): \(line.text)")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.06)))
    }

    private func row(_ label: String, _ text: String, highlight: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).font(.caption2.bold()).foregroundStyle(highlight ? Color.accentColor : Color.secondary)
            Text(text).font(.body).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
    }
}
