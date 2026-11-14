import Foundation

/// Prompt text lives in `prompts/*.txt` at the top of the repo, so it can be edited without touching Swift
/// (on Windows too). Files are read on every request: an edit takes effect on the next question, with no
/// rebuild and no app restart. If a file is missing or empty the built-in copy in Bonsai.swift is used, so
/// the app never breaks because of a prompt file.
public enum Prompts {
    /// The working copy this binary was built from. Data files (`prompts/`, `bench/`) are read from here and
    /// not from CLUELESS_ROOT, because check.sh points CLUELESS_ROOT at the main checkout (for the models)
    /// while testing a branch in another working copy. The branch's own files must be the ones tested.
    /// Override with CLUELESS_DATA.
    public static let dataRoot: URL = {
        if let env = ProcessInfo.processInfo.environment["CLUELESS_DATA"] { return URL(fileURLWithPath: env) }
        // Sources/CluelessCore/Prompts.swift -> repo root
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }()

    public static let names = ["watcher", "answerer_common", "answerer_question", "answerer_catch_up", "answerer_notes"]

    /// Text of `prompts/<name>.txt`, or nil when the file is missing or empty.
    /// Windows line endings and a byte-order mark (Notepad adds one) are removed.
    public static func load(_ name: String) -> String? {
        let url = dataRoot.appendingPathComponent("prompts").appendingPathComponent(name + ".txt")
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let text = raw.replacingOccurrences(of: "\u{FEFF}", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// The built-in copy of a prompt file (what is used when the file cannot be read).
    static func builtIn(_ name: String) -> String {
        switch name {
        case "watcher": return Watcher.builtInSystem
        case "answerer_common": return Answerer.builtInCommon
        case "answerer_question": return Answerer.builtInTask(.question)
        case "answerer_catch_up": return Answerer.builtInTask(.catchUp)
        case "answerer_notes": return Answerer.builtInTask(.notes)
        default: return ""
        }
    }

    /// Short form for benchmark output: are the prompt files being used?
    public static var summary: String {
        let missing = names.filter { load($0) == nil }
        return missing.isEmpty ? "all \(names.count) from prompts/*.txt" : "BUILT-IN used for \(missing.joined(separator: ", "))"
    }

    /// One line per prompt saying where its text comes from. Printed by `clueless-bench prompts`.
    public static func report() -> [String] {
        names.map { (name: String) -> String in
            guard let text = load(name) else { return "\(name): BUILT-IN (prompts/\(name).txt missing or empty)" }
            let same = text == builtIn(name)
            return "\(name): prompts/\(name).txt, \(text.count) chars, \(same ? "same as built-in" : "differs from built-in")"
        }
    }
}
