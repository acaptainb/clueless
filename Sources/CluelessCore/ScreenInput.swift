import Foundation
import CoreGraphics

/// Decides whether the screenshot itself is worth sending to the answerer.
///
/// Why this exists: with an image attached the first token takes about 6 s (the vision projector has to encode
/// it); with OCR text only it takes under 1 s. Most questions are about words on the screen or about what was
/// said, and OCR covers those. The image is only needed when the question is about something OCR cannot carry:
/// a diagram, a chart, layout, colour, or math notation (OCR turned `w ← w − η·∇L(w)` into `w = w - n • VL(W)`).
/// This is a code check, not a model call.
public enum ScreenPolicy {
    /// Longest side of the screenshot sent to the model. `CLUELESS_IMAGE_SIDE=768` overrides it without a rebuild.
    public static let imageMaxSide: Int = {
        if let s = ProcessInfo.processInfo.environment["CLUELESS_IMAGE_SIDE"], let n = Int(s), n >= 256 { return n }
        // 768 is the smallest size that kept every test question right, including the chart-colour questions
        // on the lecture slide (512 lost the colour). First token is about 0.6 s sooner than at 1024.
        // Measured on the Mac mini, BENCHMARKS.md section 7.
        return 768
    }()

    /// Below this many OCR characters the screen is mostly a picture (a video frame, a diagram, a photo).
    static let thinTextChars = 80

    /// A question word that starts with one of these is about something visual.
    static let visualStems = [
        "diagram", "chart", "graph", "plot", "figure", "pictur", "image", "photo", "drawing", "drawn", "illustrat",
        "color", "colour", "shape", "arrow", "curve", "axis", "axes", "table", "column", "layout", "sketch",
        "handwrit", "icon", "logo", "screenshot",
        // Math notation: OCR loses Greek letters, arrows and operators.
        "equation", "formula", "symbol", "notation", "expression", "derivation", "integral", "matrix",
    ]
    /// Whole words only (too short or too common to match as a prefix).
    static let visualWords: Set<String> = ["rule", "map", "math", "draw", "red", "green", "blue", "yellow"]
    static let visualPhrases = [
        "look like", "looks like", "you see", "on the left", "on the right", "at the top", "at the bottom",
        "in the corner", "in the middle",
    ]
    /// Words that point at the screen. They only count when OCR found almost no text.
    static let pointingWords: Set<String> = ["this", "that", "here", "screen", "slide", "page", "shown", "showing"]

    public static func needsImage(task: AnswerTask, question: String?, ocrText: String) -> Bool {
        // Catch-up and notes are about what was said. Screen text is enough context for them.
        guard task == .question, let question else { return false }
        let q = question.lowercased()
        if visualPhrases.contains(where: { q.contains($0) }) { return true }
        let words = q.split(whereSeparator: { !$0.isLetter }).map(String.init)
        for w in words {
            if visualWords.contains(w) { return true }
            if visualStems.contains(where: { w.hasPrefix($0) }) { return true }
        }
        if ocrText.count < thinTextChars, words.contains(where: { pointingWords.contains($0) }) { return true }
        return false
    }

    /// Turns `.auto` into what is actually sent for this request. Other methods pass through unchanged.
    public static func resolve(_ method: ScreenMethod, task: AnswerTask, question: String?, ocrText: String) -> ScreenMethod {
        guard method == .auto else { return method }
        return needsImage(task: task, question: question, ocrText: ocrText) ? .both : .ocr
    }
}

/// What the answerer gets from one screenshot: OCR text and, when it is worth the cost, a downscaled JPEG.
public struct ScreenInput: Sendable {
    public var text = ""
    public var image: Data?
    public var ocrSeconds = 0.0
    /// What was actually sent (`.auto` resolved to `.ocr` or `.both`).
    public var sent: ScreenMethod = .none

    public init() {}

    /// Runs OCR and JPEG encoding on the calling thread: call it off the main actor.
    public static func prepare(_ shot: CGImage, method: ScreenMethod, task: AnswerTask, question: String? = nil,
                               maxSide: Int = ScreenPolicy.imageMaxSide) -> ScreenInput {
        var out = ScreenInput()
        if method == .none { return out }
        if method != .image {
            let t0 = Date()
            out.text = ScreenText.recognize(shot)
            out.ocrSeconds = Date().timeIntervalSince(t0)
        }
        out.sent = ScreenPolicy.resolve(method, task: task, question: question, ocrText: out.text)
        if out.sent == .image || out.sent == .both { out.image = ScreenText.jpeg(shot, maxSide: maxSide) }
        return out
    }
}
