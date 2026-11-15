// clueless-bench prewarm [port]
// How long does a question wait for its first word late in a long session, and how much of that goes away
// when the timeline has been read into the server's cache beforehand (Answerer.prewarm)?
import Foundation
import CluelessCore

func benchPrewarm(port: Int) async throws {
    let answerer = Answerer(client: BonsaiClient(port: port))
    let sentences = [
        "At every step we compute the gradient of the loss with respect to the weights.",
        "The gradient points in the direction of steepest increase, so we move the weights the other way.",
        "How far we move is controlled by the learning rate, which we set before training starts.",
        "In practice we do not compute the gradient over the whole data set, only over a small random batch.",
        "That is called stochastic gradient descent, and it is what almost everyone uses today.",
        "One common improvement is momentum, which keeps a running average of past gradients.",
    ]
    let tl = Timeline()
    let base = Date().addingTimeInterval(-280)
    for i in 0..<117 { tl.append(.them, "Point \(i + 1). " + sentences[i % sentences.count], at: base.addingTimeInterval(Double(i) * 2.2)) }
    tl.append(.them, "My office hours this week moved to Tuesday at 3, in room 204.", at: base.addingTimeInterval(259))
    tl.append(.them, "Homework 3 is due on Thursday at 11:59 pm.", at: base.addingTimeInterval(262))
    tl.append(.them, "Next week we will cover adaptive methods such as Adam.", at: base.addingTimeInterval(265))
    let lines = tl.all
    let question = "When are office hours this week?"
    func other() async { _ = try? await answerer.client.chat(system: "You are terse.", user: .text("Say OK."), maxTokens: 3) }
    func ask(_ label: String, _ lines: [TimelineLine]) async throws {
        let card = try await answerer.answer(.question, lines: lines, screenText: "", question: question)
        let right = hit(card.answer, ["tuesday", "3|three"])
        print("\(pad(label, 46)) first token \(f(card.stats.firstTokenSeconds))s, whole card \(f(card.stats.seconds))s, "
              + "\(card.stats.promptTokens) tokens read, \(card.stats.cachedTokens) cached, \(right ? "right" : "WRONG: " + String(card.answer.prefix(60)))")
    }
    print("\(lines.count) lines in the timeline")
    for run in 1...2 {
        await other()                                   // something else was asked: the cache is cold
        try await ask("run \(run): cold", lines)
        await other()
        let warm = await answerer.prewarm(lines: lines)
        try await ask("run \(run): after prewarm (\(f(warm ?? -1))s in the background)", lines)
        // Three more lines arrive, the cache is topped up, then the question comes.
        let more = lines + [
            TimelineLine(id: 201, t: Date(), source: .them, text: "One more thing about the midterm."),
            TimelineLine(id: 202, t: Date(), source: .them, text: "It covers lectures one through eight."),
            TimelineLine(id: 203, t: Date(), source: .them, text: "You may bring one page of handwritten notes."),
        ]
        let top = await answerer.prewarm(lines: more)
        try await ask("run \(run): 3 new lines, top-up \(f(top ?? -1))s", more)
    }
}
