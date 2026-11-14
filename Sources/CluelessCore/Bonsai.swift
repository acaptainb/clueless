import Foundation

/// Where things live on disk. Override the root with CLUELESS_ROOT.
public enum Paths {
    public static let root: URL = {
        if let env = ProcessInfo.processInfo.environment["CLUELESS_ROOT"] { return URL(fileURLWithPath: env) }
        // Sources/CluelessCore/Bonsai.swift -> repo root (fine for a hackathon build run on the build machine)
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }()
    public static var models: URL { root.appendingPathComponent("models") }
    public static var whisperModel: URL {
        models.appendingPathComponent("argmax/models/argmaxinc/whisperkit-coreml/openai_whisper-large-v3-v20240930_626MB")
    }
    public static var whisperTokenizer: URL { models.appendingPathComponent("argmax") }
    public static var ttsModels: URL { models.appendingPathComponent("argmax/ttskit-coreml") }
    public static var ttsTokenizer: URL { models.appendingPathComponent("argmax/tts-tokenizer") }
    public static var sessions: URL { root.appendingPathComponent("sessions") }
}

public struct BonsaiStats: Sendable {
    public init() {}
    public init(seconds: Double) { self.seconds = seconds }
    public var seconds: Double = 0
    public var promptTokens: Int = 0
    public var outputTokens: Int = 0
    public var tokensPerSecond: Double = 0
}

/// Minimal client for the llama.cpp OpenAI-compatible server. Localhost only.
public struct BonsaiClient: Sendable {
    public static let answererPort = 8080
    public static let watcherPort = 8082
    public let port: Int
    public init(port: Int) { self.port = port }

    public enum Content {
        case text(String)
        case textAndImage(String, pngOrJpeg: Data)
    }

    public func isUp() async -> Bool {
        var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/health")!)
        req.timeoutInterval = 1
        guard let (_, resp) = try? await URLSession.shared.data(for: req) else { return false }
        return (resp as? HTTPURLResponse)?.statusCode == 200
    }

    public func chat(system: String, user: Content, maxTokens: Int, thinking: Bool = false,
                     json: Bool = false) async throws -> (String, BonsaiStats) {
        var userContent: Any
        switch user {
        case .text(let s): userContent = s
        case .textAndImage(let s, let data):
            let mime = data.starts(with: [0xFF, 0xD8]) ? "image/jpeg" : "image/png"
            userContent = [
                ["type": "image_url", "image_url": ["url": "data:\(mime);base64,\(data.base64EncodedString())"]],
                ["type": "text", "text": s],
            ]
        }
        var body: [String: Any] = [
            "messages": [["role": "system", "content": system], ["role": "user", "content": userContent]],
            "max_tokens": thinking ? max(maxTokens, 8192) : maxTokens,
            "chat_template_kwargs": ["enable_thinking": thinking],
            "top_k": 20,
            // Sampling from the model card. presence_penalty is lowered for JSON: 1.5 fights repeated keys/quotes.
            "temperature": thinking ? 1.0 : (json ? 0.3 : 0.7),
            "top_p": thinking ? 0.95 : 0.8,
            "presence_penalty": json ? 0.0 : (thinking ? 1.0 : 1.5),
        ]
        if json { body["response_format"] = ["type": "json_object"] }

        var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/v1/chat/completions")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 180
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let t0 = Date()
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200,
              let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String
        else {
            throw NSError(domain: "Bonsai", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "Bonsai server on port \(port) returned: \(String(data: data.prefix(300), encoding: .utf8) ?? "?")"])
        }
        var stats = BonsaiStats(seconds: Date().timeIntervalSince(t0))
        if let tm = obj["timings"] as? [String: Any] {
            stats.promptTokens = (tm["prompt_n"] as? Int) ?? 0
            stats.outputTokens = (tm["predicted_n"] as? Int) ?? 0
            stats.tokensPerSecond = (tm["predicted_per_second"] as? Double) ?? 0
        }
        return (content, stats)
    }
}

// MARK: - Watcher (2B)

public struct Decision: Sendable, Equatable {
    public var needsUser: Bool
    public var reason: String      // "name" | "question" | "none"
    public var usedModel: Bool
    public var seconds: Double
}

public struct Watcher: Sendable {
    public let client: BonsaiClient
    public init(client: BonsaiClient = BonsaiClient(port: BonsaiClient.watcherPort)) { self.client = client }

