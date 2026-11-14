import Foundation

/// Appends to .run/app.log under the project root (and stderr), so the app can be debugged
/// however it was launched.
public enum Log {
    private static let handle: FileHandle? = {
        let dir = Paths.root.appendingPathComponent(".run")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("app.log")
        if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
        let h = try? FileHandle(forWritingTo: url)
        _ = try? h?.seekToEnd()
        return h
    }()
    private static let lock = NSLock()

    public static func write(_ message: String) {
        lock.lock(); defer { lock.unlock() }
        handle?.write(Data((message + "\n").utf8))
    }
}
