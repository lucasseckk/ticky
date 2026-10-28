import AppKit

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let extent = CGFloat(pixels)
        NSColor(calibratedRed: 0.25, green: 0.23, blue: 0.65, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: extent * 0.06, y: extent * 0.06, width: extent * 0.88, height: extent * 0.88),
                     xRadius: extent * 0.2, yRadius: extent * 0.2).fill()
        NSColor.white.set()
        ClockIcon.draw(in: NSRect(x: extent * 0.15, y: extent * 0.15, width: extent * 0.7, height: extent * 0.7), completed: true)
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
assert(ClockIcon.menuImage(completed: true).isTemplate)
assert(ClockIcon.menuImage(completed: false).size == NSSize(width: 18, height: 18))
assert(ClockIcon.menuImage(completed: true).tiffRepresentation != ClockIcon.menuImage(completed: false).tiffRepresentation)
assert(Set(ClockIcon.Mood.allCases.map { ClockIcon.badge($0, size: 64).tiffRepresentation! }).count == ClockIcon.Mood.allCases.count)
