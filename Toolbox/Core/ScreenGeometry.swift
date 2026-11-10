import Cocoa

enum ScreenGeo {
    static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    /// NSScreen (origin at the bottom) → CG coordinates (origin at the top).
    static func cg(_ r: NSRect) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }
    static func ns(_ r: CGRect) -> NSRect {
        NSRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }
    static var mouse: CGPoint {
        let p = NSEvent.mouseLocation
        return CGPoint(x: p.x, y: primaryHeight - p.y)
    }
    static func screen(at p: CGPoint) -> NSScreen? {
        NSScreen.screens.first { cg($0.frame).insetBy(dx: -1, dy: -1).contains(p) }
    }
    /// The screen containing the largest part of the window.
    static func screen(for r: CGRect) -> NSScreen? {
        NSScreen.screens.max { a, b in
            let ia = cg(a.frame).intersection(r), ib = cg(b.frame).intersection(r)
            return (ia.isNull ? 0 : ia.width * ia.height) < (ib.isNull ? 0 : ib.width * ib.height)
        } ?? NSScreen.main
    }
    static func area(_ s: NSScreen) -> CGRect { cg(s.visibleFrame) }
    /// A "real" edge: there is no other monitor beyond it.
    static func isOuterEdge(_ p: CGPoint) -> Bool {
        !NSScreen.screens.contains { cg($0.frame).contains(p) }
    }
    /// The nearest monitor to the left or right (for ⌥⇧ arrows).
    static func neighbor(of s: NSScreen, left: Bool) -> NSScreen? {
        let f = cg(s.frame)
        return NSScreen.screens
            .filter { left ? cg($0.frame).midX < f.midX - 1 : cg($0.frame).midX > f.midX + 1 }
            .min { abs(cg($0.frame).midX - f.midX) < abs(cg($1.frame).midX - f.midX) }
    }
}

extension CGRect {
    func distance(to r: CGRect) -> CGFloat {
        max(abs(minX - r.minX), abs(minY - r.minY), abs(width - r.width), abs(height - r.height))
    }
    var area: CGFloat { isNull ? 0 : width * height }
}
