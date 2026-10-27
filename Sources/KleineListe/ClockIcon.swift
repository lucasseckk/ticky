import AppKit

// Shared vector artwork keeps the menu bar and Finder icons consistent.
enum ClockIcon {
    static func draw(in rect: NSRect, completed: Bool) {
        let scale = rect.width / 18
        let transform = NSAffineTransform()
        transform.translateX(by: rect.minX, yBy: rect.minY)
        transform.scale(by: scale)
        transform.concat()
        let outline = NSBezierPath(ovalIn: NSRect(x: 1.5, y: 1.5, width: 15, height: 15))
        outline.lineWidth = 1.5
        outline.stroke()
        let hands = NSBezierPath()
        hands.lineWidth = 1.3
        hands.lineCapStyle = .round
        hands.move(to: NSPoint(x: 9, y: 14))
        hands.line(to: NSPoint(x: 9, y: 10))
        hands.line(to: NSPoint(x: 11.5, y: 11.5))
        hands.stroke()
        for x in [5.5, 11.0] {
            NSBezierPath(ovalIn: NSRect(x: x, y: 7.5, width: 1.5, height: 1.5)).fill()
        }
        let mouth = NSBezierPath()
        mouth.lineWidth = 1.2
        mouth.lineCapStyle = .round
        mouth.move(to: NSPoint(x: 6, y: 5.5))
        if completed {
            mouth.curve(to: NSPoint(x: 12, y: 5.5), controlPoint1: NSPoint(x: 7, y: 3), controlPoint2: NSPoint(x: 11, y: 3))
        } else {
            mouth.line(to: NSPoint(x: 12, y: 5.5))
        }
        mouth.stroke()
        transform.invert()
        transform.concat()
    }

    static func menuImage(completed: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            NSColor.black.set()
            draw(in: rect, completed: completed)
            return true
        }
        image.isTemplate = true
        return image
    }
}
