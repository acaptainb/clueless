import Foundation
import CluelessCore

// Call mode, end of session (T33): the app side of T13 to T15. The work is done by the core
// (`SessionNotes.make` in Speakers.swift): label the speakers with Argmax SpeakerKit on the recorded system
// audio, ask Bonsai for their names from what was said, then write the notes with the names in place.
// Every step is optional there, so without the SpeakerKit models the notes are still written, unlabelled.
extension AppState {
    /// Loads SpeakerKit from disk, after the app is already listening. It is only needed when notes are asked for.
    func loadSpeakerLabeler() async {
        guard speakerLabeler == nil else { return }
        do {
            let labeler = try await SpeakerLabeler()
            speakerLabeler = labeler
            Log.write("[speakers] SpeakerKit loaded in \(String(format: "%.1f", labeler.loadSeconds))s from \(SpeakerLabeler.modelFolder ?? "?")")
        } catch {
            Log.write("[speakers] SpeakerKit NOT loaded (\(error.localizedDescription)). Call notes will have no speaker labels. Models are expected in \(Paths.speakerModels.path)")
        }
    }

    /// Notes for a call. `lines` are the spoken lines of the session; the result is shown like any other card.
    func callNotes(_ lines: [TimelineLine], answerer: Answerer,
                   onPartial: @escaping @Sendable (Card) -> Void) async throws -> Card {
        Log.write("[notes] call notes: \(lines.count) lines, \(Int(sessionAudio.seconds)) s of recorded audio, SpeakerKit \(speakerLabeler == nil ? "not loaded" : "loaded")")
        // `lines` is capped (200). The other side is rebuilt from the whole recording, so give the notes
        // everything the user said in the call as well, or their earlier lines are the only ones missing.
        let own = timeline.all.filter { $0.source == .me && $0.t >= callStartedAt }
        Log.write("[notes] your lines: \(own.count) in the whole call, \(lines.filter { $0.source == .me }.count) of them in the capped list")
        let result = try await SessionNotes.make(lines: lines, ownLines: own, audio: sessionAudio, labeler: speakerLabeler, transcriber: transcriber,
                                                 answerer: answerer, userName: userName, onPartial: onPartial)
        // Receipts look lines up by number: show them with the speaker names from now on.
        for line in result.lines where line.speaker != nil { namedLines[line.id] = line }
        let names = result.names.sorted { $0.key < $1.key }.map { "\($0.key) = \($0.value)" }.joined(separator: ", ")
        let labelled = result.lines.filter { $0.source == .them && $0.speaker != nil }.count
        Log.write("[notes] \(result.speakerCount) speakers heard, \(labelled) of \(result.lines.filter { $0.source == .them }.count) lines labelled, names: \(names.isEmpty ? "none" : names); labels and names took \(String(format: "%.1f", result.prepareSeconds))s")
        if result.speakerCount > 0 {
            cardTitle = "Session notes · \(result.speakerCount) speakers, \(result.names.count) named"
        }
        return result.card
    }
}
