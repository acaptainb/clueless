import Foundation
import SpeakerKit

// Call mode, end of session: who said what.
//   T13  SessionAudio keeps the system audio; SpeakerLabeler (Argmax SpeakerKit) finds the speaker turns in it;
//        Speakers.assign gives every "them" line a label ("Speaker 1", "Speaker 2", ...).
//   T14  NameResolver asks Bonsai for the real names behind those labels, from what was said ("thanks, Priya").
//   T15  SessionNotes.make runs both and then writes the notes with the names in place.
// Every step is optional: without audio or without the SpeakerKit models the notes are still written, unlabelled.

/// Keeps the session's system audio (16 kHz mono) so speakers can be labelled when the session ends.
/// Stored as 16-bit samples: about 115 MB per hour.
public final class SessionAudio: @unchecked Sendable {
    public static let sampleRate = 16_000
    private let lock = NSLock()
    private var pcm: [Int16] = []
    /// Samples dropped from the front once the recording passed `maxSeconds`.
    private var dropped = 0
    /// Where in the recording a wall-clock time is. A new anchor is added whenever audio resumes after a gap,
    /// because the capture stream may send nothing while the Mac is silent.
    private var anchors: [(index: Int, time: Date)] = []
    private var lastArrival: Date?
    /// Older audio than this is dropped.
    public let maxSeconds: Double

    public init(maxSeconds: Double = 3600) { self.maxSeconds = maxSeconds }

    /// Add a buffer. `now` is when it arrived (the same clock `AudioChunker` uses for a line's time).
    public func append(_ samples: [Float], at now: Date = Date()) {
        guard !samples.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        let duration = Double(samples.count) / Double(Self.sampleRate)
        var continuous = false
        if let last = lastArrival { continuous = now.timeIntervalSince(last) <= duration + 0.5 }
        if !continuous { anchors.append((index: dropped + pcm.count, time: now)) }
        lastArrival = now
        for v in samples { pcm.append(Int16(max(-1, min(1, v)) * 32767)) }
        let limit = Int(maxSeconds) * Self.sampleRate
        if pcm.count > limit + 60 * Self.sampleRate {
            let extra = pcm.count - limit
            pcm.removeFirst(extra)
            dropped += extra
        }
    }

    public var seconds: Double {
        lock.lock(); defer { lock.unlock() }
        return Double(pcm.count) / Double(Self.sampleRate)
    }

    public func samples() -> [Float] {
        lock.lock(); defer { lock.unlock() }
        return pcm.map { Float($0) / 32767 }
    }

    /// Position of a wall-clock time inside `samples()`, in seconds. Nil if it is before the recording
    /// (or in a part that was dropped).
    public func offset(of time: Date) -> Double? {
        lock.lock(); defer { lock.unlock() }
        guard let anchor = anchors.last(where: { $0.time <= time }) ?? anchors.first else { return nil }
        let index = Double(anchor.index - dropped) + time.timeIntervalSince(anchor.time) * Double(Self.sampleRate)
        guard index >= 0 else { return nil }
        return min(index, Double(pcm.count)) / Double(Self.sampleRate)
    }
}

/// One stretch of speech by one speaker, in seconds from the start of the audio.
public struct SpeakerTurn: Sendable, Equatable {
    public let speaker: Int
    public let start: Double
    public let end: Double
    public init(speaker: Int, start: Double, end: Double) { self.speaker = speaker; self.start = start; self.end = end }
}

/// Argmax SpeakerKit, loaded from disk. Never downloads.
public final class SpeakerLabeler: @unchecked Sendable {
    private let kit: SpeakerKit
    public private(set) var loadSeconds: Double = 0

