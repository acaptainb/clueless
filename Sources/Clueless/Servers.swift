import Foundation
import CluelessCore

/// What a Bonsai server's /health says.
enum ServerHealth {
    case up        // HTTP 200
    case loading   // answering, but the model is still loading (HTTP 503)
    case dead      // nothing is listening on the port
    case busy      // listening but slow to answer: leave it alone
}

/// Talks to the two llama.cpp servers as processes: is each one alive, and start them when they are not.
/// Localhost only. Starting goes through scripts/servers.sh, so the flags stay in one place.
enum ServerControl {
    static var script: URL { Paths.root.appendingPathComponent("scripts/servers.sh") }
    static var log: URL { Paths.root.appendingPathComponent(".run/servers-start.log") }

    static func health(port: Int) async -> ServerHealth {
        var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/health")!)
        req.timeoutInterval = 1.5
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            return (resp as? HTTPURLResponse)?.statusCode == 200 ? .up : .loading
        } catch let error as URLError {
            return error.code == .cannotConnectToHost ? .dead : .busy
        } catch {
            return .busy
        }
    }

    /// Runs `servers.sh <args>` and waits for it. Returns whether it exited 0 and its last line of output.
    static func run(_ args: [String]) async -> (ok: Bool, lastLine: String) {
        let script = script, log = log
        return await Task.detached { () -> (ok: Bool, lastLine: String) in
            guard FileManager.default.fileExists(atPath: script.path) else {
                return (false, "\(script.path) not found. Set CLUELESS_ROOT to the main checkout.")
            }
            // Output goes to a file, not a pipe: the servers outlive the script and must not hold a pipe open.
            try? FileManager.default.createDirectory(at: log.deletingLastPathComponent(), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: log.path, contents: nil)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = [script.path] + args
            process.currentDirectoryURL = Paths.root
            process.standardInput = FileHandle.nullDevice
            if let out = try? FileHandle(forWritingTo: log) {
                process.standardOutput = out
                process.standardError = out
            }
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin"
            process.environment = env
            do { try process.run() } catch { return (false, "Could not run servers.sh: \(error.localizedDescription)") }
            process.waitUntilExit()
            let text = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
            let last = text.split(separator: "\n").last.map(String.init) ?? ""
            return (process.terminationStatus == 0, last)
        }.value
    }
}

extension AppState {
    /// Probe both servers, update the HUD dots and the warning row, and restart the servers when the
    /// answerer has died. Called at launch and every 2 s from the HUD timer.
    func checkServers() async {
        guard !startingServers else { return }
        async let a = ServerControl.health(port: BonsaiClient.answererPort)
        async let w = ServerControl.health(port: BonsaiClient.watcherPort)
        let (answerer, watcher) = await (a, w)
        // A slow /health while the model is generating is not a failure: keep the last known state.
        if answerer != .busy { hud.answerer = answerer == .up }
        if watcher != .busy { hud.watcher = watcher == .up }
        answererDeadChecks = answerer == .dead ? answererDeadChecks + 1 : 0

        if answerer == .up, watcher == .up {
            serverIssue = nil; serverCanRestart = false; autoStartAttempts = 0
            return
        }
        if answerer == .busy || watcher == .busy { return }
        if answerer == .loading || watcher == .loading {
            serverIssue = "Bonsai is loading its model. Answers will work in a few seconds."
            serverCanRestart = false
            return
        }
        if answerer == .dead {
            // Two failed checks in a row, never in the middle of an answer, and not in a tight loop.
            let allowed = ProcessInfo.processInfo.environment["CLUELESS_NO_SERVER_START"] == nil
            if allowed, answererDeadChecks >= 2, !thinking, autoStartAttempts < 3,
               Date().timeIntervalSince(lastServerStart) > 30 {
                autoStartAttempts += 1
                await startServers()
            } else if serverIssue == nil || !serverCanRestart {
                // Keep a more specific "did not start: ..." message if one is already showing.
                serverIssue = "The Bonsai answerer (9B, port 8080) is not running, so questions and catch-up will not work."
                serverCanRestart = true
            }
            return
        }
        // Only the watcher is down. Restarting would also restart the healthy answerer, so leave that
        // to the user: the name trigger is the only thing lost.
        serverIssue = "The Bonsai watcher (port 8082) is not running. Questions and catch-up still work; "
            + "the automatic \"you were called on\" trigger in call mode does not."
        serverCanRestart = true
    }

    /// Stop whatever is left of the servers and start both again. Also behind the Restart button.
    func startServers() async {
        guard !startingServers else { return }
        startingServers = true; lastServerStart = Date(); serverCanRestart = false
        serverIssue = "Starting the Bonsai servers. The models take about 15 seconds to load."
        Log.write("[servers] starting")
        _ = await ServerControl.run(["stop"])
        let result = await ServerControl.run(["start"])
        startingServers = false
        answererDeadChecks = 0
        Log.write("[servers] start \(result.ok ? "ok" : "failed"): \(result.lastLine)")
        if result.ok {
            serverIssue = nil
            hud.answerer = true; hud.watcher = true
        } else {
            serverIssue = "The Bonsai servers did not start: \(result.lastLine)"
            serverCanRestart = true
        }
    }

    func restartServers() { Task { autoStartAttempts = 0; await startServers() } }
}
