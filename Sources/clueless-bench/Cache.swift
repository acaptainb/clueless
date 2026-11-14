// clueless-bench cache [port]
//
// T09: how much of the prompt does the server have to evaluate again on each request?
// Plays a session that grows, like the live app: every request sees a few more timeline lines than the one
// before, and questions alternate with catch-ups. Runs it once per prompt layout and prints, per request,
// the prompt tokens evaluated, the tokens reused from the cache, and the time to the first token.
// The first request of each run is cold (the cache holds the other layout), so the averages skip it.
import Foundation
import CluelessCore

private struct CacheStep {
    let task: AnswerTask
    let lines: Int          // how many timeline lines exist at this point
    let question: String?
}

private func cell(_ s: String, _ n: Int) -> String { s.count >= n ? s + " " : s + String(repeating: " ", count: n - s.count) }
private func secs(_ d: Double) -> String { String(format: "%.2f", d) }

func benchCache(port: Int) async throws {
    let call: CallData = loadCases("call")
    let questions: [QuestionCase] = loadCases("questions")
    let all = sampleCall(call).all
    guard all.count >= 6, questions.count >= 4 else {
        print("error: the cache benchmark needs at least 6 lines in bench/call.json and 4 questions")
        exit(1)
    }
    let n = all.count
    let steps: [CacheStep] = [
        CacheStep(task: .question, lines: n - 4, question: questions[0].q),
        CacheStep(task: .question, lines: n - 3, question: questions[1].q),
        CacheStep(task: .catchUp, lines: n - 3, question: nil),
        CacheStep(task: .question, lines: n - 2, question: questions[2].q),
        CacheStep(task: .catchUp, lines: n - 1, question: nil),
        CacheStep(task: .question, lines: n, question: questions[3].q),
        CacheStep(task: .catchUp, lines: n, question: nil),
    ]
    print("== prompts: \(Prompts.summary)")
    for layout in PromptLayout.allCases {
        let answerer = Answerer(client: BonsaiClient(port: port), layout: layout)
        print("\nlayout: \(layout.rawValue)")
        print(cell("#", 3), cell("task", 9), cell("lines", 6), cell("evaluated", 10), cell("cached", 7),
              cell("prompt s", 9), cell("first tok s", 12), "total s")
        var evaluated = 0, cached = 0, first = 0.0, prompt = 0.0, total = 0.0, counted = 0
        for (i, step) in steps.enumerated() {
            let lines = Array(all.prefix(step.lines))
            let card = try await answerer.answer(step.task, lines: lines, screenText: "", question: step.question,
                                                 userName: call.user, onPartial: { _ in })
            let s = card.stats
            print(cell("\(i + 1)", 3), cell(step.task.rawValue, 9), cell("\(step.lines)", 6), cell("\(s.promptTokens)", 10),
                  cell("\(s.cachedTokens)", 7), cell(secs(s.promptSeconds), 9), cell(secs(s.firstTokenSeconds), 12), secs(s.seconds))
            if i > 0 {
                evaluated += s.promptTokens; cached += s.cachedTokens
                first += s.firstTokenSeconds; prompt += s.promptSeconds; total += s.seconds; counted += 1
            }
        }
        let d = Double(max(counted, 1))
        print("== \(layout.rawValue): avg prompt tokens evaluated \(evaluated / max(counted, 1)), cached \(cached / max(counted, 1)), "
              + "prompt \(secs(prompt / d))s, first token \(secs(first / d))s, whole card \(secs(total / d))s (requests 2 to \(steps.count))")
    }
    print("\nLower 'evaluated' and 'first tok' in the stable layout is the win. If 'cached' is 0 everywhere, this server "
          + "build does not report it; compare 'evaluated' and 'prompt s' instead.")
}