    /// Folder with the SpeakerKit Core ML models: `models/argmax/speakerkit-coreml` in the project, or the
    /// place `argmax-cli diarize` downloaded them to. Nil if neither exists.
    public static var modelFolder: String? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates: [URL] = [
            Paths.speakerModels,
            home.appendingPathComponent("Documents/huggingface/models/argmaxinc/speakerkit-coreml"),
        ]
        for url in candidates where FileManager.default.fileExists(atPath: url.path) { return url.path }
        return nil
    }

    public init() async throws {
        let t0 = Date()
        let config = PyannoteConfig(modelFolder: Self.modelFolder, download: false, load: true, verbose: false)
        kit = try await SpeakerKit(config)
        loadSeconds = Date().timeIntervalSince(t0)
    }

    /// Who speaks when. `speakers` fixes the number of speakers when it is known; nil lets SpeakerKit decide.
    public func turns(_ samples: [Float], speakers: Int? = nil) async throws -> [SpeakerTurn] {
        let options = PyannoteDiarizationOptions(numberOfSpeakers: speakers)
        let result = try await kit.diarize(audioArray: samples, options: options)
        var out: [SpeakerTurn] = []
        for segment in result.segments {
            guard let id = segment.speaker.speakerId else { continue }
            out.append(SpeakerTurn(speaker: id, start: Double(segment.startTime), end: Double(segment.endTime)))
        }
        return out
    }
}

public enum Speakers {
    /// A timeline line covers at most this much audio (chunks are cut at 8 s).
    static let maxLineSeconds = 10.0

    /// Gives every "them" line the label of whoever speaks most during it: "Speaker 1", "Speaker 2", ...
    /// numbered in order of first appearance. `offset` maps a line's time to seconds in the diarized audio
    /// (`SessionAudio.offset(of:)`). Lines it cannot place keep what they had.
    public static func assign(_ lines: [TimelineLine], turns: [SpeakerTurn], offset: (Date) -> Double?) -> [TimelineLine] {
        var out = lines
        var them: [Int] = []
        for i in lines.indices where lines[i].source == .them { them.append(i) }
        var numbers: [Int: Int] = [:]
        for (k, i) in them.enumerated() {
            guard let start = offset(lines[i].t) else { continue }
            var end = start + maxLineSeconds
            if k + 1 < them.count, let next = offset(lines[them[k + 1]].t), next > start { end = min(end, next) }
            var overlap: [Int: Double] = [:]
            for turn in turns {
                let shared = min(end, turn.end) - max(start, turn.start)
                if shared > 0 { overlap[turn.speaker, default: 0] += shared }
            }
            var best: Int? = nil
            var bestSeconds = 0.0
            for (speaker, seconds) in overlap where seconds > bestSeconds || (seconds == bestSeconds && speaker < (best ?? Int.max)) {
                best = speaker; bestSeconds = seconds
            }
            guard let speaker = best else { continue }
            if numbers[speaker] == nil { numbers[speaker] = numbers.count + 1 }
            out[i].speaker = "Speaker \(numbers[speaker] ?? 0)"
        }
        return out
    }

    /// Replaces labels by names: `["Speaker 2": "Priya"]`. Labels without a name stay.
    public static func rename(_ lines: [TimelineLine], names: [String: String]) -> [TimelineLine] {
        var out = lines
        for i in out.indices {
            if let label = out[i].speaker, let name = names[label], !name.isEmpty { out[i].speaker = name }
        }
        return out
    }
}

/// Works out the real names behind "Speaker N" labels from what was said. One Bonsai call, at the end of a session.
public struct NameResolver: Sendable {
    public let client: BonsaiClient
    public init(client: BonsaiClient = BonsaiClient(port: BonsaiClient.answererPort)) { self.client = client }

    /// Live text: prompts/names.txt. The built-in copy below is only used when that file cannot be read.
    static var system: String { Prompts.load("names") ?? builtInSystem }

