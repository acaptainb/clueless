import Foundation
import CluelessCore

// The first screenshot of a launch can be very slow: on the Mac mini the first card of a live run waited
// about 15 s between the trigger and the saved receipt, and every later screenshot took under a second
// (Sun 2:32 am). The first card is the one a viewer sees, so pay that cost right after capture starts:
// take one screenshot and read it once, and throw the result away. Nothing is saved or sent.
extension AppState {
    func warmUpScreenWhenReady() {
        guard ProcessInfo.processInfo.environment["CLUELESS_NO_SCREEN_WARMUP"] == nil,
              ProcessInfo.processInfo.environment["CLUELESS_AUDIO_FILE"] == nil else { return }
        Task { [weak self] in
            // Wait for live capture (models loaded, permission granted), for five minutes at most.
            let t0 = Date()
            while self?.captureLive != true, Date().timeIntervalSince(t0) < 300 {
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            guard let self, self.captureLive else { return }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            let started = Date()
            do {
                let shot = try await self.capture.screenshot()
                let shotSeconds = Date().timeIntervalSince(started)
                // OCR and the downscaled JPEG, the same work a card does, off the main actor.
                let input = await Task.detached { ScreenInput.prepare(shot, method: .both, task: .question, question: nil) }.value
                Log.write("[warmup] first screenshot \(String(format: "%.2f", shotSeconds))s, OCR \(String(format: "%.2f", input.ocrSeconds))s (\(input.text.count) chars), \(String(format: "%.2f", Date().timeIntervalSince(started)))s in all; discarded")
            } catch {
                Log.write("[warmup] screenshot failed: \(error.localizedDescription)")
            }
        }
    }
}
