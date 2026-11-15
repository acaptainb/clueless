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

    /// Wall-clock time of a position (in seconds) inside `samples()`: the inverse of `offset(of:)`.
    public func time(at seconds: Double) -> Date? {
        lock.lock(); defer { lock.unlock() }
        let index = Int(seconds * Double(Self.sampleRate)) + dropped
        guard let anchor = anchors.last(where: { $0.index <= index }) ?? anchors.first else { return nil }
        return anchor.time.addingTimeInterval(Double(index - anchor.index) / Double(Self.sampleRate))
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
    public func turns(_ samples: [Float], speakers: Int? = nil, threshold: Float? = nil) async throws -> [SpeakerTurn] {
        let options = PyannoteDiarizationOptions(numberOfSpeakers: speakers, clusterDistanceThreshold: threshold)
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

    /// Joins consecutive turns of one speaker (pauses up to `maxGap`) into one stretch of speech and drops
    /// stretches too short to hold a word.
    public static func utterances(_ turns: [SpeakerTurn], maxGap: Double = 1.0, minSeconds: Double = 0.4) -> [SpeakerTurn] {
        var out: [SpeakerTurn] = []
        for turn in turns.sorted(by: { $0.start < $1.start }) {
            if let last = out.last, last.speaker == turn.speaker, turn.start - last.end <= maxGap {
                out[out.count - 1] = SpeakerTurn(speaker: last.speaker, start: last.start, end: max(last.end, turn.end))
            } else {
                out.append(turn)
            }
        }
        return out.filter { $0.end - $0.start >= minSeconds }
    }

    /// The call transcribed again from the recording, one line per stretch of speech by one speaker.
    /// Live lines are cut at pauses, so one line can hold two people ("Go ahead, Sam. The API changes are
    /// merged."); these lines cannot. Speakers are "Speaker 1", "Speaker 2", ... in order of first appearance.
    /// `time` maps seconds in the recording to wall-clock time; ids count up from `firstID`.
    public static func transcript(from samples: [Float], turns: [SpeakerTurn], transcriber: Transcriber,
                                  time: (Double) -> Date?, firstID: Int) async -> [TimelineLine] {
        let rate = Double(SessionAudio.sampleRate)
        var numbers: [Int: Int] = [:]
        var out: [TimelineLine] = []
        for stretch in utterances(turns) {
            // Whisper works on windows of 30 s: cut longer stretches.
            var start = stretch.start
            while start < stretch.end {
                let end = min(stretch.end, start + 25)
                let a = max(0, Int((start - 0.15) * rate)), b = min(samples.count, Int((end + 0.15) * rate))
                if b - a > Int(0.3 * rate), let text = try? await transcriber.transcribe(Array(samples[a..<b])), text.count > 1 {
                    if numbers[stretch.speaker] == nil { numbers[stretch.speaker] = numbers.count + 1 }
                    out.append(TimelineLine(id: firstID + out.count, t: time(start) ?? Date(), source: .them,
                                            speaker: "Speaker \(numbers[stretch.speaker] ?? 0)", text: text))
                }
                start = end
            }
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
    A name inside a line is never the name of the person saying that line: it names the person they are talking to. A name that is only talked about is not a clue. "You" is the user and never needs a name. If you are not sure about a speaker, use "".
    Reply with JSON only, one key per label: {"Speaker 1": "Maya", "Speaker 2": ""}
    """

    /// `["Speaker 1": "Maya"]` for the labels it is sure about. Empty when there is nothing to resolve or the model is down.
    public func resolve(_ lines: [TimelineLine], userName: String) async -> [String: String] {
        let spoken = Array(lines.filter { $0.source == .them || $0.source == .me }.suffix(120))
        let labels = Set(spoken.compactMap(\.speaker).filter { $0.hasPrefix("Speaker ") })
        guard !labels.isEmpty else { return [:] }
        // Who is addressed and who answers settles most names without a model (BENCHMARKS.md: the model
        // alone got 7/12, handing a name to the person who said it).
        let coded = NameClues.resolve(spoken, userName: userName)
        if !coded.isEmpty { return coded }
        let transcript = spoken.map { "\($0.label): \($0.text)" }.joined(separator: "\n")
        var prompt = ""
        if !userName.isEmpty { prompt += "The user, shown as \"You\", is \(userName).\n\n" }
        prompt += "TRANSCRIPT:\n" + transcript + "\n\nLabels to resolve: " + labels.sorted().joined(separator: ", ")
        guard let reply = try? await client.chat(system: Self.system, user: .text(prompt), maxTokens: 120, json: true),
              let obj = JSONRepair.object(reply.0) else { return [:] }
        var names = Self.validate(obj, labels: labels, transcript: spoken.map(\.text).joined(separator: "\n"), userName: userName)
        // Nobody addresses themselves: drop a name the speaker uses to address someone else.
        let said = NameClues.addressedBy(spoken, userName: userName)
        for (label, name) in names where said[label]?.contains(name.lowercased()) == true { names[label] = nil }
        return names
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

    /// With a `transcriber`, a recording of up to `rebuildLimit` seconds is transcribed again one speaker
    /// turn at a time, which is what makes the speaker of each line (and so the names) reliable. Longer
    /// recordings, or no transcriber, fall back to labelling the live lines by who talks most during each.
    public static let rebuildLimit = 900.0

    public static func make(lines: [TimelineLine], audio: SessionAudio? = nil, labeler: SpeakerLabeler? = nil,
                            transcriber: Transcriber? = nil,
                            answerer: Answerer = Answerer(), userName: String = "",
                            onPartial: (@Sendable (Card) -> Void)? = nil) async throws -> Result {
        let t0 = Date()
        var labelled = lines
        var speakerCount = 0
        if let audio, let labeler, audio.seconds > 5 {
            let samples = audio.samples()
            if let turns = try? await labeler.turns(samples), !turns.isEmpty {
                speakerCount = Set(turns.map(\.speaker)).count
                var rebuilt: [TimelineLine] = []
                if let transcriber, audio.seconds <= rebuildLimit {
                    let firstID = (lines.map(\.id).max() ?? 0) + 10_000
                    rebuilt = await Speakers.transcript(from: samples, turns: turns, transcriber: transcriber,
                                                        time: { audio.time(at: $0) }, firstID: firstID)
                }
                if rebuilt.isEmpty {
                    labelled = Speakers.assign(lines, turns: turns, offset: { audio.offset(of: $0) })
                } else {
                    // The user's own lines (microphone) are kept as they were, in time order with the rest.
                    labelled = (rebuilt + lines.filter { $0.source == .me }).sorted { $0.t < $1.t }
                }
            }
        }
        let names = await NameResolver(client: answerer.client).resolve(labelled, userName: userName)
        labelled = Speakers.rename(labelled, names: names)
        if speakerCount > 0 {
            // Two clusters with the same name are one person: count people, not clusters.
            speakerCount = Set(labelled.filter { $0.source == .them }.compactMap(\.speaker)).count
        }
        let prepareSeconds = Date().timeIntervalSince(t0)
        let card = try await answerer.answer(.notes, lines: labelled, screenText: "", userName: userName, onPartial: onPartial)
        return Result(card: card, lines: labelled, names: names, speakerCount: speakerCount, prepareSeconds: prepareSeconds)
    }
}

/// Names worked out in code from who is addressed and who answers. No model call.
///   "Priya, where are we?"  then someone else speaks      -> that next speaker is Priya
///   "Thanks, Sam." / "Got it, Maya."                      -> the speaker just before is Sam / Maya
///   "this is Sam", "Sam here"                             -> the speaker is Sam
public enum NameClues {
    /// A sentence opening with one of these is an answer to the previous speaker, not a call on the next.
    static let answerOpeners: Set<String> = ["thanks", "thank", "got", "perfect", "great", "good", "right", "okay", "ok",
                                             "yes", "yeah", "yep", "no", "nope", "not", "sure", "understood", "agreed",
                                             "exactly", "will", "works", "fine", "cool", "sorry"]
    /// Capitalised words that turn up next to a comma and are not names.
    static let notNames: Set<String> = ["okay", "ok", "thanks", "thank", "understood", "approved", "agreed", "great", "good",
        "sure", "yes", "yeah", "yep", "no", "nope", "well", "so", "now", "right", "perfect", "sorry", "please", "hello", "hi",
        "hey", "morning", "afternoon", "evening", "today", "tomorrow", "yesterday", "tonight", "then", "first", "second",
        "third", "next", "finally", "also", "actually", "honestly", "look", "listen", "everyone", "everybody", "folks",
        "team", "guys", "all", "and", "but", "or", "still", "anyway", "alright", "fine", "cool", "exactly", "absolutely",
        "definitely", "maybe", "however", "meanwhile", "instead", "otherwise", "basically", "obviously", "again", "there",
        "here", "this", "that", "these", "those", "you", "we", "they", "it", "one", "two", "three", "monday", "tuesday",
        "wednesday", "thursday", "friday", "saturday", "sunday", "january", "february", "march", "april", "may", "june",
        "july", "august", "september", "october", "november", "december", "noted", "done", "correct", "true", "wait"]

    struct Address { let name: String; let answering: Bool }

    static func sentences(_ text: String) -> [String] {
        var out: [String] = []
        var current = ""
        for ch in text {
            current.append(ch)
            if ch == "." || ch == "!" || ch == "?" {
                out.append(current); current = ""
            }
        }
        if !current.trimmingCharacters(in: .whitespaces).isEmpty { out.append(current) }
        return out.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private static let addressPattern = try! NSRegularExpression(pattern: "(?:^|,\\s)([A-Z][a-z]{1,14})(?=,|[.!?]?$)")
    private static let thanksPattern = try! NSRegularExpression(pattern: "^(?:Thanks|Thank you)\\s([A-Z][a-z]{1,14})\\b")
    private static let selfPattern = try! NSRegularExpression(
        pattern: "(?:\\b[Tt]his is|\\bI'm|\\bI am|\\b[Mm]y name is)\\s([A-Z][a-z]{1,14})\\b|^([A-Z][a-z]{1,14}) here\\b")

    private static func captures(_ regex: NSRegularExpression, _ text: String) -> [(name: String, atStart: Bool)] {
        let ns = text as NSString
        var out: [(name: String, atStart: Bool)] = []
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            for group in 1..<match.numberOfRanges where match.range(at: group).location != NSNotFound {
                out.append((ns.substring(with: match.range(at: group)), match.range(at: group).location == 0))
            }
        }
        return out
    }

    /// Names used to address someone in one sentence.
    static func addresses(in sentence: String, userName: String) -> [Address] {
        let first = sentence.split(whereSeparator: { !$0.isLetter }).first.map { $0.lowercased() } ?? ""
        var out: [Address] = []
        for found in captures(addressPattern, sentence) + captures(thanksPattern, sentence).map({ (name: $0.name, atStart: false) }) {
            let lower = found.name.lowercased()
            if notNames.contains(lower) || lower == userName.lowercased() { continue }
            if out.contains(where: { $0.name.lowercased() == lower }) { continue }
            out.append(Address(name: found.name, answering: !found.atStart && answerOpeners.contains(first)))
        }
        return out
    }

    /// For every speaker label, the names (lower case) that speaker uses to address someone else.
    public static func addressedBy(_ lines: [TimelineLine], userName: String) -> [String: Set<String>] {
        var out: [String: Set<String>] = [:]
        for line in lines {
            guard let label = line.speaker else { continue }
            for sentence in sentences(line.text) {
                for address in addresses(in: sentence, userName: userName) { out[label, default: []].insert(address.name.lowercased()) }
            }
        }
        return out
    }

    /// `["Speaker 1": "Maya"]`. Two labels may get the same name: SpeakerKit sometimes splits one person in two.
    public static func resolve(_ lines: [TimelineLine], userName: String) -> [String: String] {
        let spoken = lines.filter { $0.source == .them || $0.source == .me }
        let said = addressedBy(spoken, userName: userName)
        var votes: [String: [String: Int]] = [:]          // label -> name -> votes
        func vote(_ label: String?, _ name: String, _ weight: Int = 1) {
            guard let label, label.hasPrefix("Speaker "), said[label]?.contains(name.lowercased()) != true else { return }
            votes[label, default: [:]][name, default: 0] += weight
        }
        /// The nearest "them" line with another speaker, looking forwards or backwards over at most 3 lines.
        func neighbour(of i: Int, step: Int) -> String? {
            var j = i + step, seen = 0
            while j >= 0, j < spoken.count, seen < 3 {
                if spoken[j].source == .them, let label = spoken[j].speaker, label != spoken[i].speaker { return label }
                j += step; seen += 1
            }
            return nil
        }
        for (i, line) in spoken.enumerated() {
            for sentence in sentences(line.text) {
                for found in captures(selfPattern, sentence) where !notNames.contains(found.name.lowercased()) {
                    if line.source == .them, found.name.lowercased() != userName.lowercased() { vote(line.speaker, found.name, 3) }
                }
                for address in addresses(in: sentence, userName: userName) {
                    vote(neighbour(of: i, step: address.answering ? -1 : 1), address.name)
                }
            }
        }
        var out: [String: String] = [:]
        for (label, counts) in votes {
            let best = counts.max { $0.value < $1.value }
            guard let best, counts.filter({ $0.value == best.value }).count == 1 else { continue }
            out[label] = best.key
        }
        return out
    }
}
