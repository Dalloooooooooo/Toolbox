import Cocoa

/// The Zones icon, drawn like an SF Symbol (outlines, tinted by the system): a small zone at the top left,
/// a medium one at the bottom left and a large one on the right.
enum ZonesIcon {
    static let image: NSImage = {
        let img = NSImage(size: NSSize(width: 22, height: 18), flipped: true) { _ in
            let line: CGFloat = 1.5
            let zones = [
                CGRect(x: 1, y: 1, width: 8, height: 5.5),    // small, top left
                CGRect(x: 1, y: 8, width: 8, height: 9),      // medium, bottom left
                CGRect(x: 10.5, y: 1, width: 10.5, height: 16), // large, right
            ]
            NSColor.black.setStroke()
            for z in zones {
                let p = NSBezierPath(roundedRect: z.insetBy(dx: line / 2, dy: line / 2), xRadius: 2, yRadius: 2)
                p.lineWidth = line
                p.stroke()
            }
            return true
        }
        img.isTemplate = true
        img.accessibilityDescription = String(localized: "Zones")
        return img
    }()
}
