import Cocoa

/// Shows a monitor's zones on screen: while dragging a window (the zone under the pointer lights up)
/// and briefly when the layout changes. One panel per monitor, freed as soon as they disappear.
final class ZoneOverlay {
    static let shared = ZoneOverlay()
    private var panels: [String: (panel: NSPanel, view: ZonesView)] = [:]
    private var fadeGeneration = 0

    /// `zones`: for each monitor, the zone frames (CoreGraphics coordinates) and the lit ones.
    func show(_ zones: [(screen: NSScreen, frames: [CGRect], lit: Set<Int>)], below window: CGWindowID?) {
        fadeGeneration += 1
        let keys = Set(zones.map { ZoneStore.key(for: $0.screen) })
        for (key, p) in panels where !keys.contains(key) { p.panel.orderOut(nil); panels[key] = nil }
        for z in zones {
            let key = ZoneStore.key(for: z.screen)
            let area = ScreenGeo.area(z.screen)
            let entry = panels[key] ?? make()
            panels[key] = entry
            let (p, v) = entry
            if ScreenGeo.cg(p.frame) != area { p.setFrame(ScreenGeo.ns(area), display: false) }
            v.update(frames: z.frames.map { $0.offsetBy(dx: -area.minX, dy: -area.minY) }, lit: z.lit)
            if !p.isVisible || p.alphaValue < 1 {
                p.alphaValue = p.isVisible ? p.alphaValue : 0
                if let window { p.order(.below, relativeTo: Int(window)) } else { p.orderFrontRegardless() }
                NSAnimationContext.runAnimationGroup { $0.duration = 0.12; p.animator().alphaValue = 1 }
            }
        }
    }

    func hide() {
        fadeGeneration += 1
        let generation = fadeGeneration
        let all = panels.values.map(\.panel)
        guard !all.isEmpty else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.16
            all.forEach { $0.animator().alphaValue = 0 }
        }, completionHandler: { [weak self] in
            guard let self, self.fadeGeneration == generation else { return } // shown again meanwhile
            self.panels.values.forEach { $0.panel.orderOut(nil) }
            self.panels = [:]
        })
    }

    /// Shows a monitor's zones for a moment (after changing layout).
    func flash(_ screen: NSScreen) {
        guard ZoneSettings.flash else { return }
        let layout = ZoneStore.shared.layout(for: screen)
        guard !layout.zones.isEmpty else { return }
        show([(screen, layout.frames(in: ScreenGeo.area(screen)), [])], below: nil)
        let generation = fadeGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            if self?.fadeGeneration == generation { self?.hide() }
        }
    }

    private func make() -> (NSPanel, ZonesView) {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.level = .normal
        p.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        let v = ZonesView()
        p.contentView = v
        return (p, v)
    }
}

/// Draws zones as rounded rectangles with their number, like FancyZones.
final class ZonesView: NSView {
    private var frames: [CGRect] = []
    private var lit: Set<Int> = []
    override var isFlipped: Bool { true }

    func update(frames: [CGRect], lit: Set<Int>) {
        guard frames != self.frames || lit != self.lit else { return }
        self.frames = frames
        self.lit = lit
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let color = ZoneSettings.highlightColor
        let opacity = CGFloat(ZoneSettings.opacity)
        let numbers = ZoneSettings.showNumbers
        for (i, f) in frames.enumerated() {
            let on = lit.contains(i)
            let path = NSBezierPath(roundedRect: f.insetBy(dx: 1, dy: 1), xRadius: 10, yRadius: 10)
            (on ? color.withAlphaComponent(opacity) : NSColor.windowBackgroundColor.withAlphaComponent(opacity * 0.9)).setFill()
            path.fill()
            (on ? color : color.withAlphaComponent(0.7)).setStroke()
            path.lineWidth = on ? 3 : 2
            path.stroke()
            guard numbers else { continue }
            let size = min(72, max(18, min(f.width, f.height) * 0.22))
            let text = NSAttributedString(string: "\(i + 1)", attributes: [
                .font: NSFont.systemFont(ofSize: size, weight: .semibold),
                .foregroundColor: on ? NSColor.white : NSColor.labelColor.withAlphaComponent(0.75),
            ])
            let s = text.size()
            text.draw(at: CGPoint(x: f.midX - s.width / 2, y: f.midY - s.height / 2))
        }
    }
}
