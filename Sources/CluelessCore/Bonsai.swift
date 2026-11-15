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
    public static var speakerModels: URL { models.appendingPathComponent("argmax/speakerkit-coreml") }
    public static var sessions: URL { root.appendingPathComponent("sessions") }
}

public struct BonsaiStats: Sendable {
    public init() {}
    public init(seconds: Double) { self.seconds = seconds }
    public var seconds: Double = 0
    /// Streaming only: time until the first token arrived.
    public var firstTokenSeconds: Double = 0
    public var promptTokens: Int = 0
    public var outputTokens: Int = 0
    public var tokensPerSecond: Double = 0
    /// Prompt tokens the server reused from its cache instead of evaluating again (0 if it does not report this).
    /// `promptTokens` counts only the ones it had to evaluate.
    public var cachedTokens: Int = 0
    /// Time the server spent evaluating the prompt, before the first output token.
    public var promptSeconds: Double = 0

    /// Fill in from the `timings` object of a llama.cpp server response.
    mutating func read(timings tm: [String: Any]) {
        promptTokens = (tm["prompt_n"] as? Int) ?? 0
        cachedTokens = (tm["cache_n"] as? Int) ?? 0
        outputTokens = (tm["predicted_n"] as? Int) ?? 0
        tokensPerSecond = (tm["predicted_per_second"] as? Double) ?? 0
        promptSeconds = ((tm["prompt_ms"] as? Double) ?? 0) / 1000
    }
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
        /// Text, then the image, then more text. Keeps the text before the image reusable from the server's cache.
        case textImageText(String, pngOrJpeg: Data, String)
    }

    public func isUp() async -> Bool {
        var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/health")!)
        req.timeoutInterval = 1
        guard let (_, resp) = try? await URLSession.shared.data(for: req) else { return false }
        return (resp as? HTTPURLResponse)?.statusCode == 200
    }

    /// `onPartial`, when given, switches to streaming and is called with the text so far after every token.
    public func chat(system: String, user: Content, maxTokens: Int, thinking: Bool = false, json: Bool = false,
                     onPartial: (@Sendable (String) -> Void)? = nil) async throws -> (String, BonsaiStats) {
        var userContent: Any
        switch user {
        case .text(let s): userContent = s
        case .textAndImage(let s, let data):
            let mime = data.starts(with: [0xFF, 0xD8]) ? "image/jpeg" : "image/png"
            userContent = [
                ["type": "image_url", "image_url": ["url": "data:\(mime);base64,\(data.base64EncodedString())"]],
                ["type": "text", "text": s],
            ]
        case .textImageText(let before, let data, let after):
            let mime = data.starts(with: [0xFF, 0xD8]) ? "image/jpeg" : "image/png"
            let parts: [[String: Any]] = [
                ["type": "text", "text": before],
                ["type": "image_url", "image_url": ["url": "data:\(mime);base64,\(data.base64EncodedString())"]],
                ["type": "text", "text": after],
            ]
            userContent = parts
        }
        var body: [String: Any] = [
            "messages": [["role": "system", "content": system], ["role": "user", "content": userContent]],
            "max_tokens": thinking ? max(maxTokens, 8192) : maxTokens,
            "chat_template_kwargs": ["enable_thinking": thinking],
            "top_k": 20,
            // Reuse the evaluated prefix of the previous request (the default on current servers; stated so it is certain).
            "cache_prompt": true,
            // Sampling from the model card. presence_penalty is lowered for JSON: 1.5 fights repeated keys/quotes.
            "temperature": thinking ? 1.0 : (json ? 0.3 : 0.7),
            "top_p": thinking ? 0.95 : 0.8,
            "presence_penalty": json ? 0.0 : (thinking ? 1.0 : 1.5),
        ]
        if json { body["response_format"] = ["type": "json_object"] }
        if onPartial != nil { body["stream"] = true }

        var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/v1/chat/completions")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 180
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let t0 = Date()
        if let onPartial {
            // Server-sent events: one "data: {json}" line per token, then "data: [DONE]".
            let (bytes, resp) = try await URLSession.shared.bytes(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
                throw NSError(domain: "Bonsai", code: 1, userInfo: [NSLocalizedDescriptionKey:
                    "Bonsai server on port \(port) returned HTTP \((resp as? HTTPURLResponse)?.statusCode ?? 0)"])
            }
            var text = ""
            var stats = BonsaiStats()
            for try await line in bytes.lines {
                guard line.hasPrefix("data: ") else { continue }
                let payload = line.dropFirst(6)
                if payload == "[DONE]" { break }
                guard let obj = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any] else { continue }
                if let choices = obj["choices"] as? [[String: Any]], let delta = choices.first?["delta"] as? [String: Any],
                   let piece = delta["content"] as? String, !piece.isEmpty {
                    if text.isEmpty { stats.firstTokenSeconds = Date().timeIntervalSince(t0) }
                    text += piece
                    onPartial(text)
                }
                if let tm = obj["timings"] as? [String: Any] { stats.read(timings: tm) }
            }
            stats.seconds = Date().timeIntervalSince(t0)
            return (text, stats)
        }
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
        if let tm = obj["timings"] as? [String: Any] { stats.read(timings: tm) }
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

    /// Live text: prompts/watcher.txt. The built-in copy below is only used when that file cannot be read.
    static var system: String { Prompts.load("watcher") ?? builtInSystem }

    static let builtInSystem = """
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

/// How the answerer's request is laid out. The server reuses the longest part of the prompt that is identical
/// to the start of the previous request, so the order decides how much it has to evaluate again.
public enum PromptLayout: String, Sendable, CaseIterable {
    /// The original order: task instructions in the system prompt, image first. Asking a question after a
    /// catch-up (or attaching a new screenshot) makes the server evaluate nearly the whole prompt again.
    case classic
    /// What stays the same comes first: one system prompt for every task, then the timeline (it only grows at
    /// its end), then what changes per request: image, screen text, question, task instructions.
    case stable

    /// `CLUELESS_PROMPT_LAYOUT=classic` switches back without a rebuild.
    public static let current: PromptLayout = {
        PromptLayout(rawValue: ProcessInfo.processInfo.environment["CLUELESS_PROMPT_LAYOUT"] ?? "") ?? .stable
    }()
}

/// How the screen reaches the model. This is one of the things we benchmark.
/// `auto` = OCR text always, screenshot only when `ScreenPolicy` says the question needs it.
public enum ScreenMethod: String, Sendable, CaseIterable { case ocr, image, both, none, auto }

public struct Answerer: Sendable {
    public let client: BonsaiClient
    public let layout: PromptLayout
    public init(client: BonsaiClient = BonsaiClient(port: BonsaiClient.answererPort), layout: PromptLayout = .current) {
        self.client = client; self.layout = layout
    }

    /// The part of the system prompt that is the same for every task.
    static var commonSystem: String { Prompts.load("answerer_common") ?? builtInCommon }
    /// The instructions for one task (question, catch-up or notes).
    static func taskInstructions(_ task: AnswerTask) -> String {
        Prompts.load("answerer_" + task.rawValue) ?? builtInTask(task)
    }

    /// Live text: prompts/answerer_common.txt plus prompts/answerer_<task>.txt, joined by one newline.
    /// The built-in copies below are only used when those files cannot be read.
    static func system(_ task: AnswerTask) -> String {
        commonSystem + "\n" + taskInstructions(task)
    }

    static let builtInCommon = """
    You are Clueless, a private on-device copilot. You get a numbered timeline of what was just said \
    (lines look like "[L12 14:03:10] Speaker: text") and what is on the user's screen.
    Use only that material. If it does not contain the answer, say so briefly. Be concise and concrete.
    "sources" must list the L-numbers of the timeline lines you actually used (integers only, most relevant first). \
    Use [] if you only used the screen.
    Reply with JSON only.
    """

    static func builtInTask(_ task: AnswerTask) -> String {
        switch task {
        case .question:
            return """
            The user asks a question about the lecture or document. Answer in 1 to 3 short sentences, plain text, no markdown.
            JSON shape: {"answer": "...", "sources": [12, 9]}
            """
        case .catchUp:
            return """
            The user lost the thread and needs to be caught up right now.
            "asked" and "missed" are about what people SAID, so take them only from the TIMELINE. Anything under ON SCREEN is background that nobody said: never report it as said, asked or missed, and never describe the screen.
            - "asked": the question or request most recently directed at the user in the timeline, in one sentence. "" if nobody asked them anything.
            - "missed": the 1 to 2 most important things said in the timeline recently, in one or two sentences.
            - "reply": one natural sentence the user could say out loud next. "" if no reply is needed.
            JSON shape: {"asked": "...", "missed": "...", "reply": "...", "sources": [215, 212]}
            """
        case .notes:
            return """
            Write end-of-session notes in three parts, in this order: DECISIONS, ACTION ITEMS, OPEN QUESTIONS. Leave out a part that has nothing in it.
            Say who decided, who owns each action item and by when if a time was said, and who raised each open question. Use the speakers' names exactly as they appear in the timeline; "You" is the user.
            Plain text with short lines, no markdown.
            JSON shape: {"answer": "...", "sources": [3, 8, 14]}
            """
        }
    }

    /// The part of a request that only grows at its end from one request to the next.
    static func head(lines: [TimelineLine], userName: String) -> String {
        var head = ""
        if !userName.isEmpty { head += "User name: \(userName)\n\n" }
        head += "TIMELINE (newest last):\n" + (lines.isEmpty ? "(nothing said yet)" : lines.rendered) + "\n\n"
        return head
    }

    /// Reads the timeline into the server's cache ahead of time, so that when a card is asked for only the
    /// question and the newest lines are left to read. Without it a question late in a long session waits
    /// seconds before its first word (3.4 s with 120 lines on the Mac mini). Call it with the same lines a
    /// question would get, when new lines have arrived and no card is being written. Only the stable layout
    /// benefits. Returns the seconds it took, or nil if the server did not answer.
    @discardableResult
    public func prewarm(lines: [TimelineLine], userName: String = "") async -> Double? {
        guard layout == .stable, !lines.isEmpty else { return nil }
        let reply = try? await client.chat(system: Self.commonSystem, user: .text(Self.head(lines: lines, userName: userName)),
                                           maxTokens: 1)
        return reply?.1.seconds
    }

    /// How much screen text a catch-up gets. Questions get up to 4,000 characters.
    static let catchUpScreenChars = 600

    public func answer(_ task: AnswerTask, lines: [TimelineLine], screenText: String, image: Data? = nil,
                       question: String? = nil, userName: String = "", thinking: Bool = false,
                       onPartial: (@Sendable (Card) -> Void)? = nil) async throws -> Card {
        // `head` only grows at its end from one request to the next (the timeline is append-only), so the
        // server can reuse it. `tail` is what changes every time.
        // Nothing was said: there is nothing to catch up on, and no reason to ask a model. (Asked anyway, it
        // filled the card from whatever text was on the screen.)
        if task == .catchUp, lines.isEmpty {
            var card = Card(task: task)
            card.missed = "Nothing was said in the last few minutes."
            return card
        }
        let head = Self.head(lines: lines, userName: userName)
        var tail = ""
        if task == .catchUp {
            // A catch-up is about what was said. The screen is only there to help read the words (a slide
            // title, a name), so it is short and labelled as something nobody said.
            if !screenText.isEmpty { tail += "ON SCREEN (background only, nobody said this):\n\(String(screenText.prefix(Self.catchUpScreenChars)))\n\n" }
            if image != nil { tail += "The attached image is the user's current screen (background only).\n\n" }
        } else {
            if !screenText.isEmpty { tail += "SCREEN TEXT (OCR of the user's current screen):\n\(String(screenText.prefix(4000)))\n\n" }
            if image != nil { tail += "The attached image is the user's current screen.\n\n" }
        }
        if let question { tail += "QUESTION: \(question)\n" }
        tail += "Task: \(task.rawValue)"

        let system: String
        let content: BonsaiClient.Content
        switch layout {
        case .classic:
            system = Self.system(task)
            if let image { content = .textAndImage(head + tail, pngOrJpeg: image) } else { content = .text(head + tail) }
        case .stable:
            system = Self.commonSystem
            tail += "\n\n" + Self.taskInstructions(task)
            if let image { content = .textImageText(head, pngOrJpeg: image, tail) } else { content = .text(head + tail) }
        }
        let valid = Set(lines.map(\.id))
        let stream: (@Sendable (String) -> Void)? = onPartial.map { callback in
            { text in callback(Self.card(task, from: text, validIDs: valid, partial: true)) }
        }
        let (out, stats) = try await client.chat(system: system, user: content,
                                                 maxTokens: task == .notes ? 500 : 220, thinking: thinking, json: true,
                                                 onPartial: stream)
        var card = Self.card(task, from: out, validIDs: valid, partial: false)
        card.stats = stats
        return card
    }

    /// Turn model output into a card. With `partial`, the JSON is still being written: pull out whatever
    /// string fields have started so the UI can show them as they grow.
    static func card(_ task: AnswerTask, from out: String, validIDs: Set<Int>, partial: Bool) -> Card {
        var card = Card(task: task, raw: out)
        if !partial, let obj = JSONRepair.object(out) {
            card.asked = (obj["asked"] as? String) ?? ""
            card.missed = (obj["missed"] as? String) ?? ""
            card.reply = (obj["reply"] as? String) ?? ""
            card.answer = (obj["answer"] as? String) ?? ""
            let ids = (obj["sources"] as? [Any] ?? []).compactMap { v -> Int? in
                if let i = v as? Int { return i }
                if let s = v as? String { return Int(s.trimmingCharacters(in: CharacterSet(charactersIn: "L "))) }
                return nil
            }
            // Receipts must point at real lines. Drop anything the model invented.
            var seen = Set<Int>()
            card.sources = ids.filter { validIDs.contains($0) && seen.insert($0).inserted }
        } else if partial || out.contains("\"") {
            card.asked = JSONRepair.partialString(out, key: "asked")
            card.missed = JSONRepair.partialString(out, key: "missed")
            card.reply = JSONRepair.partialString(out, key: "reply")
            card.answer = JSONRepair.partialString(out, key: "answer")
            if !partial, card.asked.isEmpty, card.missed.isEmpty, card.answer.isEmpty {
                card.answer = out.trimmingCharacters(in: .whitespacesAndNewlines)
            }
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

    /// Value of a string field in JSON that may still be incomplete (no closing quote yet).
    public static func partialString(_ s: String, key: String) -> String {
        guard let r = s.range(of: "\"\(key)\"\\s*:\\s*\"", options: .regularExpression) else { return "" }
        var out = "", escaped = false
        for ch in s[r.upperBound...] {
            if escaped {
                switch ch { case "n": out.append("\n"); case "t": out.append("\t"); case "u": break; default: out.append(ch) }
                escaped = false
            } else if ch == "\\" { escaped = true }
            else if ch == "\"" { break }
            else { out.append(ch) }
        }
        return out
    }
}
