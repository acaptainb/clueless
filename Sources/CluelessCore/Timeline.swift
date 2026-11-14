import Foundation

/// One line of the shared timeline. This format is the contract between teammates (BRIEF.md §4).
public struct TimelineLine: Codable, Identifiable, Sendable, Equatable {
    public enum Source: String, Codable, Sendable { case them, me, screen, webcam, system }
    public let id: Int
    public let t: Date
    public let source: Source
    public var speaker: String?
    public var text: String
    public var snapshot: String?

    public init(id: Int, t: Date, source: Source, speaker: String? = nil, text: String, snapshot: String? = nil) {
        self.id = id; self.t = t; self.source = source; self.speaker = speaker; self.text = text; self.snapshot = snapshot
    }

    static let clock: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f
    }()

    public var label: String {
        if let speaker { return speaker }
        switch source {
        case .them: return "Them"
        case .me: return "You"
        case .screen: return "Screen"
        case .webcam: return "Webcam"
        case .system: return "System"
        }
    }

    public var clockTime: String { Self.clock.string(from: t) }

    /// `[L215 14:03:10] Maya: Yusuf, can your team still hit Friday?`
    public var rendered: String { "[L\(id) \(clockTime)] \(label): \(text)" }
}

/// Numbered, timestamped log. In memory, mirrored to a JSONL file.
public final class Timeline: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [TimelineLine] = []
    private var nextID = 1
    private var handle: FileHandle?
    private let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e
    }()

    public init(jsonl: URL? = nil) {
        if let jsonl {
            try? FileManager.default.createDirectory(at: jsonl.deletingLastPathComponent(), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: jsonl.path, contents: nil)
            handle = try? FileHandle(forWritingTo: jsonl)
        }
    }

    @discardableResult
    public func append(_ source: TimelineLine.Source, _ text: String, speaker: String? = nil,
                       snapshot: String? = nil, at t: Date = Date()) -> TimelineLine {
        lock.lock(); defer { lock.unlock() }
        let line = TimelineLine(id: nextID, t: t, source: source, speaker: speaker, text: text, snapshot: snapshot)
        nextID += 1
        lines.append(line)
        if let handle, let data = try? encoder.encode(line) {
            handle.write(data); handle.write(Data("\n".utf8))
        }
        return line
    }

    public var all: [TimelineLine] { lock.lock(); defer { lock.unlock() }; return lines }

    /// Lines from about the last `seconds`, capped at about `maxLines` (newest kept).
    ///
    /// The first line returned only changes every `step` seconds (and, when the cap is hit, every 10 lines),
    /// not on every call. Two requests a few seconds apart then start with the same lines, and the Bonsai
    /// server reuses its evaluation of them instead of reading the whole timeline again. The window is
    /// therefore up to `step` seconds longer than asked for. `step: 0` gives the exact window.
    public func recent(seconds: TimeInterval, maxLines: Int = 60, step: TimeInterval = 60, now: Date = Date()) -> [TimelineLine] {
        lock.lock(); defer { lock.unlock() }
        var cutoff = now.addingTimeInterval(-seconds)
        if step > 0 {
            cutoff = Date(timeIntervalSince1970: (cutoff.timeIntervalSince1970 / step).rounded(.down) * step)
        }
        let inWindow = lines.filter { $0.t >= cutoff }
        guard inWindow.count > maxLines else { return inWindow }
        guard step > 0 else { return Array(inWindow.suffix(maxLines)) }
        // Over the cap: drop from the front up to the next id that is a multiple of 10.
        let firstKept = inWindow[inWindow.count - maxLines].id
        let start = ((firstKept + 9) / 10) * 10
        let trimmed = inWindow.filter { $0.id >= start }
        return trimmed.isEmpty ? Array(inWindow.suffix(maxLines)) : trimmed
    }

    public func last(_ n: Int) -> [TimelineLine] { lock.lock(); defer { lock.unlock() }; return Array(lines.suffix(n)) }

    public func line(id: Int) -> TimelineLine? { lock.lock(); defer { lock.unlock() }; return lines.first { $0.id == id } }
}

public extension Array where Element == TimelineLine {
    var rendered: String { map(\.rendered).joined(separator: "\n") }
}
