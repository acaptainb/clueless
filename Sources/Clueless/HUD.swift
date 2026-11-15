import SwiftUI
import Darwin
import CluelessCore

/// Memory of other processes on this Mac, read from the kernel (no shell, no network).
enum ProcessMemory {
    /// Physical footprint in MB, the number Activity Monitor shows as "Memory". nil if the process is gone.
    static func footprintMB(pid: pid_t) -> Int? {
        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
        }
        return result == 0 ? Int(info.ri_phys_footprint / 1_048_576) : nil
    }

    /// Footprint of a Bonsai server started by scripts/servers.sh, found through its pid file.
    /// A pid file can outlive its server, so the process must also be called llama-server.
    static func serverMB(_ name: String) -> Int? {
        let file = Paths.root.appendingPathComponent(".run/\(name).pid")
        guard let text = try? String(contentsOf: file, encoding: .utf8),
              let pid = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)), pid > 0 else { return nil }
        var name = [CChar](repeating: 0, count: 256)
        guard proc_name(pid, &name, UInt32(name.count)) > 0, String(cString: name).hasPrefix("llama-server") else { return nil }
        return footprintMB(pid: pid)
    }
}

extension AppState {
    /// Called every 2 s from the HUD timer.
    func refreshServerMemory() {
        hud.answererMB = ProcessMemory.serverMB("answerer") ?? 0
        hud.watcherMB = ProcessMemory.serverMB("watcher") ?? 0
    }
}

/// The strip at the bottom of the panel: proof of what is running, where, and how fast.
struct HUDView: View {
    let hud: AppState.HUD

    var body: some View {
        VStack(spacing: 6) {
            Divider()
            statusRow
            HStack(spacing: 0) {
                tile("stt", seconds(hud.stt), "Argmax WhisperKit: time to transcribe the last chunk of audio")
                tile("ocr", seconds(hud.ocr), "Apple Vision: time to read the text on the screen")
                tile("watcher", seconds(hud.watch), "Bonsai watcher: time to decide whether the last line needs you")
                tile("first word", seconds(hud.last.firstTokenSeconds), "Bonsai answerer: time until the first word of the last card")
                tile("whole card", seconds(hud.last.seconds), "Bonsai answerer: time for the whole last card")
                tile("tok/s", hud.last.tokensPerSecond > 0 ? String(format: "%.0f", hud.last.tokensPerSecond) : "–",
                     "Bonsai answerer: output tokens per second on the last card")
                tile("cached", cached, "Share of the last prompt the server reused from its cache instead of reading again")
            }
        }
    }

    private var statusRow: some View {
        HStack(spacing: 8) {
            Label(hud.online ? "network on" : "network off", systemImage: hud.online ? "wifi" : "wifi.slash")
                .foregroundStyle(hud.online ? Color.secondary : Color.green)
                .help(hud.online ? "The network is on but unused: Clueless only talks to 127.0.0.1. Turn Wi-Fi off and everything keeps working."
                      : "No network. Everything you see is running on this Mac.")
            Spacer(minLength: 0)
            server("9B", up: hud.answerer, mb: hud.answererMB, help: "Bonsai 2 9B answerer on port 8080")
            server("watcher", up: hud.watcher, mb: hud.watcherMB, help: "Bonsai 2 watcher on port 8082")
            Text("app \(memory(hud.ramMB))").help("Clueless itself, including the Argmax speech models")
            if total > 0 {
                Text("= \(memory(total))").foregroundStyle(.primary)
                    .help("Memory in use by Clueless and both Bonsai servers together")
            }
        }
        .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
    }

    private var total: Int {
        hud.answererMB + hud.watcherMB > 0 ? hud.ramMB + hud.answererMB + hud.watcherMB : 0
    }

    private var cached: String {
        let all = hud.last.cachedTokens + hud.last.promptTokens
        guard hud.last.seconds > 0, all > 0 else { return "–" }
        return "\(Int((Double(hud.last.cachedTokens) / Double(all) * 100).rounded()))%"
    }

    private func server(_ name: String, up: Bool, mb: Int, help: String) -> some View {
        HStack(spacing: 3) {
            Circle().fill(up ? Color.green : Color.red).frame(width: 6, height: 6)
            Text(mb > 0 ? "\(name) \(memory(mb))" : name)
        }
        .help(help + (up ? "" : " (not running)"))
    }

    private func tile(_ label: String, _ value: String, _ help: String) -> some View {
        VStack(spacing: 1) {
            Text(value).font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(.primary)
            Text(label).font(.system(size: 8)).foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity)
        .help(help)
    }

    private func seconds(_ value: Double) -> String { value > 0 ? String(format: "%.1fs", value) : "–" }

    private func memory(_ mb: Int) -> String {
        mb >= 1000 ? String(format: "%.1f GB", Double(mb) / 1024) : "\(mb) MB"
    }
}
