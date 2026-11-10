import Cocoa

/// Draws the layouts as thumbnails. Used as the bar that drops down at the top of the screen while dragging
/// (WindowSnap tracks the pointer over it) and as the clickable ⌥Z menu.
final class LayoutPicker {
    enum Style { case bar, flyout }

    let style: Style
    private(set) var layouts: [SnapLayout] = []
    private var panel: NSPanel?
    private var view: LayoutPickerView?
    var onChoose: ((Int, Int) -> Void)?

    var highlight: (Int, Int)? {
        get { view?.highlight }
        set { if view?.highlight.map({ [$0.0, $0.1] }) != newValue.map({ [$0.0, $0.1] }) { view?.highlight = newValue } }
    }
    var isVisible: Bool { panel?.isVisible == true }

    init(style: Style) { self.style = style }

    func show(layouts: [SnapLayout], area: CGRect, topCenter: CGPoint) {
        show(layouts: layouts, area: area) { size in CGPoint(x: topCenter.x - size.width / 2, y: topCenter.y) }
    }

    func show(layouts: [SnapLayout], area: CGRect, origin: (CGSize) -> CGPoint) {
        let p = panel ?? make()
        panel = p
        let same = layouts.count == self.layouts.count && p.isVisible
        self.layouts = layouts
        guard !same else { return }
        let columns = style == .bar ? layouts.count : min(3, layouts.count)
        view?.configure(layouts: layouts, aspect: area.width / max(1, area.height), columns: columns)
        let size = view?.fittingSize ?? .zero
        let o = origin(size)
        p.setFrame(ScreenGeo.ns(CGRect(origin: o, size: size)), display: true)
        p.alphaValue = 0
        p.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.15; p.animator().alphaValue = 1 }
    }

    func hide() {
        guard panel?.isVisible == true else { return }
        panel?.orderOut(nil)
        view?.highlight = nil
    }

    func contains(_ p: CGPoint) -> Bool {
        guard let panel, panel.isVisible else { return false }
        return ScreenGeo.cg(panel.frame).contains(p)
    }

    /// Layout zone under the point (screen coordinates).
    func hit(_ p: CGPoint) -> (Int, Int)? {
        guard let panel, panel.isVisible, let view else { return nil }
        let f = ScreenGeo.cg(panel.frame)
        return view.zone(at: CGPoint(x: p.x - f.minX, y: p.y - f.minY))
    }

    var frame: CGRect? { panel.map { ScreenGeo.cg($0.frame) } }

    private func make() -> NSPanel {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .popUpMenu
        p.ignoresMouseEvents = style == .bar // while dragging, the mouse is "busy" with the window
        p.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        p.hidesOnDeactivate = false
        let blur = NSVisualEffectView()
        blur.material = .popover
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 12
        blur.layer?.masksToBounds = true
        let v = LayoutPickerView()
        v.onClick = { [weak self] l, z in self?.onChoose?(l, z) }
        v.autoresizingMask = [.width, .height]
        blur.addSubview(v)
        p.contentView = blur
        view = v
        return p
    }
}

final class LayoutPickerView: NSView {
    private var layouts: [SnapLayout] = []
    private var aspect: CGFloat = 16.0 / 9
    private var columns = 3
    private let pad: CGFloat = 12, gap: CGFloat = 12, boxW: CGFloat = 92
    var highlight: (Int, Int)? { didSet { needsDisplay = true } }
    var onClick: ((Int, Int) -> Void)?

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var boxH: CGFloat { (boxW / aspect).rounded() }

    func configure(layouts: [SnapLayout], aspect: CGFloat, columns: Int) {
        self.layouts = layouts
        self.aspect = min(max(aspect, 0.5), 2.6)
        self.columns = max(1, columns)
        let rows = (layouts.count + self.columns - 1) / self.columns
        let size = NSSize(width: pad * 2 + CGFloat(self.columns) * boxW + CGFloat(self.columns - 1) * gap,
                          height: pad * 2 + CGFloat(rows) * boxH + CGFloat(rows - 1) * gap)
        setFrameSize(size)
        superview?.setFrameSize(size)
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
        needsDisplay = true
    }

    override var fittingSize: NSSize { frame.size }

    private func box(_ i: Int) -> CGRect {
        let c = i % columns, r = i / columns
        return CGRect(x: pad + CGFloat(c) * (boxW + gap), y: pad + CGFloat(r) * (boxH + gap), width: boxW, height: boxH)
    }

    private func zoneRect(_ l: Int, _ z: Int) -> CGRect {
        let b = box(l).insetBy(dx: 2, dy: 2)
        let u = layouts[l].zones[z].unit
        return CGRect(x: b.minX + u.minX * b.width, y: b.minY + u.minY * b.height,
                      width: u.width * b.width, height: u.height * b.height).insetBy(dx: 2, dy: 2)
    }

    func zone(at p: CGPoint) -> (Int, Int)? {
        for l in layouts.indices { for z in layouts[l].zones.indices where zoneRect(l, z).insetBy(dx: -2, dy: -2).contains(p) { return (l, z) } }
        return nil
    }

    override func draw(_ dirtyRect: NSRect) {
        for l in layouts.indices {
            let outer = NSBezierPath(roundedRect: box(l), xRadius: 7, yRadius: 7)
            NSColor.labelColor.withAlphaComponent(0.06).setFill()
            outer.fill()
            for z in layouts[l].zones.indices {
                let on = highlight.map { $0.0 == l && $0.1 == z } ?? false
                let path = NSBezierPath(roundedRect: zoneRect(l, z), xRadius: 4, yRadius: 4)
                (on ? NSColor.controlAccentColor : NSColor.labelColor.withAlphaComponent(0.18)).setFill()
                path.fill()
                if on {
                    NSColor.controlAccentColor.withAlphaComponent(0.9).setStroke()
                    path.lineWidth = 1.5
                    path.stroke()
                }
            }
        }
    }

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let h = zone(at: p)
        if h.map({ [$0.0, $0.1] }) != highlight.map({ [$0.0, $0.1] }) { highlight = h }
    }
    override func mouseExited(with event: NSEvent) { highlight = nil }
    override func mouseDown(with event: NSEvent) {
        if let h = zone(at: convert(event.locationInWindow, from: nil)) { onClick?(h.0, h.1) }
    }

    /// Keyboard navigation: all zones in a row.
    func step(_ delta: Int) {
        let flat = layouts.indices.flatMap { l in layouts[l].zones.indices.map { (l, $0) } }
        guard !flat.isEmpty else { return }
        let cur = highlight.flatMap { h in flat.firstIndex { $0 == h } } ?? (delta > 0 ? -1 : 0)
        highlight = flat[(cur + delta + flat.count) % flat.count]
    }
}
