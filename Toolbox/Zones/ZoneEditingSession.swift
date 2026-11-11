import Cocoa

/// Drawing a custom layout directly on the monitor: a panel covering the usable area, with the grid or
/// canvas editor and a small toolbar. Save applies the layout to that monitor; Esc or Cancel discards.
final class ZoneEditingSession: NSObject {
    private static var current: ZoneEditingSession?

    private let panel: KeyPanel
    private var layout: ZoneLayout
    private let screen: NSScreen
    private let editor: ZoneEditingView

    static func start(_ layout: ZoneLayout, on screen: NSScreen) {
        current?.finish(save: false)
        current = ZoneEditingSession(layout, screen: screen)
    }

    private init(_ layout: ZoneLayout, screen: NSScreen) {
        self.layout = layout
        self.screen = screen
        let area = ScreenGeo.ns(ScreenGeo.area(screen))
        panel = KeyPanel(contentRect: area, styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = NSColor.black.withAlphaComponent(0.25)
        panel.level = .floating
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        editor = layout.kind == .canvas ? CanvasEditorView(zones: layout.customZones) : GridEditorView(zones: layout.customZones)
        super.init()

        let root = NSView(frame: NSRect(origin: .zero, size: area.size))
        editor.frame = root.bounds
        editor.autoresizingMask = [.width, .height]
        root.addSubview(editor)
        let bar = toolbar()
        root.addSubview(bar)
        bar.frame.origin = NSPoint(x: (root.bounds.width - bar.frame.width) / 2, y: root.bounds.height - bar.frame.height - 16)
        bar.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin]
        panel.contentView = root
        editor.onSave = { [weak self] in self?.finish(save: true) }
        editor.onCancel = { [weak self] in self?.finish(save: false) }

        ZoneEditor.shared.stepAside()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(editor)
        NSApp.activate()
    }

    /// Name, the commands for this kind of layout and the buttons. It can be dragged out of the way.
    private func toolbar() -> NSView {
        let commands: [(String, String)] = layout.kind == .canvas ? [
            (String(localized: "Add zone"), String(localized: "a new zone")),
            (String(localized: "Drag a zone"), String(localized: "move it")),
            (String(localized: "Drag its borders or corners"), String(localized: "resize it")),
            (String(localized: "× or ⌫"), String(localized: "remove the selected zone")),
        ] : [
            (String(localized: "Click"), String(localized: "split the zone into top and bottom")),
            (String(localized: "⇧ + click"), String(localized: "split the zone into left and right")),
            (String(localized: "Drag a border"), String(localized: "resize the zones along it")),
            (String(localized: "Drag across zones → Merge"), String(localized: "join them (this is how you remove a zone)")),
        ]
        let title = NSTextField(labelWithString: layout.name)
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        let grid = NSGridView(views: commands.map { key, what in
            let k = NSTextField(labelWithString: key)
            k.font = .systemFont(ofSize: 12, weight: .semibold)
            let w = NSTextField(labelWithString: what)
            w.font = .systemFont(ofSize: 12)
            w.textColor = .secondaryLabelColor
            return [k, w]
        })
        grid.rowSpacing = 4
        grid.columnSpacing = 12
        let note = NSTextField(labelWithString: String(localized: "Borders snap to 1/4, 1/3, 1/2, 2/3 and 3/4 of the screen. Return saves, Esc cancels."))
        note.font = .systemFont(ofSize: 11)
        note.textColor = .tertiaryLabelColor

        var buttons: [NSView] = []
        if layout.kind == .canvas {
            buttons.append(NSButton(title: String(localized: "Add zone"), target: self, action: #selector(addZone)))
        }
        let cancel = NSButton(title: String(localized: "Cancel"), target: self, action: #selector(cancel))
        let save = NSButton(title: String(localized: "Save and apply"), target: self, action: #selector(save))
        save.keyEquivalent = "\r"
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let top = NSStackView(views: [title, spacer] + buttons + [cancel, save])
        top.spacing = 8
        let stack = NSStackView(views: [top, grid, note])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 16, bottom: 12, right: 14)
        top.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -30).isActive = true

        let box = DraggableBox()
        box.material = .popover
        box.state = .active
        box.wantsLayer = true
        box.layer?.cornerRadius = 12
        box.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: box.leadingAnchor), stack.trailingAnchor.constraint(equalTo: box.trailingAnchor),
            stack.topAnchor.constraint(equalTo: box.topAnchor), stack.bottomAnchor.constraint(equalTo: box.bottomAnchor),
        ])
        box.frame.size = stack.fittingSize
        box.toolTip = String(localized: "Drag to move")
        return box
    }

    @objc private func addZone() { (editor as? CanvasEditorView)?.addZone() }
    @objc private func cancel() { finish(save: false) }
    @objc private func save() { finish(save: true) }

    private func finish(save: Bool) {
        if save {
            layout.customZones = editor.zones
            ZoneStore.shared.put(layout)
            ZoneStore.shared.apply(layout.id, to: screen)
        }
        panel.orderOut(nil)
        panel.contentView = nil
        Self.current = nil
        ZoneEditor.shared.comeBack()
        if save { ZoneOverlay.shared.flash(screen) }
    }
}