    /// Cheap code check. No model call unless the newest line has the user's name or a question mark.
    public static func precheck(_ line: TimelineLine, userName: String) -> Bool {
        line.text.contains("?") || mentions(line.text, userName)
    }

    public static func mentions(_ text: String, _ userName: String) -> Bool {
        guard !userName.isEmpty else { return false }
        return text.range(of: "\\b\(NSRegularExpression.escapedPattern(for: userName))\\b",
                          options: [.regularExpression, .caseInsensitive]) != nil
    }

    static let system = """
    You watch a live meeting transcript for one user. Decide whether the NEWEST line needs that user to respond now.
    Reply with JSON only: {"needs_user": true|false, "reason": "name"|"question"|"none"}

    needs_user is true only in two cases:
    - reason "name": the speaker is talking TO the user by name (asks them, or calls on them).
    - reason "question": the speaker asks the whole group an open question that anyone, including the user, should answer.

    needs_user is false, reason "none", when:
    - the line is addressed to a different person by name ("Dana, did you send it?")
    - the user's name is only mentioned, not addressed ("I spoke with <user> yesterday", "<user> fixed that")
    - the question is rhetorical or the speaker answers it themselves
    - the line is a statement

    Examples for a user named Alex:
    "Alex, what's your take?" -> {"needs_user": true, "reason": "name"}
    "Does anybody object to that plan?" -> {"needs_user": true, "reason": "question"}
    "Dana, can you send the invoice?" -> {"needs_user": false, "reason": "none"}
    "Alex sent the invoice on Monday." -> {"needs_user": false, "reason": "none"}
    "Why is it slow? Because of the cache." -> {"needs_user": false, "reason": "none"}
    """

    /// True when the line opens by addressing a known participant other than the user ("Priya, where are we...").
    /// That is a code check, so no model call is needed.
    public static func addressesSomeoneElse(_ line: TimelineLine, lines: [TimelineLine], userName: String) -> Bool {
        guard !mentions(line.text, userName) else { return false }
        let others = Set(lines.compactMap(\.speaker)).subtracting([line.speaker ?? "", userName])
        guard let first = line.text.split(whereSeparator: { ",.!? ".contains($0) }).first else { return false }
        return others.contains { $0.caseInsensitiveCompare(String(first)) == .orderedSame }
    }

    public func watch(_ lines: [TimelineLine], userName: String) async -> Decision {
        guard let newest = lines.last, newest.source == .them, Self.precheck(newest, userName: userName),
              !Self.addressesSomeoneElse(newest, lines: lines, userName: userName) else {
            return Decision(needsUser: false, reason: "none", usedModel: false, seconds: 0)
        }
        let prompt = "User name: \(userName)\n\nTranscript (newest last):\n\(Array(lines.suffix(6)).rendered)"
        do {
            let (out, stats) = try await client.chat(system: Self.system, user: .text(prompt), maxTokens: 30, json: true)
            if let obj = JSONRepair.object(out) {
                let needs = (obj["needs_user"] as? Bool) ?? false
                let reason = (obj["reason"] as? String) ?? (needs ? "question" : "none")
                return Decision(needsUser: needs, reason: needs ? reason : "none", usedModel: true, seconds: stats.seconds)
            }
        } catch {}
        // Model down or unparseable: fall back to the code check alone, name only.
        let named = Self.mentions(newest.text, userName)
        return Decision(needsUser: named, reason: named ? "name" : "none", usedModel: false, seconds: 0)
    }
}

// MARK: - Answerer (9B)

public enum AnswerTask: String, Sendable { case catchUp = "catch_up", question, notes }

public struct Card: Sendable {
    public var task: AnswerTask
    public var asked: String = ""     // catch-up: what you were asked
    public var missed: String = ""    // catch-up: what you missed
    public var reply: String = ""     // catch-up: suggested reply
    public var answer: String = ""    // question / notes
    public var sources: [Int] = []
    public var stats = BonsaiStats()
    public var raw: String = ""

    public init(task: AnswerTask, stats: BonsaiStats = BonsaiStats(), raw: String = "") {
        self.task = task; self.stats = stats; self.raw = raw
    }

    /// What gets read aloud.
    public var spoken: String {
        switch task {
        case .catchUp: return [asked, missed, reply.isEmpty ? "" : "You could say: \(reply)"].filter { !$0.isEmpty }.joined(separator: " ")
        default: return answer
        }
    }
}

