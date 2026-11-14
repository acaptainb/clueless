import AppKit
let w = 1024, h = 640
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSColor.white.setFill(); NSRect(x: 0, y: 0, width: w, height: h).fill()
func draw(_ s: String, _ y: Int, _ size: CGFloat, bold: Bool = false) {
    let f = bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size)
    (s as NSString).draw(at: NSPoint(x: 60, y: y), withAttributes: [.font: f, .foregroundColor: NSColor.black])
}
draw("Lecture 7: Gradient Descent", 540, 44, bold: true)
draw("Update rule:   w  ←  w − η · ∇L(w)", 440, 32)
draw("• η (eta) is the learning rate, here η = 0.01", 360, 26)
draw("• Too large: the loss diverges. Too small: slow convergence.", 310, 26)
draw("• Batch size in today's example: 64", 260, 26)
draw("Homework 3 due Thursday 11:59 pm", 120, 24, bold: true)
draw("CS 4780 · Prof. Weinberger", 40, 18)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "shot.png"))
