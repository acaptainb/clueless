import AppKit
import SwiftUI
import CluelessCore

/// The screen the answerer was shown for the current card (T06): the timeline line that records it, whose
/// `snapshot` is the path of the saved JPEG, and a small copy for the panel.
struct ScreenReceipt {
    let line: TimelineLine
    /// nil until the file has been written (a few tens of milliseconds after the request started).
    var thumbnail: NSImage?
    /// The picture is shown at the full width of the card instead of as a thumbnail.
    var enlarged = false

    var url: URL? { line.snapshot.map { URL(fileURLWithPath: $0) } }
}

enum Snapshots {
    /// Longest side of the saved file: still readable when opened, about 200 to 400 KB as JPEG.
    static let savedSide = 1600
    /// Longest side of the copy kept in memory for the panel (the card is about 390 points wide, 2x).
    static let thumbSide = 800

    private static let stamp: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH-mm-ss-SSS"; return f
    }()

    static func url(in dir: URL, at date: Date) -> URL {
        dir.appendingPathComponent("screen-\(stamp.string(from: date)).jpg")
    }

    /// Returns the number of bytes written, or nil if the image could not be encoded or saved.
    static func write(_ shot: CGImage, to url: URL) -> Int? {
        guard let data = ScreenText.jpeg(shot, maxSide: savedSide, quality: 0.8) else { return nil }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return data.count
        } catch {
            return nil
        }
    }

    static func scaled(_ image: CGImage, maxSide: Int) -> CGImage? {
        let scale = min(1.0, Double(maxSide) / Double(max(image.width, image.height)))
        let w = max(1, Int(Double(image.width) * scale)), h = max(1, Int(Double(image.height) * scale))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }
}

extension AppState {
    /// Called once per card, right after the screenshot was read. It adds nothing to the time to the answer:
    /// the timeline line is appended at once with the path the file will have, and the JPEG is written in
    /// the background while Bonsai is already working.
    func keepReceipt(of shot: CGImage, text: String) {
        let now = Date()
        let url = Snapshots.url(in: snapshotDir, at: now)
        let summary = text.isEmpty ? "(screenshot, no text recognised)" : String(text.prefix(300))
        let line = timeline.append(.screen, summary, snapshot: url.path, at: now)
        screenReceipt = ScreenReceipt(line: line, thumbnail: nil)
        Task.detached { [weak self] in
            let t0 = Date()
            let bytes = Snapshots.write(shot, to: url)
            let small = bytes == nil ? nil : Snapshots.scaled(shot, maxSide: Snapshots.thumbSide)
            if let bytes {
                Log.write("[receipt] L\(line.id) screen saved to \(url.path) (\(bytes / 1024) KB, \(String(format: "%.0f", Date().timeIntervalSince(t0) * 1000)) ms)")
            } else {
                Log.write("[receipt] L\(line.id) screen could NOT be saved to \(url.path)")
            }
            await self?.receiptSaved(line.id, small)
        }
    }

    private func receiptSaved(_ id: Int, _ small: CGImage?) {
        // A newer card may have replaced this one while the file was being written.
        guard screenReceipt?.line.id == id else { return }
        if let small {
            screenReceipt?.thumbnail = NSImage(cgImage: small, size: NSSize(width: small.width, height: small.height))
        } else {
            screenReceipt = nil   // nothing to show: do not offer a receipt that does not exist
        }
    }
}

/// The screen receipt in a card: a thumbnail next to the time and the first words read from the screen.
/// Click the thumbnail to enlarge it in place; the arrow opens the saved file.
/// No `@State` here: it is a macro whose plugin ships with Xcode, and the Mac mini has none.
struct ScreenReceiptRow: View {
    let receipt: ScreenReceipt
    let toggle: () -> Void
    private var enlarged: Bool { receipt.enlarged }

    private var caption: String {
        let words = receipt.line.text.split(whereSeparator: \.isNewline).joined(separator: " · ")
        return "\(receipt.line.clockTime)  \(receipt.line.label): \(words)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                if let image = receipt.thumbnail, !enlarged {
                    Button(action: toggle) { picture(image).frame(width: 96) }
                        .buttonStyle(.plain).help("Show the screen Clueless read for this answer")
                }
                Text(caption).font(.caption).foregroundStyle(.secondary).lineLimit(enlarged ? 2 : 3)
                Spacer(minLength: 0)
                if let url = receipt.url, receipt.thumbnail != nil {
                    Button { NSWorkspace.shared.open(url) } label: { Image(systemName: "arrow.up.forward.square") }
                        .buttonStyle(.borderless).help("Open the saved screenshot")
                }
            }
            if let image = receipt.thumbnail, enlarged {
                Button(action: toggle) { picture(image) }
                    .buttonStyle(.plain).help("Click to shrink")
            }
        }
    }

    private func picture(_ image: NSImage) -> some View {
        Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.primary.opacity(0.15)))
    }
}