/// How the screen reaches the model. This is one of the things we benchmark.
public enum ScreenMethod: String, Sendable, CaseIterable { case ocr, image, both, none }

public struct Answerer: Sendable {
    public let client: BonsaiClient
    public init(client: BonsaiClient = BonsaiClient(port: BonsaiClient.answererPort)) { self.client = client }

    static func system(_ task: AnswerTask) -> String {
        let common = """
        You are Clueless, a private on-device copilot. You get a numbered timeline of what was just said \
        (lines look like "[L12 14:03:10] Speaker: text") and what is on the user's screen.
        Use only that material. If it does not contain the answer, say so briefly. Be concise and concrete.
        "sources" must list the L-numbers of the timeline lines you actually used (integers only, most relevant first). \
        Use [] if you only used the screen.
        Reply with JSON only.
        """
        switch task {
        case .question:
            return common + """

            The user asks a question about the lecture or document. Answer in 1 to 3 short sentences, plain text, no markdown.
            JSON shape: {"answer": "...", "sources": [12, 9]}
            """
        case .catchUp:
            return common + """

            The user lost the thread and needs to be caught up right now.
            - "asked": the question or request most recently directed at the user, in one sentence. "" if nobody asked them anything.
            - "missed": the 1 to 2 most important things said recently, in one or two sentences.
            - "reply": one natural sentence the user could say out loud next. "" if no reply is needed.
            JSON shape: {"asked": "...", "missed": "...", "reply": "...", "sources": [215, 212]}
            """
        case .notes:
            return common + """

            Write end-of-session notes: decisions, action items with owner, and open questions. Attribute by speaker. \
            Plain text with short lines, no markdown.
            JSON shape: {"answer": "...", "sources": [3, 8, 14]}
            """
        }
    }

    public func answer(_ task: AnswerTask, lines: [TimelineLine], screenText: String, image: Data? = nil,
                       question: String? = nil, userName: String = "", thinking: Bool = false) async throws -> Card {
        var prompt = ""
        if !userName.isEmpty { prompt += "User name: \(userName)\n\n" }
        prompt += "TIMELINE (newest last):\n" + (lines.isEmpty ? "(nothing said yet)" : lines.rendered) + "\n\n"
        if !screenText.isEmpty { prompt += "SCREEN TEXT (OCR of the user's current screen):\n\(String(screenText.prefix(4000)))\n\n" }
        if image != nil { prompt += "The attached image is the user's current screen.\n\n" }
        if let question { prompt += "QUESTION: \(question)\n" }
        prompt += "Task: \(task.rawValue)"

        let content: BonsaiClient.Content = image.map { .textAndImage(prompt, pngOrJpeg: $0) } ?? .text(prompt)
        let (out, stats) = try await client.chat(system: Self.system(task), user: content,
                                                 maxTokens: task == .notes ? 500 : 220, thinking: thinking, json: true)
        var card = Card(task: task, stats: stats, raw: out)
        if let obj = JSONRepair.object(out) {
            card.asked = (obj["asked"] as? String) ?? ""
            card.missed = (obj["missed"] as? String) ?? ""
            card.reply = (obj["reply"] as? String) ?? ""
            card.answer = (obj["answer"] as? String) ?? ""
            let valid = Set(lines.map(\.id))
            let ids = (obj["sources"] as? [Any] ?? []).compactMap { v -> Int? in
                if let i = v as? Int { return i }
                if let s = v as? String { return Int(s.trimmingCharacters(in: CharacterSet(charactersIn: "L "))) }
                return nil
            }
            // Receipts must point at real lines. Drop anything the model invented.
            var seen = Set<Int>()
            card.sources = ids.filter { valid.contains($0) && seen.insert($0).inserted }
        } else {
            card.answer = out.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return card
    }
}

/// Small models sometimes wrap JSON in prose or code fences. Pull out the first object.
public enum JSONRepair {
    public static func object(_ s: String) -> [String: Any]? {
        guard let start = s.firstIndex(of: "{"), let end = s.lastIndex(of: "}"), start < end else { return nil }
        let slice = String(s[start...end])
        return (try? JSONSerialization.jsonObject(with: Data(slice.utf8))) as? [String: Any]
    }
}
