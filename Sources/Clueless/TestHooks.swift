import Foundation
import CluelessCore

// Test hook, for the Mac mini only (T45). Three of the fixes in T41 could only be judged by a person at the
// keyboard: a question typed while a card is being written, Option+S during a spoken card, and play pressed
// twice. `CLUELESS_TEST_T41=<seconds after launch>` does those three things by itself and writes what
// happened to the log as `[test41]` lines, so they can be checked with nobody there.
// It needs something to listen to: the lecture through `CLUELESS_AUDIO_FILE`, or through the speakers.
extension AppState {
    func runT41TestIfAsked() {
        guard let delay = Double(ProcessInfo.processInfo.environment["CLUELESS_TEST_T41"] ?? "") else { return }
        Log.write("[test41] will start \(Int(delay)) s after launch")
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1e9))
            await self?.t41Test()
        }
    }

    private func t41Pause(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1e9))
    }

    /// Waits until no card is being written. Returns false if that took longer than `limit`.
    private func t41Idle(_ limit: Double = 60) async -> Bool {
        let t0 = Date()
        while thinking, Date().timeIntervalSince(t0) < limit { await t41Pause(0.1) }
        return !thinking
    }

    private func t41Test() async {
        guard recording else { Log.write("[test41] not recording, nothing tested"); return }

        // 1. A question typed while a card is being written is answered afterwards, not dropped.
        _ = await t41Idle()
        let q = ProcessInfo.processInfo.environment["CLUELESS_TEST_T41_QUESTION"] ?? "What is this lecture about?"
        Log.write("[test41] 1: catch-up now, and the question \"\(q)\" 0.4 s later")
        catchUp()
        await t41Pause(0.4)
        let overlapped = thinking
        question = q
        ask()
        // The question's card carries the question as its title.
        let t0 = Date()
        while !(cardTitle == q && !thinking && card != nil), Date().timeIntervalSince(t0) < 60 { await t41Pause(0.1) }
        let answered = cardTitle == q && !thinking && card != nil
        Log.write("[test41] 1: \(answered ? "PASS" : "FAIL"): a card was being written when the question was asked: \(overlapped) (must be true for this to mean anything); the question got its card: \(answered), \(String(format: "%.1f", Date().timeIntervalSince(t0))) s after it was asked")

        // 2. Option+S while a card is still streaming: the voice must not start again for that card.
        await t41Pause(6)                      // let the question's answer finish being spoken
        _ = await t41Idle()
        Log.write("[test41] 2: session notes now (a long card), Option+S 2.5 s later")
        notes()
        await t41Pause(2.5)
        let streaming = thinking
        stopSpeaking()
        Log.write("[test41] 2: STOP SPEAKING pressed; the card was still being written: \(streaming) (must be true). Any \"[speech] queued\" line between here and the line \"[test41] 2: end\" is a FAIL")
        _ = await t41Idle()
        await t41Pause(1)
        Log.write("[test41] 2: end")

        // 3. Play pressed twice must not open two capture streams. Only with live capture: the file hook
        //    never opens a stream. A second stream would keep delivering audio after pause.
        if ProcessInfo.processInfo.environment["CLUELESS_AUDIO_FILE"] != nil {
            Log.write("[test41] 3: skipped (file hook; needs live capture with audio playing)")
        } else {
            await stop()
            await t41Pause(1.5)
            Log.write("[test41] 3: paused; pressing play twice at once")
            toggle()
            toggle()
            await t41Pause(12)
            let started = recording
            await stop()
            await t41Pause(4)                  // chunks already cut may still be transcribed
            let before = timeline.last(1).first?.id ?? 0
            await t41Pause(12)
            let after = timeline.last(1).first?.id ?? 0
            Log.write("[test41] 3: \(started && after == before ? "PASS" : "FAIL"): recording after the double press: \(started); new timeline lines during 12 s of pause: \(after - before) (must be 0; more means a second stream is still running). Also check the lines before this for doubled transcript text")
            await start()
        }
        Log.write("[test41] done")
    }
}
