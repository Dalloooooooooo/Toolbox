import Cocoa

/// Grid layouts: zones that fill the screen without overlapping.
/// Click splits the zone under the pointer (a horizontal line; with ⇧ a vertical one), dragging a border
/// moves it for all the zones along it, dragging across zones selects them to merge them.
final class GridEditorView: ZoneEditingView {
    /// A border between zones: the line `coord` (x if vertical), with the zones on either side.
    private struct Divider {
        let vertical: Bool
        var coord: CGFloat
        let before: [Int] // zones ending at the line (left / above)
        let after: [Int]  // zones starting at it (right / below)
    }

    private var hover: CGPoint?
    private var divider: Divider?      // under the pointer or being dragged
    private var draggingDivider = false
    private var anchor: Int?           // zone where a click / selection started
    private var downPoint: CGPoint = .zero
    private var selecting = false
    private var selection: Set<Int> = []
    private var mergeButton: NSButton?
    private var preview: (zone: Int, at: CGFloat, vertical: Bool)? // where a click would split (0…1)
    private let minSide: CGFloat = 60  // points
    private let eps: CGFloat = 0.0005

    init(zones: [CGRect]) {
        super.init(frame: .zero)
        self.zones = zones.isEmpty ? [CGRect(x: 0, y: 0, width: 1, height: 1)] : zones
    }
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    private var splitVertically: Bool { NSEvent.modifierFlags.contains(.shift) }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        for (i, z) in zones.enumerated() { drawZone(toView(z), number: i + 1, selected: selection.contains(i)) }
        let accent = NSColor.controlAccentColor
        if let d = divider {
            // the border that will move
            let line = NSBezierPath()
            for i in d.before + d.after {
                let r = toView(zones[i])
                if d.vertical {
                    let x = d.coord * bounds.width
                    line.move(to: CGPoint(x: x, y: r.minY)); line.line(to: CGPoint(x: x, y: r.maxY))
                } else {
                    let y = d.coord * bounds.height
                    line.move(to: CGPoint(x: r.minX, y: y)); line.line(to: CGPoint(x: r.maxX, y: y))
                }
            }
            accent.setStroke()
            line.lineWidth = 5
            line.stroke()
        } else if let pv = preview {
            // where the click would split
            let r = toView(zones[pv.zone])
            let line = NSBezierPath()
            if pv.vertical {
                let x = pv.at * bounds.width
                line.move(to: CGPoint(x: x, y: r.minY + 4)); line.line(to: CGPoint(x: x, y: r.maxY - 4))
            } else {
                let y = pv.at * bounds.height
                line.move(to: CGPoint(x: r.minX + 4, y: y)); line.line(to: CGPoint(x: r.maxX - 4, y: y))
            }
            accent.setStroke()
            line.lineWidth = 2
            line.setLineDash([6, 4], count: 2, phase: 0)
            line.stroke()
        }
        drawGuides()
    }

    /// Updates where a click would split, snapped to the fractions of the screen and to the other borders.
    private func updatePreview() {
        guard let p = hover, !draggingDivider, divider == nil, !selecting, mergeButton == nil, let i = zoneIndex(at: p) else {
            preview = nil
            if !draggingDivider { guides = [] }
            return
        }
        let vertical = splitVertically
        let raw = vertical ? p.x / bounds.width : p.y / bounds.height
        let s = snapUnit(raw, vertical: vertical, extra: borders(vertical: vertical))
        preview = (i, s.value, vertical)
        guides = s.label.map { [(vertical, s.value, $0)] } ?? []
    }

    /// The zones' inner borders along one axis (x for vertical lines), except those in `skip`.
    private func borders(vertical: Bool, skip: Set<Int> = []) -> [CGFloat] {
        zones.indices.filter { !skip.contains($0) }.flatMap { i -> [CGFloat] in
            let z = zones[i]
            return vertical ? [z.minX, z.maxX] : [z.minY, z.maxY]
        }.filter { $0 > eps && $0 < 1 - eps }
    }

    private func dragDivider(to p: CGPoint) {
        guard var d = divider else { return }
        let raw = d.vertical ? p.x / bounds.width : p.y / bounds.height
        let s = snapUnit(raw, vertical: d.vertical, extra: borders(vertical: d.vertical, skip: Set(d.before + d.after)))
        move(&d, to: s.value)
        divider = d
        guides = s.label != nil && abs(d.coord - s.value) < 0.0001 ? [(d.vertical, d.coord, s.label!)] : []
    }

    // MARK: Mouse

    override func mouseMoved(with event: NSEvent) {
        hover = point(event)
        if !draggingDivider { divider = dividerAt(hover!) }
        updatePreview()
        updateCursor()
        needsDisplay = true
    }
    override func mouseExited(with event: NSEvent) {
        hover = nil
        if !draggingDivider { divider = nil }
        updatePreview()
        needsDisplay = true
    }
    override func flagsChanged(with event: NSEvent) { updatePreview(); needsDisplay = true }

    override func mouseDown(with event: NSEvent) {
        let p = point(event)
        removeMergeButton()
        downPoint = p
        selecting = false
        if let d = dividerAt(p) {
            divider = d
            draggingDivider = true
            preview = nil
            return
        }
        selection = []
        anchor = zoneIndex(at: p)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let p = point(event)
        hover = p
        if draggingDivider {
            dragDivider(to: p)
        } else if let anchor, hypot(p.x - downPoint.x, p.y - downPoint.y) > 6 {
            selecting = true
            preview = nil
            guides = []
            let here = zoneIndex(at: p) ?? anchor
            selection = ZoneDrag.span([anchor, here], in: zones.map(toView))
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let p = point(event)
        defer { anchor = nil; needsDisplay = true }
        if draggingDivider {
            dragDivider(to: p)
            draggingDivider = false
            guides = []
            divider = dividerAt(p)
            return
        }
        if selecting {
            selecting = false
            if selection.count > 1 { showMergeButton(at: p) } else { selection = [] }
            return
        }
        if let i = anchor, i == zoneIndex(at: p) {
            updatePreview()
            if let pv = preview, pv.zone == i { split(i, at: pv.at, vertically: pv.vertical) }
            preview = nil
            updatePreview()
        }
    }

    private func updateCursor() {
        if let d = divider { (d.vertical ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).set() }
        else { NSCursor.arrow.set() }
    }

    // MARK: Editing

    private func zoneIndex(at p: CGPoint) -> Int? { zones.indices.first { toView(zones[$0]).contains(p) } }

    /// Splits zone `i` with a line at `c` (0…1: x if vertical, y otherwise).
    private func split(_ i: Int, at c: CGFloat, vertically: Bool) {
        let z = zones[i]
        if vertically {
            guard (c - z.minX) * bounds.width >= minSide, (z.maxX - c) * bounds.width >= minSide else { NSSound.beep(); return }
            zones[i] = CGRect(x: z.minX, y: z.minY, width: c - z.minX, height: z.height)
            zones.insert(CGRect(x: c, y: z.minY, width: z.maxX - c, height: z.height), at: i + 1)
        } else {
            guard (c - z.minY) * bounds.height >= minSide, (z.maxY - c) * bounds.height >= minSide else { NSSound.beep(); return }
            zones[i] = CGRect(x: z.minX, y: z.minY, width: z.width, height: c - z.minY)
            zones.insert(CGRect(x: z.minX, y: c, width: z.width, height: z.maxY - c), at: i + 1)
        }
    }

    /// The border near `p` (within a few points) and every zone along it, as long as they touch each other.
    private func dividerAt(_ p: CGPoint) -> Divider? {
        let tol: CGFloat = 6
        let u = toUnit(p)
        for vertical in [true, false] {
            let size = vertical ? bounds.width : bounds.height
            let pos = vertical ? u.x : u.y, across = vertical ? u.y : u.x
            func lo(_ r: CGRect) -> CGFloat { vertical ? r.minX : r.minY }
            func hi(_ r: CGRect) -> CGFloat { vertical ? r.maxX : r.maxY }
            func aLo(_ r: CGRect) -> CGFloat { vertical ? r.minY : r.minX }
            func aHi(_ r: CGRect) -> CGFloat { vertical ? r.maxY : r.maxX }
            var lines: [CGFloat] = []
            for z in zones {
                for v in [lo(z), hi(z)] where v > eps && v < 1 - eps { lines.append(v) }
            }
            guard let c = lines.min(by: { abs($0 - pos) < abs($1 - pos) }), abs(c - pos) * size <= tol else { continue }
            let onLine = zones.indices.filter { abs(lo(zones[$0]) - c) < 0.001 || abs(hi(zones[$0]) - c) < 0.001 }
            // the stretch of line under the pointer, extended through every zone that touches it
            var members = onLine.filter { aLo(zones[$0]) - eps <= across && across <= aHi(zones[$0]) + eps }
            guard !members.isEmpty else { continue }
            var changed = true
            while changed {
                let a = members.map { aLo(zones[$0]) }.min()!, b = members.map { aHi(zones[$0]) }.max()!
                let more = onLine.filter { !members.contains($0) && aLo(zones[$0]) <= b + 0.001 && aHi(zones[$0]) >= a - 0.001 }
                changed = !more.isEmpty
                members += more
            }
            let before = members.filter { abs(hi(zones[$0]) - c) < 0.001 }, after = members.filter { abs(lo(zones[$0]) - c) < 0.001 }
            guard !before.isEmpty, !after.isEmpty else { continue }
            return Divider(vertical: vertical, coord: c, before: before, after: after)
        }
        return nil
    }

    private func move(_ d: inout Divider, to c: CGFloat) {
        let size = d.vertical ? bounds.width : bounds.height
        let m = minSide / max(1, size)
        var lo: CGFloat = 0, hi: CGFloat = 1
        for i in d.before { lo = max(lo, (d.vertical ? zones[i].minX : zones[i].minY) + m) }
        for i in d.after { hi = min(hi, (d.vertical ? zones[i].maxX : zones[i].maxY) - m) }
        guard lo <= hi else { return }
        let v = min(max(c, lo), hi)
        for i in d.before {
            var z = zones[i]
            if d.vertical { z.size.width = v - z.minX } else { z.size.height = v - z.minY }
            zones[i] = z
        }
        for i in d.after {
            var z = zones[i]
            if d.vertical { z = CGRect(x: v, y: z.minY, width: z.maxX - v, height: z.height) }
            else { z = CGRect(x: z.minX, y: v, width: z.width, height: z.maxY - v) }
            zones[i] = z
        }
        d.coord = v
    }

    /// A clearly visible button in the middle of the selected zones.
    private func showMergeButton(at p: CGPoint) {
        let b = NSButton(title: "", target: self, action: #selector(merge))
        b.isBordered = false
        b.wantsLayer = true
        b.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        b.layer?.cornerRadius = 10
        b.layer?.shadowColor = NSColor.black.cgColor
        b.layer?.shadowOpacity = 0.35
        b.layer?.shadowRadius = 8
        b.layer?.shadowOffset = CGSize(width: 0, height: -2)
        b.attributedTitle = NSAttributedString(string: String(localized: "Merge"), attributes: [
            .font: NSFont.systemFont(ofSize: 16, weight: .semibold), .foregroundColor: NSColor.white,
        ])
        b.image = NSImage(systemSymbolName: "rectangle.compress.vertical", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 15, weight: .semibold).applying(.init(paletteColors: [.white])))
        b.imagePosition = .imageLeading
        b.imageHugsTitle = true
        let text = b.attributedTitle.size()
        b.frame.size = CGSize(width: text.width + 58, height: 40)
        let box = selection.map { toView(zones[$0]) }.reduce(CGRect.null) { $0.union($1) }
        let c = box.isNull ? p : CGPoint(x: box.midX, y: box.midY)
        b.frame.origin = CGPoint(x: min(max(8, c.x - b.frame.width / 2), bounds.width - b.frame.width - 8),
                                 y: min(max(8, c.y - b.frame.height / 2), bounds.height - b.frame.height - 8))
        addSubview(b)
        mergeButton = b
    }

    private func removeMergeButton() {
        mergeButton?.removeFromSuperview()
        mergeButton = nil
    }

    @objc private func merge() {
        let ids = selection.sorted()
        guard ids.count > 1 else { return }
        let box = ids.map { zones[$0] }.reduce(CGRect.null) { $0.union($1) }
        let first = ids[0]
        zones[first] = box
        for i in ids.dropFirst().reversed() { zones.remove(at: i) }
        selection = []
        removeMergeButton()
        needsDisplay = true
    }
}
