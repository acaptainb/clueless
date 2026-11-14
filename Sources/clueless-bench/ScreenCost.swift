// clueless-bench screencost <image> [qa.json] [sides]
//
// T08: what does the screenshot cost, and what do we lose without it?
//   1. Policy check (no model): does ScreenPolicy pick the image for visual questions and skip it for the rest?
//   2. Latency and accuracy per variant: OCR only, image only, image + OCR at each size, and auto.
// `sides` is a comma list of longest-side pixel sizes, default 1024,768,512.
// `qa.json` is [{"q": "...", "expect": ["a|b", "c"], "visual": false}, ...]; "visual" is optional.
// Self-contained on purpose (own helpers) so it does not depend on the rest of main.swift.
import Foundation
import CluelessCore

private struct CostQA { let q: String; let expect: [String]; let visual: Bool? }

private func col(_ s: String, _ n: Int) -> String { s.count >= n ? s + " " : s + String(repeating: " ", count: n - s.count) }
private func num(_ d: Double) -> String { String(format: "%.2f", d) }

/// Every entry of `expect` must appear in the answer; "a|b" means either.
private func matches(_ answer: String, _ expect: [String]) -> Bool {
    let a = answer.lowercased()
    return expect.allSatisfy { alt in alt.split(separator: "|").contains { a.contains($0.lowercased()) } }
}

private let policyCases: [(q: String, ocrChars: Int, image: Bool)] = [
    ("What is the learning rate in this example?", 900, false),
    ("When is the homework due?", 900, false),
    ("What did the professor say about overfitting?", 900, false),
    ("Summarize this slide.", 900, false),
    ("Who is presenting?", 900, false),
    ("What does this term mean?", 900, false),
    ("Write the update rule shown on the slide.", 900, true),
    ("What does the diagram show?", 900, true),
    ("Explain the equation at the top.", 900, true),
    ("Which curve is the validation loss?", 900, true),
    ("What colour is the decision boundary?", 900, true),
    ("What is in the second column of the table?", 900, true),
    ("What does the graph look like after epoch 10?", 900, true),
    ("What is this?", 20, true),
    ("What is on the screen?", 20, true),
    ("What did she just say?", 20, false),
]

func benchScreenCost(_ imagePath: String, _ qaPath: String?, _ sidesArg: String?) async throws {
    // 1. Policy, no model.
    var policyOK = 0
    var policyMisses: [String] = []
    for c in policyCases {
        let got = ScreenPolicy.needsImage(task: .question, question: c.q, ocrText: String(repeating: "x", count: c.ocrChars))
        if got == c.image { policyOK += 1 } else { policyMisses.append("\(c.q) -> image \(got), expected \(c.image)") }
    }
    let catchUpImage = ScreenPolicy.needsImage(task: .catchUp, question: nil, ocrText: "")
    if catchUpImage { policyMisses.append("catch-up asked for an image") } else { policyOK += 1 }
    print("policy: \(policyOK)/\(policyCases.count + 1)")
    for m in policyMisses { print("   x \(m)") }

    // 2. Latency and accuracy.
    guard let image = ScreenText.load(URL(fileURLWithPath: imagePath)) else {
        print("cannot read image \(imagePath)")
        exit(1)
    }
    let parsedSides = (sidesArg ?? "1024,768,512").split(separator: ",").compactMap { Int($0) }
    let sides = parsedSides.isEmpty ? [1024] : parsedSides
    let t0 = Date()
    let ocr = ScreenText.recognize(image)
    let ocrSeconds = Date().timeIntervalSince(t0)
    var jpegs: [Int: Data] = [:]
    for side in sides { jpegs[side] = ScreenText.jpeg(image, maxSide: side) }
    let sizes = sides.map { "\($0) px = \((jpegs[$0]?.count ?? 0) / 1024) KB" }.joined(separator: ", ")
    print("image \(image.width)x\(image.height). OCR \(num(ocrSeconds))s, \(ocr.count) chars. JPEG: \(sizes)\n")

    var qas = [
        CostQA(q: "What is the learning rate in this example?", expect: ["0.01"], visual: false),
        CostQA(q: "What batch size is used?", expect: ["64"], visual: false),
        CostQA(q: "When is the homework due?", expect: ["thursday"], visual: false),
        CostQA(q: "What happens if the learning rate is too large?", expect: ["diverge"], visual: false),
        CostQA(q: "Write the update rule shown on the slide.", expect: ["w", "η|eta|learning rate", "∇|gradient|nabla"], visual: true),
        CostQA(q: "Which course and professor is this?", expect: ["4780", "weinberger"], visual: false),
    ]
    if let qaPath, let data = FileManager.default.contents(atPath: qaPath),
       let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] {
        qas = arr.compactMap { item in
            guard let q = item["q"] as? String, let expect = item["expect"] as? [String] else { return nil }
            return CostQA(q: q, expect: expect, visual: item["visual"] as? Bool)
        }
    }

    var variants: [(name: String, method: ScreenMethod, side: Int)] = [("ocr", .ocr, sides[0]), ("image \(sides[0])", .image, sides[0])]
    for side in sides { variants.append(("both \(side)", .both, side)) }
    for side in sides { variants.append(("auto \(side)", .auto, side)) }

    let answerer = Answerer()
    // Warm the model so the first variant is not charged for loading.
    _ = try? await answerer.answer(.question, lines: [], screenText: "warm-up", question: "Say ok.")

    print(col("variant", 12), col("correct", 8), col("avg s", 7), col("first tok", 10), col("worst first", 12),
          col("prompt tok", 11), "images sent")
    for v in variants {
        var ok = 0, secs = 0.0, first = 0.0, worstFirst = 0.0, ptok = 0, images = 0
        var misses: [String] = []
        for qa in qas {
            let sent = ScreenPolicy.resolve(v.method, task: .question, question: qa.q, ocrText: ocr)
            let withImage = sent == .image || sent == .both
            if withImage { images += 1 }
            // The empty callback switches the client to streaming, which is what gives a first-token time.
            let card = try await answerer.answer(.question, lines: [],
                                                 screenText: sent == .image ? "" : ocr,
                                                 image: withImage ? jpegs[v.side] : nil,
                                                 question: qa.q) { _ in }
            secs += card.stats.seconds
            first += card.stats.firstTokenSeconds
            worstFirst = max(worstFirst, card.stats.firstTokenSeconds)
            ptok = max(ptok, card.stats.promptTokens)
            if matches(card.answer, qa.expect) { ok += 1 } else { misses.append("\(qa.q) -> \(card.answer.prefix(90))") }
        }
        let n = Double(max(qas.count, 1))
        print(col(v.name, 12), col("\(ok)/\(qas.count)", 8), col(num(secs / n), 7), col(num(first / n), 10),
              col(num(worstFirst), 12), col("\(ptok)", 11), "\(images)/\(qas.count)")
        for m in misses { print("   x \(m)") }
    }
}
