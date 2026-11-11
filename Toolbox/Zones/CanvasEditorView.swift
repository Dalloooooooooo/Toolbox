import Cocoa

/// Canvas layouts: free zones, even overlapping. Drag a zone to move it, its borders or corners to
/// resize it (they snap to the screen edges and to the other zones); × or Delete removes it.
final class CanvasEditorView: ZoneEditingView {
    private struct Edges: OptionSet {
        let rawValue: Int
        static let left = Edges(rawValue: 1), right = Edges(rawValue: 2), top = Edges(rawValue: 4), bottom = Edges(rawValue: 8)
    }

    private var selected: Int?
    private var dragging: (index: Int, edges: Edges, start: CGRect, mouse: CGPoint)?
    private let minSide: CGFloat = 80
    private let grip: CGFloat = 10

    init(zones: [CGRect]) {
        super.init(frame: .zero)
        self.zones = zones
    }
    required init?(coder: NSCoder) { fatalError() }

    func addZone() {
        let k = CGFloat(zones.count % 6) * 0.04
        zones.append(CGRect(x: 0.25 + k, y: 0.2 + k, width: 0.4, height: 0.5))
        selected = zones.count - 1
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        // the selected zone is drawn on top, so it's always fully visible
        let order = zones.indices.filter { $0 != selected } + (selected.map { [$0] } ?? [])
        for i in order {
            let r = toView(zones[i])
            drawZone(r, number: i + 1, selected: i == selected)
            let x = closeButton(r)
            NSColor.windowBackgroundColor.setFill()
            NSBezierPath(ovalIn: x).fill()
            NSColor.secondaryLabelColor.setStroke()
            let cross = NSBezierPath()
            cross.move(to: CGPoint(x: x.minX + 6, y: x.minY + 6)); cross.line(to: CGPoint(x: x.maxX - 6, y: x.maxY - 6))
            cross.move(to: CGPoint(x: x.maxX - 6, y: x.minY + 6)); cross.line(to: CGPoint(x: x.minX + 6, y: x.maxY - 6))
            cross.lineWidth = 1.5
            cross.stroke()
        }
        drawGuides()
    }

    private func closeButton(_ r: CGRect) -> CGRect { CGRect(x: r.maxX - 32, y: r.minY + 10, width: 20, height: 20) }

    // MARK: Mouse

    /// Topmost zone under the point (the selected one counts as topmost).
    private func zoneIndex(at p: CGPoint) -> Int? {
        if let s = selected, toView(zones[s]).insetBy(dx: -2, dy: -2).contains(p) { return s }
        return zones.indices.reversed().first { toView(zones[$0]).insetBy(dx: -2, dy: -2).contains(p) }
    }

    private func edges(at p: CGPoint, of r: CGRect) -> Edges {
        var e: Edges = []
        if abs(p.x - r.minX) <= grip { e.insert(.left) } else if abs(p.x - r.maxX) <= grip { e.insert(.right) }
        if abs(p.y - r.minY) <= grip { e.insert(.top) } else if abs(p.y - r.maxY) <= grip { e.insert(.bottom) }
        return e
    }

    override func mouseMoved(with event: NSEvent) {
        let p = point(event)
        guard let i = zoneIndex(at: p) else { NSCursor.arrow.set(); return }
        let e = edges(at: p, of: toView(zones[i]))
        if e.contains(.left) || e.contains(.right) { (e.contains(.top) || e.contains(.bottom) ? NSCursor.crosshair : NSCursor.resizeLeftRight).set() }
        else if e.contains(.top) || e.contains(.bottom) { NSCursor.resizeUpDown.set() }
        else { NSCursor.openHand.set() }
    }

