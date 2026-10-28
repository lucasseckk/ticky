import AppKit

// Shared vector artwork keeps the menu bar, Finder and notification icons consistent.
enum ClockIcon {
    /// Faces for the menu bar and notifications (#87).
    enum Mood: String, CaseIterable { case neutral, happy, stressed, overdue }

    static func draw(in rect: NSRect, completed: Bool) {
        draw(in: rect, mood: completed ? .happy : .neutral)
    }

    /// Draws in the current color; `drop` colors the sweat drop of the stressed face.
    static func draw(in rect: NSRect, mood: Mood, drop: NSColor? = nil) {
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
        for x in [6.25, 11.75] {
            if mood == .overdue {
                let cross = NSBezierPath()
                cross.lineWidth = 1
                cross.lineCapStyle = .round
                cross.move(to: NSPoint(x: x - 1, y: 7.25))
                cross.line(to: NSPoint(x: x + 1, y: 9.25))
                cross.move(to: NSPoint(x: x - 1, y: 9.25))
                cross.line(to: NSPoint(x: x + 1, y: 7.25))
                cross.stroke()
            } else {
                NSBezierPath(ovalIn: NSRect(x: x - 0.75, y: 7.5, width: 1.5, height: 1.5)).fill()
            }
        }
        let mouth = NSBezierPath()
        mouth.lineWidth = 1.2
        mouth.lineCapStyle = .round
        mouth.move(to: NSPoint(x: 6, y: 5.5))
        switch mood {
        case .neutral:
            mouth.line(to: NSPoint(x: 12, y: 5.5))
        case .happy:
            mouth.curve(to: NSPoint(x: 12, y: 5.5), controlPoint1: NSPoint(x: 7, y: 3), controlPoint2: NSPoint(x: 11, y: 3))
        case .stressed:
            // Wobbly mouth.
            mouth.curve(to: NSPoint(x: 9, y: 5.2), controlPoint1: NSPoint(x: 7, y: 6.6), controlPoint2: NSPoint(x: 8, y: 6.6))
            mouth.curve(to: NSPoint(x: 12, y: 5.2), controlPoint1: NSPoint(x: 10, y: 3.8), controlPoint2: NSPoint(x: 11, y: 3.8))
        case .overdue:
            mouth.removeAllPoints()
            mouth.move(to: NSPoint(x: 6.5, y: 4))
            mouth.curve(to: NSPoint(x: 11.5, y: 4), controlPoint1: NSPoint(x: 7.5, y: 6), controlPoint2: NSPoint(x: 10.5, y: 6))
        }
        mouth.stroke()
        if mood == .stressed {
            // Sweat drop on the forehead, left of the hands.
            NSGraphicsContext.saveGraphicsState()
            drop?.setFill()
            let tear = NSBezierPath()
            tear.move(to: NSPoint(x: 4.6, y: 14))
            tear.curve(to: NSPoint(x: 4.6, y: 10.4), controlPoint1: NSPoint(x: 3.2, y: 12), controlPoint2: NSPoint(x: 3.2, y: 10.4))
            tear.curve(to: NSPoint(x: 4.6, y: 14), controlPoint1: NSPoint(x: 6, y: 10.4), controlPoint2: NSPoint(x: 6, y: 12))
            tear.fill()
            NSGraphicsContext.restoreGraphicsState()
        }
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

    /// Colored face in the style of the app icon, used as notification attachment and in the pop-up.
    static func badge(_ mood: Mood, size: CGFloat = 256) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let colors: [Mood: NSColor] = [
                .neutral: NSColor(calibratedRed: 0.25, green: 0.23, blue: 0.65, alpha: 1),
                .happy: NSColor(calibratedRed: 0.20, green: 0.62, blue: 0.40, alpha: 1),
                .stressed: NSColor(calibratedRed: 0.90, green: 0.55, blue: 0.13, alpha: 1),
                .overdue: NSColor(calibratedRed: 0.82, green: 0.22, blue: 0.20, alpha: 1),
            ]
            colors[mood]!.setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: size * 0.06, dy: size * 0.06), xRadius: size * 0.2, yRadius: size * 0.2).fill()
            NSColor.white.set()
            draw(in: rect.insetBy(dx: size * 0.15, dy: size * 0.15), mood: mood, drop: NSColor(calibratedRed: 0.62, green: 0.86, blue: 1, alpha: 1))
            return true
        }
    }
}
