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

    /// Lines from the last `seconds`, capped at `maxLines` (newest kept).
    public func recent(seconds: TimeInterval, maxLines: Int = 60, now: Date = Date()) -> [TimelineLine] {
        lock.lock(); defer { lock.unlock() }
        let cutoff = now.addingTimeInterval(-seconds)
        return Array(lines.filter { $0.t >= cutoff }.suffix(maxLines))
    }

    public func last(_ n: Int) -> [TimelineLine] { lock.lock(); defer { lock.unlock() }; return Array(lines.suffix(n)) }

    public func line(id: Int) -> TimelineLine? { lock.lock(); defer { lock.unlock() }; return lines.first { $0.id == id } }
}

public extension Array where Element == TimelineLine {
    var rendered: String { map(\.rendered).joined(separator: "\n") }
}