    override func mouseDown(with event: NSEvent) {
        let p = point(event)
        guard let i = zoneIndex(at: p) else { selected = nil; needsDisplay = true; return }
        let r = toView(zones[i])
        if closeButton(r).contains(p) { remove(i); return }
        selected = i
        dragging = (i, edges(at: p, of: r), r, p)
        if dragging?.edges.isEmpty == true { NSCursor.closedHand.set() }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let d = dragging else { return }
        let p = point(event)
        let dx = p.x - d.mouse.x, dy = p.y - d.mouse.y
        var r = d.start
        snappedTo = []
        defer { guides = snappedTo }
        if d.edges.isEmpty {
            r = r.offsetBy(dx: dx, dy: dy)
            r.origin.x = snapped(r.minX, r.maxX, excluding: d.index, vertical: true)
            r.origin.y = snapped(r.minY, r.maxY, excluding: d.index, vertical: false)
            r.origin.x = min(max(0, r.minX), bounds.width - r.width)
            r.origin.y = min(max(0, r.minY), bounds.height - r.height)
        } else {
            var x0 = r.minX, x1 = r.maxX, y0 = r.minY, y1 = r.maxY
            if d.edges.contains(.left) { x0 = min(max(0, snap(x0 + dx, d.index, true)), x1 - minSide) }
            if d.edges.contains(.right) { x1 = max(min(bounds.width, snap(x1 + dx, d.index, true)), x0 + minSide) }
            if d.edges.contains(.top) { y0 = min(max(0, snap(y0 + dy, d.index, false)), y1 - minSide) }
            if d.edges.contains(.bottom) { y1 = max(min(bounds.height, snap(y1 + dy, d.index, false)), y0 + minSide) }
            r = CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
        }
        zones[d.index] = CGRect(x: r.minX / bounds.width, y: r.minY / bounds.height,
                                width: r.width / bounds.width, height: r.height / bounds.height)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if dragging != nil { mouseDragged(with: event) } // the last movements may have been merged into the release
        dragging = nil
        guides = []
        mouseMoved(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 || event.keyCode == 117, let s = selected { remove(s); return } // ⌫ / ⌦
        super.keyDown(with: event)
    }

    private func remove(_ i: Int) {
        zones.remove(at: i)
        selected = nil
        dragging = nil
        needsDisplay = true
    }

    // MARK: Snapping to the screen edges, its fractions (1/4, 1/3, 1/2…) and the other zones

    private var snappedTo: [Guide] = []

    private func lines(excluding i: Int, vertical: Bool) -> [(value: CGFloat, label: String?)] {
        let size = vertical ? bounds.width : bounds.height
        var out: [(CGFloat, String?)] = [(0, nil), (size, nil)] + Self.fractions.map { ($0.value * size, $0.label) }
        for (j, z) in zones.enumerated() where j != i {
            let r = toView(z)
            out += vertical ? [(r.minX, nil), (r.maxX, nil)] : [(r.minY, nil), (r.maxY, nil)]
        }
        return out
    }

    private func note(_ line: (value: CGFloat, label: String?), vertical: Bool) {
        guard let label = line.label else { return }
        snappedTo.removeAll { $0.vertical == vertical }
        snappedTo.append((vertical, line.value / max(1, vertical ? bounds.width : bounds.height), label))
    }

    private func snap(_ v: CGFloat, _ i: Int, _ vertical: Bool) -> CGFloat {
        guard let best = lines(excluding: i, vertical: vertical).min(by: { abs($0.value - v) < abs($1.value - v) }),
              abs(best.value - v) <= snapDistance else { return v }
        note(best, vertical: vertical)
        return best.value
    }

    /// A moved zone: either of its two edges snaps, whichever is closer to a line.
    private func snapped(_ lo: CGFloat, _ hi: CGFloat, excluding i: Int, vertical: Bool) -> CGFloat {
        let ls = lines(excluding: i, vertical: vertical)
        guard let a = ls.min(by: { abs($0.value - lo) < abs($1.value - lo) }),
              let b = ls.min(by: { abs($0.value - hi) < abs($1.value - hi) }) else { return lo }
        let useLo = abs(a.value - lo) <= abs(b.value - hi)
        let line = useLo ? a : b
        let shift = line.value - (useLo ? lo : hi)
        guard abs(shift) <= snapDistance else { return lo }
        note(line, vertical: vertical)
        return lo + shift
    }
}
