// clueless-bench grounding [port]
// Catch-up cards must come from what was SAID. On the Mac mini a card summarised the terminal text that
// happened to be on screen, and with an empty transcript it invented "you were asked" from the screen.
// Cases are in bench/grounding.json; each runs three times.
import Foundation
import CluelessCore

struct GroundingData: Decodable {
    struct Case: Decodable {
        let name: String
        let lines: [CallData.Line]
        let screen: String
        let asked_empty: Bool?
        let asked_any: [String]?
        let missed_any: [String]?
        let missed_none: [String]?
        let sources_empty: Bool?
    }
    let user: String
    let screens: [String: String]
    let cases: [Case]
}

func benchGrounding(port: Int) async throws {
    let data: GroundingData = loadCases("grounding")
    let answerer = Answerer(client: BonsaiClient(port: port))
    print("prompts: \(Prompts.summary)")
    var passed = 0, total = 0, seconds = 0.0
    for c in data.cases {
        let tl = Timeline()
        let base = Date().addingTimeInterval(-60)
        for (i, line) in c.lines.enumerated() {
            tl.append(TimelineLine.Source(rawValue: line.source) ?? .them, line.text, speaker: line.speaker,
                      at: base.addingTimeInterval(Double(i) * 6))
        }
        var ok = 0
        var problems: [String] = []
        for _ in 1...3 {
            let card = try await answerer.answer(.catchUp, lines: tl.all, screenText: data.screens[c.screen] ?? "", userName: data.user)
            seconds += card.stats.seconds
            var why: [String] = []
            let missed = card.missed.lowercased()
            if c.asked_empty == true, !card.asked.isEmpty { why.append("asked should be empty, got: \(card.asked.prefix(90))") }
            if let want = c.asked_any, !hit(card.asked, want) { why.append("asked misses \(want), got: \(card.asked.prefix(90))") }
            if let want = c.missed_any, !hit(card.missed, want) { why.append("missed lacks \(want), got: \(card.missed.prefix(110))") }
            if let banned = c.missed_none, let word = banned.first(where: { missed.contains($0.lowercased()) }) {
                why.append("missed repeats the screen (\"\(word)\"): \(card.missed.prefix(110))")
            }
            if c.sources_empty == true, !card.sources.isEmpty { why.append("sources should be empty, got \(card.sources)") }
            if why.isEmpty { ok += 1 } else if problems.count < 2 { problems.append(why.joined(separator: "; ")) }
        }
        passed += ok; total += 3
        print("\(ok)/3  \(c.name)")
        for p in problems { print("   x \(p)") }
    }
    print("== grounding: \(passed)/\(total) cards built from what was said, avg \(f(seconds / Double(max(total, 1))))s")
}
