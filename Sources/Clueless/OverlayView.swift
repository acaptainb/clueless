import SwiftUI
import CluelessCore

struct OverlayView: View {
    @ObservedObject var state: AppState
    @FocusState private var questionFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            transcript
            askBar
            if state.thinking { thinkingRow }
            if let card = state.card { CardView(title: state.cardTitle, card: card, timeline: state.timeline) }
            Spacer(minLength: 0)
            hud
        }
        .padding(14)
        .frame(width: 420)
        .frame(minHeight: 300)
        .background(.regularMaterial)
        .onChange(of: state.focusQuestion) { questionFocused = true }
    }

    // Always-visible recording indicator: Clueless never hides that it is capturing.
    private var header: some View {
        HStack(spacing: 8) {
            Circle().fill(state.recording ? Color.red : Color.gray).frame(width: 10, height: 10)
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
                Picker("Screen input", selection: $state.screenMethodRaw) {
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

    private var hud: some View {
        let h = state.hud
        return HStack(spacing: 10) {
            Label(h.online ? "network on (unused)" : "network off", systemImage: h.online ? "wifi" : "wifi.slash")
                .foregroundStyle(h.online ? Color.secondary : Color.green)
            Text("stt \(h.stt, specifier: "%.1f")s")
            Text("ocr \(h.ocr, specifier: "%.1f")s")
            Text("9B \(h.llm, specifier: "%.1f")s · \(h.tps, specifier: "%.0f") tok/s")
            Text("\(h.ramMB) MB")
            Circle().fill(h.answerer ? Color.green : Color.red).frame(width: 6, height: 6).help("Bonsai 9B answerer")
            Circle().fill(h.watcher ? Color.green : Color.red).frame(width: 6, height: 6).help("Bonsai watcher")
        }
        .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
    }
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
