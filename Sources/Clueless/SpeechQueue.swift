import Foundation
import CluelessCore

/// Cuts the text of a card into pieces to speak while the card is still being written.
/// Feed it the spoken text so far after every token; it hands back each new run of complete
/// sentences once, and the remainder when the card is final.
struct SpeechSplitter {
    /// Shorter pieces sound choppy and each one costs a synthesis start, so wait for more text.
    var minCharacters = 24
    /// Characters of the text already handed out.
    private(set) var consumed = 0

    mutating func next(_ spoken: String, final: Bool) -> String? {
        let chars = Array(spoken)
        guard chars.count > consumed else { return nil }
        var end = chars.count
        if !final {
            // The last sentence end that is followed by whitespace: the sentence is known to be over,
            // and "3.5" or a half-written word is never cut.
            end = consumed
            var i = chars.count - 2
            while i >= consumed {
                if ".!?".contains(chars[i]), chars[i + 1].isWhitespace { end = i + 1; break }
                i -= 1
            }
            guard end - consumed >= minCharacters else { return nil }
        }
        let piece = String(chars[consumed..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        consumed = end
        return piece.isEmpty ? nil : piece
    }
}

/// Speaks pieces one after another through Argmax TTSKit, starting while the answer is still streaming.
@MainActor
final class SpeechQueue {
    private let speaker: Speaker
    private var splitter = SpeechSplitter()
    private var pending: [String] = []
    private var worker: Task<Void, Never>?
    private var generation = 0
    /// Set by `stop()` until the next card begins: the card that was stopped is still streaming, and its
    /// next sentence must not start the voice again.
    private var muted = false
    /// True while a piece is being spoken or is waiting to be.
    var speaking: Bool { worker != nil }
    /// When the last piece finished or was stopped.
    private(set) var lastSpokeAt = Date.distantPast

    init(speaker: Speaker) { self.speaker = speaker }

    /// Start a new card: drop whatever was being said.
    func begin() {
        stop()
        splitter = SpeechSplitter()
        muted = false
    }

    /// Give the spoken text so far. Returns true when a new piece was queued.
    @discardableResult
    func update(_ spoken: String, final: Bool) -> Bool {
        guard !muted, let piece = splitter.next(spoken, final: final) else { return false }
        pending.append(piece)
        // One line per piece, so order and repeats can be checked from the log without listening.
        Log.write("[speech] queued\(final ? " (last)" : ""): \(piece)")
        if worker == nil { startWorker() }
        return true
    }

    func stop() {
        muted = true
        if worker != nil { lastSpokeAt = Date() }
        generation += 1
        pending.removeAll()
        worker?.cancel()
        worker = nil
        speaker.stop()
    }

    private func startWorker() {
        let mine = generation
        worker = Task { [weak self] in
            while !Task.isCancelled, let self, self.generation == mine, !self.pending.isEmpty {
                let piece = self.pending.removeFirst()
                // Plays to the end, or stops when this task is cancelled.
                _ = try? await self.speaker.sayAndWait(piece)
                self.lastSpokeAt = Date()
            }
            if let self, self.generation == mine { self.worker = nil }
        }
    }
}
