import Cocoa

/// Zones while dragging a window (called by WindowSnap on every step of a move).
/// Hold ⇧ (or the opposite, depending on the setting) to see them; the zone under the pointer lights up,
/// and near the border between two zones both do. Hold ⌃ as well to span several zones.
final class ZoneDrag {
    static let shared = ZoneDrag()

    struct Target {
        let frame: CGRect, unit: CGRect, area: CGRect
        let zones: [CGRect]   // all the zones of the monitor
        let lit: Set<Int>     // the ones the window takes
    }

    private var current: (screen: NSScreen, frames: [CGRect], lit: Set<Int>)?
    private var anchor: (screen: String, zones: Set<Int>)? // where spanning (⌃) started
    /// Smart layouts: chosen once per monitor when the zones appear, so they don't change mid-drag.
    private var layouts: [String: ZoneLayout] = [:]

    private func layout(_ screen: NSScreen, _ window: CGWindowID) -> ZoneLayout {
        let key = ZoneStore.key(for: screen)
        if let l = layouts[key] { return l }
        let l = SmartZones.layout(for: screen, window: window)
        layouts[key] = l
        return l
    }

    /// True if zones are showing: edge snapping stands aside meanwhile.
    func update(pid: pid_t, window: CGWindowID) -> Bool {
        let flags = CGEventSource.flagsState(.combinedSessionState)
        let shift = flags.contains(.maskShift)
        guard ZoneSettings.enabled, ZoneSettings.holdShift ? shift : !shift,
              !ZoneSettings.isExcluded(pid: pid) else { stop(); return false }
        let m = ScreenGeo.mouse
        guard let screen = ScreenGeo.screen(at: m) else { stop(); return false }
        let layout = layout(screen, window)
        let frames = layout.frames(in: ScreenGeo.area(screen))
        guard !frames.isEmpty else { stop(); return false } // "No layout": normal snapping
        var lit = Self.zones(at: m, in: frames, sensitivity: CGFloat(layout.sensitivity))
        let key = ZoneStore.key(for: screen)
        if flags.contains(.maskControl), !lit.isEmpty {
            if anchor?.screen != key { anchor = (key, lit) }
            lit = Self.span(lit.union(anchor?.zones ?? []), in: frames)
        } else {
            anchor = nil
        }
        current = (screen, frames, lit)
        var shown = [(screen: screen, frames: frames, lit: lit)]
        if ZoneSettings.allMonitors {
            for s in NSScreen.screens where s != screen {
                let f = self.layout(s, window).frames(in: ScreenGeo.area(s))
                if !f.isEmpty { shown.append((s, f, [])) }
            }
        }
        ZoneOverlay.shared.show(shown, below: window)
        return true
    }

    /// Where the window goes if dropped now.
    var target: Target? {
        guard let c = current, !c.lit.isEmpty else { return nil }
        let frame = c.lit.map { c.frames[$0] }.reduce(CGRect.null) { $0.union($1) }
        let area = ScreenGeo.area(c.screen)
        let unit = CGRect(x: (frame.minX - area.minX) / area.width, y: (frame.minY - area.minY) / area.height,
                          width: frame.width / area.width, height: frame.height / area.height)
        return Target(frame: frame, unit: unit, area: area, zones: c.frames, lit: c.lit)
    }

    var isShowing: Bool { current != nil }

    /// The drag is over: the next one counts the windows again.
    func finish() {
        layouts = [:]
        stop()
    }

    func stop() {
        guard current != nil else { return }
        current = nil
        anchor = nil
        ZoneOverlay.shared.hide()
    }

    // MARK: Geometry

    /// The zones the pointer activates: the one it is in (the smallest, if they overlap), plus the
    /// neighbors whose border is within `sensitivity` points; in the gap between zones, those around it.
    static func zones(at p: CGPoint, in frames: [CGRect], sensitivity: CGFloat) -> Set<Int> {
        let inside = frames.indices.filter { frames[$0].contains(p) }
        if inside.count > 1, let smallest = inside.min(by: { frames[$0].area < frames[$1].area }) { return [smallest] }
        let near = frames.indices.filter { frames[$0].insetBy(dx: -sensitivity, dy: -sensitivity).contains(p) }
        if let one = inside.first {
            // neighbors only if they don't overlap the zone we're in (canvas layouts)
            return Set([one] + near.filter { $0 != one && frames[$0].intersection(frames[one]).area < 1 })
        }
        return Set(near) // in the gap between zones: those around it; outside every zone: none
    }

    /// All the zones within the rectangle containing `zones`, growing it until it contains whole zones.
    static func span(_ zones: Set<Int>, in frames: [CGRect]) -> Set<Int> {
        var set = zones
        while true {
            let box = set.map { frames[$0] }.reduce(CGRect.null) { $0.union($1) }.insetBy(dx: 2, dy: 2)
            let grown = Set(frames.indices.filter { frames[$0].intersects(box) })
            if grown == set { return set }
            set = grown
        }
    }
}
