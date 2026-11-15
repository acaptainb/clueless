import Foundation
import ScreenCaptureKit
import CluelessCore

/// Keeps capture alive: when the stream stops with an error, or goes quiet without saying so, the
/// app starts a new one by itself. A stop the user asked for (the pause button, or "Stop sharing" in
/// the macOS menu bar) is respected and never undone.
extension AppState {
    /// No buffer of any kind for this long while recording counts as a stalled stream.
    static let captureStallSeconds: TimeInterval = 15
    /// After this many failed restarts in a row the app stops trying and says so.
    static let captureMaxRestarts = 8

    /// Bookkeeping after any successful `capture.start`.
    func captureDidStart() {
        captureLive = true
        captureStartedAt = Date()
        if captureWatchdog == nil {
            captureWatchdog = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.checkCaptureStall() }
            }
        }
    }

    /// The stream told us it stopped.
    func captureStopped(_ error: Error?) {
        guard captureLive else { return }          // already handled, or stopped on purpose
        captureLive = false
        recording = false
        let ns = error as NSError?
        Log.write("[capture] stopped: \(ns?.domain ?? "") \(ns?.code ?? 0) \(error?.localizedDescription ?? "")")
        if let ns, ns.domain == SCStreamErrorDomain, ns.code == SCStreamError.Code.userStopped.rawValue {
            wantRecording = false
            status = "Capture was stopped from the menu bar. Press play to resume."
            return
        }
        guard wantRecording else { status = "Paused"; return }
        restartCapture(reason: error?.localizedDescription ?? "the stream stopped")
    }

    /// The stream is supposedly running but has delivered nothing for a while.
    private func checkCaptureStall() {
        guard captureLive, recording, wantRecording, !restartingCapture else { return }
        let quiet = Date().timeIntervalSince(max(capture.lastBufferAt, captureStartedAt))
        guard quiet > Self.captureStallSeconds else { return }
        Log.write("[capture] stalled: no buffers for \(Int(quiet)) s")
        captureLive = false
        recording = false
        restartCapture(reason: "no audio arrived for \(Int(quiet)) s")
    }

    private func restartCapture(reason: String) {
        guard !restartingCapture else { return }
        restartingCapture = true
        // What was said just before the stream was lost is still waiting in the chunkers: transcribe it now.
        // The chunkers are reset once the new stream is up, and those words were dropped then.
        cutBufferedAudio()
        // A stream that ran for a while before failing is a new problem, not the same one again.
        if Date().timeIntervalSince(captureStartedAt) > 20 { captureRestarts = 0 }
        let lostAt = Date()
        Task {
            defer { restartingCapture = false }
            while wantRecording, captureRestarts < Self.captureMaxRestarts {
                captureRestarts += 1
                status = "Capture stopped (\(reason)). Restarting, try \(captureRestarts)…"
                // 0.5 s, 1 s, 2 s, 4 s, then 8 s between tries.
                let delay = min(8, 0.5 * pow(2, Double(captureRestarts - 1)))
                try? await Task.sleep(nanoseconds: UInt64(delay * 1e9))
                guard wantRecording else { break }
                await capture.stop()                 // drop what is left of the old stream
                do {
                    try await capture.start(microphone: mode == .call)
                    // Pause may have been pressed while the stream was starting. `stop()` found no stream
                    // to stop then, so without this check recording came back on by itself after a pause.
                    guard wantRecording else {
                        await capture.stop()
                        status = "Paused"
                        Log.write("[capture] paused during a restart: the new stream was stopped again")
                        break
                    }
                    resetChunkers()                  // half-filled chunks from before the gap are stale
                    captureDidStart()
                    recording = true
                    status = "Listening"
                    let gap = Date().timeIntervalSince(lostAt)
                    timeline.append(.system, "Capture restarted after a \(String(format: "%.0f", gap)) s gap (\(reason))")
                    Log.write("[capture] restarted on try \(captureRestarts) after \(String(format: "%.1f", gap)) s")
                    return
                } catch {
                    Log.write("[capture] restart try \(captureRestarts) failed: \(error.localizedDescription)")
                }
            }
            if wantRecording {
                wantRecording = false
                status = "Capture stopped and could not be restarted (\(reason)). Check Screen Recording permission, then press play."
            }
        }
    }
}