/// The toolbar: drag it anywhere on its background.
final class DraggableBox: NSVisualEffectView {
    private var grab: CGPoint?
    override func mouseDown(with event: NSEvent) { grab = convert(event.locationInWindow, from: nil) }
    override func mouseDragged(with event: NSEvent) {
        guard let grab, let parent = superview else { return }
        let p = parent.convert(event.locationInWindow, from: nil)
        var o = CGPoint(x: p.x - grab.x, y: p.y - grab.y)
        o.x = min(max(0, o.x), parent.bounds.width - frame.width)
        o.y = min(max(0, o.y), parent.bounds.height - frame.height)
        setFrameOrigin(o)
    }
    override func mouseUp(with event: NSEvent) { grab = nil }
}

/// A borderless panel that can take the keyboard (Esc, Return, Delete, ⇧).
final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// What the two editors have in common.
class ZoneEditingView: NSView {
    var zones: [CGRect] = []   // 0…1
    var onSave: (() -> Void)?
    var onCancel: (() -> Void)?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func toView(_ u: CGRect) -> CGRect {
        CGRect(x: u.minX * bounds.width, y: u.minY * bounds.height, width: u.width * bounds.width, height: u.height * bounds.height)
    }
    func toUnit(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x / max(1, bounds.width), y: p.y / max(1, bounds.height)) }
    func point(_ e: NSEvent) -> CGPoint { convert(e.locationInWindow, from: nil) }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: onCancel?()
        case 36, 76: onSave?()
        default: super.keyDown(with: event)
        }
    }

    // MARK: Snapping to fractions of the screen

    /// Where borders snap: quarters, thirds and the middle of the screen.
    static let fractions: [(value: CGFloat, label: String)] = [
        (0.25, "1/4"), (1.0 / 3, "1/3"), (0.5, "1/2"), (2.0 / 3, "2/3"), (0.75, "3/4"),
    ]
    let snapDistance: CGFloat = 14 // points

    typealias Guide = (vertical: Bool, at: CGFloat, label: String)
    /// The snap lines being used right now (shown as guides with their fraction): at most one per direction.
    var guides: [Guide] = [] { didSet { needsDisplay = true } }

    /// Snaps `v` (a 0…1 coordinate: along x for a vertical line) to the fractions of the screen or to
    /// `extra` lines (the other zones' borders), whichever is closest within a few points.
    func snapUnit(_ v: CGFloat, vertical: Bool, extra: [CGFloat] = []) -> (value: CGFloat, label: String?) {
        let size = max(1, vertical ? bounds.width : bounds.height)
        let candidates = Self.fractions.map { ($0.value, Optional($0.label)) } + extra.map { ($0, String?.none) }
        guard let best = candidates.min(by: { abs($0.0 - v) < abs($1.0 - v) }), abs(best.0 - v) * size <= snapDistance else {
            return (v, nil)
        }
        return best
    }

    /// Small marks at the fractions along the bottom and left edges, and the active guide.
    func drawGuides() {
        let marks = NSColor.white.withAlphaComponent(0.55)
        let font = NSFont.systemFont(ofSize: 10, weight: .medium)
        for f in Self.fractions {
            let x = f.value * bounds.width, y = f.value * bounds.height
            let tick = NSBezierPath()
            tick.move(to: CGPoint(x: x, y: bounds.maxY)); tick.line(to: CGPoint(x: x, y: bounds.maxY - 8))
            tick.move(to: CGPoint(x: 0, y: y)); tick.line(to: CGPoint(x: 8, y: y))
            marks.setStroke(); tick.lineWidth = 1.5; tick.stroke()
            let label = NSAttributedString(string: f.label, attributes: [.font: font, .foregroundColor: marks])
            label.draw(at: CGPoint(x: x - label.size().width / 2, y: bounds.maxY - 22))
            label.draw(at: CGPoint(x: 11, y: y - label.size().height / 2))
        }
        for g in guides { drawGuide(g) }
    }

    private func drawGuide(_ g: Guide) {
        let accent = NSColor.controlAccentColor
        let line = NSBezierPath()
        let pos = g.at * (g.vertical ? bounds.width : bounds.height)
        if g.vertical { line.move(to: CGPoint(x: pos, y: 0)); line.line(to: CGPoint(x: pos, y: bounds.maxY)) }
        else { line.move(to: CGPoint(x: 0, y: pos)); line.line(to: CGPoint(x: bounds.maxX, y: pos)) }
        accent.withAlphaComponent(0.8).setStroke()
        line.lineWidth = 1
        line.setLineDash([4, 4], count: 2, phase: 0)
        line.stroke()
        // the fraction, in a small pill next to the pointer
        let text = NSAttributedString(string: g.label, attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                                                                     .foregroundColor: NSColor.white])
        let mouse = window.map { convert($0.mouseLocationOutsideOfEventStream, from: nil) } ?? .zero
        let size = text.size()
        let origin = g.vertical ? CGPoint(x: pos + 8, y: mouse.y + 14) : CGPoint(x: mouse.x + 14, y: pos + 6)
        let pill = CGRect(x: origin.x, y: origin.y, width: size.width + 12, height: size.height + 4)
        accent.setFill()
        NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2).fill()
        text.draw(at: CGPoint(x: pill.minX + 6, y: pill.minY + 2))
    }

    func drawZone(_ r: CGRect, number: Int, selected: Bool) {
        let accent = NSColor.controlAccentColor
        let path = NSBezierPath(roundedRect: r.insetBy(dx: 3, dy: 3), xRadius: 8, yRadius: 8)
        (selected ? accent.withAlphaComponent(0.45) : NSColor.windowBackgroundColor.withAlphaComponent(0.75)).setFill()
        path.fill()
        accent.withAlphaComponent(0.9).setStroke()
        path.lineWidth = selected ? 3 : 1.5
        path.stroke()
        let size = min(64, max(16, min(r.width, r.height) * 0.2))
        let text = NSAttributedString(string: "\(number)", attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: .semibold), .foregroundColor: NSColor.labelColor.withAlphaComponent(0.8),
        ])
        let s = text.size()
        text.draw(at: CGPoint(x: r.midX - s.width / 2, y: r.midY - s.height / 2))
        let dims = NSAttributedString(string: "\(Int(r.width)) × \(Int(r.height))", attributes: [
            .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor,
        ])
        if r.height > 90 { dims.draw(at: CGPoint(x: r.midX - dims.size().width / 2, y: r.midY + s.height / 2 + 2)) }
    }
}