    static let builtInSystem = """
    You get a meeting transcript in which some speakers are only known as "Speaker 1", "Speaker 2" and so on. Work out their real first names from what is said.
    Clues that count:
    - Someone is addressed by name and then answers: "Priya, where are we?" followed by Speaker 2 answering means Speaker 2 is Priya.
    - Someone is thanked or answered by name right after they spoke: Speaker 3 speaks, then "Thanks, Sam" means Speaker 3 is Sam.
    - Someone introduces themselves: "this is Sam", "Sam here".
    A name that is only talked about is not a clue. "You" is the user and never needs a name. If you are not sure about a speaker, use "".
    Reply with JSON only, one key per label: {"Speaker 1": "Maya", "Speaker 2": ""}
    """

    /// `["Speaker 1": "Maya"]` for the labels it is sure about. Empty when there is nothing to resolve or the model is down.
    public func resolve(_ lines: [TimelineLine], userName: String) async -> [String: String] {
        let spoken = Array(lines.filter { $0.source == .them || $0.source == .me }.suffix(120))
        let labels = Set(spoken.compactMap(\.speaker).filter { $0.hasPrefix("Speaker ") })
        guard !labels.isEmpty else { return [:] }
        let transcript = spoken.map { "\($0.label): \($0.text)" }.joined(separator: "\n")
        var prompt = ""
        if !userName.isEmpty { prompt += "The user, shown as \"You\", is \(userName).\n\n" }
        prompt += "TRANSCRIPT:\n" + transcript + "\n\nLabels to resolve: " + labels.sorted().joined(separator: ", ")
        guard let reply = try? await client.chat(system: Self.system, user: .text(prompt), maxTokens: 120, json: true),
              let obj = JSONRepair.object(reply.0) else { return [:] }
        return Self.validate(obj, labels: labels, transcript: spoken.map(\.text).joined(separator: "\n"), userName: userName)
    }

    /// Keeps only answers that can be trusted: a short name that was actually said in the call, is not the
    /// user's, and is not given to two speakers.
    public static func validate(_ obj: [String: Any], labels: Set<String>, transcript: String, userName: String) -> [String: String] {
        var out: [String: String] = [:]
        var used = Set<String>()
        for label in labels.sorted() {
            guard let raw = obj[label] as? String else { continue }
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty || name.count > 30 || name.lowercased().hasPrefix("speaker") { continue }
            if name.caseInsensitiveCompare(userName) == .orderedSame { continue }
            if !Watcher.mentions(transcript, name) { continue }
            if !used.insert(name.lowercased()).inserted { continue }
            out[label] = name
        }
        return out
    }
}

/// End-of-session notes for a call: label the speakers, find their names, then write the notes.
public enum SessionNotes {
    public struct Result: Sendable {
        public var card: Card
        /// The timeline as the notes saw it, with speaker labels and names filled in.
        public var lines: [TimelineLine]
        /// `["Speaker 1": "Maya"]`
        public var names: [String: String]
        /// How many speakers SpeakerKit heard (0 if it did not run).
        public var speakerCount: Int
        /// Time spent on speaker labels and names, before the notes started.
        public var prepareSeconds: Double
    }

    public static func make(lines: [TimelineLine], audio: SessionAudio? = nil, labeler: SpeakerLabeler? = nil,
                            answerer: Answerer = Answerer(), userName: String = "",
                            onPartial: (@Sendable (Card) -> Void)? = nil) async throws -> Result {
        let t0 = Date()
        var labelled = lines
        var speakerCount = 0
        if let audio, let labeler, audio.seconds > 5 {
            if let turns = try? await labeler.turns(audio.samples()), !turns.isEmpty {
                labelled = Speakers.assign(lines, turns: turns, offset: { audio.offset(of: $0) })
                speakerCount = Set(turns.map(\.speaker)).count
            }
        }
        let names = await NameResolver(client: answerer.client).resolve(labelled, userName: userName)
        labelled = Speakers.rename(labelled, names: names)
        let prepareSeconds = Date().timeIntervalSince(t0)
        let card = try await answerer.answer(.notes, lines: labelled, screenText: "", userName: userName, onPartial: onPartial)
        return Result(card: card, lines: labelled, names: names, speakerCount: speakerCount, prepareSeconds: prepareSeconds)
    }
}
