import Cocoa

// Snap windows like Windows 11 (Settings → System → Multitasking → Snap windows).
//
// Dragging
// - left/right edge → half; corners → quarter; top edge → full screen (on the same desktop);
// - moving toward the top center drops down the layout bar (halves, thirds, quarters…): drop the window on a zone;
// - dragging the top or bottom border to the screen edge stretches the window vertically;
// - a snapped window dragged away gets its previous size back;
// - "snap without dragging all the way to the edge": getting close is enough.
// Keyboard (left ⌥ = Windows key, like ⌥⇧S for screenshots)
// - ⌥← / ⌥→ / ⌥↑ / ⌥↓ like Win + arrows (halves, quarters, maximize, restore, minimize);
// - ⌥⇧← / ⌥⇧→ move to another monitor; ⌥⇧↑ stretches vertically, ⌥⇧↓ restores;
// - ⌥Z opens the layouts next to the window (then numbers, arrows, Return).
// Snap Assist: after snapping, offers the other windows for the remaining free space.
// Resize together: moving the shared border between snapped windows adjusts the adjacent ones.
//
// Coordinates: Accessibility/CoreGraphics ones, origin at the top left of the main screen.

final class WindowSnap {
    static let shared = WindowSnap()

    struct Snapped {
        let el: WindowRef
        var frame: CGRect      // where it is now (changes with linked resizing)
        var zone: SnapZone     // logical zone (for the arrow keys)
        var area: CGRect       // usable screen area
        let restore: CGRect    // position and size before being snapped
        var vertical = false   // stretched vertically only
    }

    private enum Mode { case undecided, moving, resizing }

    private(set) var snapped: [CGWindowID: Snapped] = [:]
    private var timer: Timer?
    private var win: WindowRef?
    private var winID: CGWindowID = 0
    private var startFrame: CGRect = .zero
    private var lastFrame: CGRect = .zero
    private var grabX: CGFloat = 0.5 // point grabbed in the title bar, as a fraction of the width
    private var onEdge = false        // grabbed by a border (resizing) rather than by the title bar
    private var mode: Mode = .undecided
    private var target: (zone: SnapZone, area: CGRect, layout: SnapLayout?, index: Int)?
    private var verticalTarget: CGRect?
    private let overlay = SnapOverlay()
    private let bar = LayoutPicker(style: .bar)

    // MARK: Events from the tap (no heavy work there: defer to the main run loop)

    func mouseDown(at p: CGPoint) {
        SnapAssist.shared.mouseDown(at: p)
        LayoutFlyout.shared.mouseDown(at: p)
        guard SnapSettings.enabled else { return }
        DispatchQueue.main.async { self.begin(at: p) }
    }

    func mouseUp() {
        DispatchQueue.main.async { self.end() }
    }

    private func begin(at p: CGPoint) {
        stopTimer()
        guard AXIsProcessTrusted(), let w = WindowRef.at(p),
              let id = w.id, let f = w.frame else { return }
        win = w; winID = id; startFrame = f; lastFrame = f
        grabX = f.width > 0 ? (p.x - f.minX) / f.width : 0.5
        // the resize borders are a thin strip around the window
        let edgeDistance = min(abs(p.x - f.minX), abs(f.maxX - p.x), abs(p.y - f.minY), abs(f.maxY - p.y))
        onEdge = edgeDistance <= 8
        mode = .undecided; target = nil; verticalTarget = nil
        let t = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        guard let win else { stopTimer(); return }
        if NSEvent.pressedMouseButtons & 1 == 0 { end(); return } // missed mouseUp
        guard let f = win.frame else { return }
        if mode == .undecided {
            // grabbed by the title bar it is always a move, even if the size changes meanwhile
            // (we put it back to its previous size, or macOS does with its own tiling)
            if onEdge, f.size != startFrame.size { mode = .resizing }
            else if abs(f.minX - startFrame.minX) > 2 || abs(f.minY - startFrame.minY) > 2 ||
                        (!onEdge && f.size != startFrame.size) { startMoving(f) }
        }
        switch mode {
        case .moving: updateTarget()
        case .resizing:
            if f != lastFrame { resized(winID, from: lastFrame, to: f) }
            updateVerticalTarget(f)
        case .undecided: break
        }
        lastFrame = f
    }

    private func startMoving(_ f: CGRect) {
        mode = .moving
        SnapAssist.shared.dismiss()
        LayoutFlyout.shared.dismiss()
        // a snapped window dragged away returns to its previous size
        guard let s = snapped.removeValue(forKey: winID), let win, s.restore.size != f.size else { return }
        let m = ScreenGeo.mouse
        win.setSize(s.restore.size)
        win.setPosition(CGPoint(x: m.x - grabX * s.restore.width, y: f.minY))
    }

    /// Where the window would go if dropped here: edges, corners, top edge or layout bar.
    private func updateTarget() {
        let m = ScreenGeo.mouse
        guard let screen = ScreenGeo.screen(at: m) else { setTarget(nil); bar.hide(); return }
        let full = ScreenGeo.cg(screen.frame)
        let area = ScreenGeo.area(screen)
        let edge: CGFloat = SnapSettings.nearEdge ? 18 : 3
        let corner = max(60, full.height * 0.12)

        // layout bar: when approaching the top center
        if SnapSettings.layoutBar, m.y < full.minY + max(110, full.height * 0.1),
           abs(m.x - full.midX) < full.width * 0.22 {
            bar.show(layouts: SnapLayout.all(for: area), area: area, topCenter: CGPoint(x: full.midX, y: full.minY + 6))
            if let h = bar.hit(m) {
                let (l, z) = h
                let layout = bar.layouts[l]
                bar.highlight = (l, z)
                setTarget((layout.zones[z], area, layout, z))
                return
            }
            bar.highlight = nil
            if !bar.contains(m) || m.y > full.minY + edge { setTarget(nil); return }
        } else {
            bar.hide()
        }

        let atLeft = m.x <= full.minX + edge && ScreenGeo.isOuterEdge(CGPoint(x: full.minX - 2, y: m.y))
        let atRight = m.x >= full.maxX - edge && ScreenGeo.isOuterEdge(CGPoint(x: full.maxX + 2, y: m.y))
        let atTop = m.y <= full.minY + edge && ScreenGeo.isOuterEdge(CGPoint(x: m.x, y: full.minY - 2))
        var z: SnapZone?
        if atLeft || atRight {
            if m.y < full.minY + corner { z = atLeft ? .topLeft : .topRight }
            else if m.y > full.maxY - corner { z = atLeft ? .bottomLeft : .bottomRight }
            else { z = atLeft ? .left : .right }
        } else if atTop {
            if m.x < full.minX + corner { z = .topLeft }
            else if m.x > full.maxX - corner { z = .topRight }
            else { z = .maximize }
        }
        guard let z else { setTarget(nil); return }
        let layout: SnapLayout? = z == .maximize ? nil : (z == .left || z == .right ? .halves : .quarters)
        setTarget((z, area, layout, layout?.zones.firstIndex(of: z) ?? 0))
    }

    private func setTarget(_ t: (zone: SnapZone, area: CGRect, layout: SnapLayout?, index: Int)?) {
        let changed = t?.zone != target?.zone || t?.area != target?.area
        target = t
        guard changed else { return }
        if let t { overlay.show(t.zone.frame(in: t.area).insetBy(dx: 6, dy: 6), below: winID) } else { overlay.hide() }
    }

    /// Top or bottom border dragged to the screen edge → vertical stretch.
    private func updateVerticalTarget(_ f: CGRect) {
        let m = ScreenGeo.mouse
        guard snapped[winID] == nil, let screen = ScreenGeo.screen(for: f) else { return }
        let area = ScreenGeo.area(screen)
        let topMoving = abs(f.minY - startFrame.minY) > 1 && abs(f.maxY - startFrame.maxY) < 2
        let bottomMoving = abs(f.minY - startFrame.minY) < 2 && abs(f.maxY - startFrame.maxY) > 1
        let reached = (topMoving && m.y <= area.minY + 2) || (bottomMoving && m.y >= area.maxY - 2)
        let v = reached ? CGRect(x: f.minX, y: area.minY, width: f.width, height: area.height) : nil
        guard v != verticalTarget else { return }
        verticalTarget = v
        if let v { overlay.show(v.insetBy(dx: 4, dy: 4), below: winID) } else { overlay.hide() }
    }

    private func end() {
        guard timer != nil else { return }
        stopTimer()
        overlay.hide()
        bar.hide()
        let w = win, id = winID, start = startFrame
        defer { win = nil; mode = .undecided; target = nil; verticalTarget = nil }
        guard let w else { return }
        if mode == .resizing {
            if let f = w.frame, f != lastFrame { resized(id, from: lastFrame, to: f) }
            if let v = verticalTarget, let screen = ScreenGeo.screen(for: v) {
                let restore = CGRect(origin: start.origin, size: start.size)
                w.setFrame(v)
                snapped[id] = Snapped(el: w, frame: w.frame ?? v, zone: .maximize, area: ScreenGeo.area(screen),
                                      restore: restore, vertical: true)
            }
            return
        }
        guard mode == .moving, let t = target else { return }
        // let macOS finish the drag, then place the window
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.apply(t.zone, to: w, id: id, area: t.area, restore: start)
            if let layout = t.layout { SnapAssist.shared.offer(layout: layout, placed: t.index, area: t.area, excluding: id) }
        }
    }

    private func stopTimer() { timer?.invalidate(); timer = nil }

    // MARK: Snapping

    /// Puts the window in the zone and remembers it. `restore` is where it was before (if it wasn't already snapped).
    func apply(_ z: SnapZone, to w: WindowRef, id: CGWindowID, area: CGRect, restore: CGRect? = nil) {
        let target = z.frame(in: area)
        let before = w.frame
        w.setFrame(target)
        let actual = w.frame ?? target
        let keep = snapped[id]?.restore ?? restore ?? before ?? target
        snapped[id] = Snapped(el: w, frame: actual, zone: z, area: area, restore: keep)
        // another window already in that zone is no longer part of it (it was covered)
        for (other, s) in snapped where other != id && s.area == area &&
            s.frame.intersection(actual).area > 0.5 * min(s.frame.area, actual.area) {
            snapped.removeValue(forKey: other)
        }
        keepInPlace(w, id: id, target: target)
    }

    /// If something else moves the window right afterwards (e.g. macOS tiling still active),
    /// puts it back where you left it.
    private func keepInPlace(_ w: WindowRef, id: CGWindowID, target: CGRect) {
        for delay in [0.35, 0.8] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard self.timer == nil, var s = self.snapped[id], s.frame.distance(to: target) <= 8,
                      let f = w.frame, f.distance(to: target) > 8 else { return }
                w.setFrame(target)
                s.frame = w.frame ?? target
                self.snapped[id] = s
            }
        }
    }

    /// Puts the window back where it was before being snapped.
    private func restore(_ w: WindowRef, id: CGWindowID) {
        guard let s = snapped.removeValue(forKey: id) else { return }
        var r = s.restore
        if let screen = ScreenGeo.screen(for: r) {
            let a = ScreenGeo.area(screen)
            r.size.width = min(r.width, a.width); r.size.height = min(r.height, a.height)
            r.origin.x = min(max(r.minX, a.minX), a.maxX - r.width)
            r.origin.y = min(max(r.minY, a.minY), a.maxY - r.height)
        }
        w.setFrame(r)
    }

    /// Is the window still snapped where we put it (not moved, not minimized, app not hidden)?
    func inPlace(_ id: CGWindowID) -> Snapped? {
        guard let s = snapped[id] else { return nil }
        guard !s.el.isAppHidden, !s.el.isMinimized, let f = s.el.frame,
              f.distance(to: s.frame) < 6 else {
            snapped.removeValue(forKey: id)
            return nil
        }
        return s
    }

    /// Resize together (like Windows' "When I resize a snapped window, simultaneously resize any adjacent snapped window"):
    /// only between snapped windows, and only the shared border.
    private func resized(_ id: CGWindowID, from previous: CGRect, to new: CGRect) {
        guard var me = snapped[id] else { return }
        let old = me.frame // the last recorded position: a missed step doesn't break anything
        me.frame = new
        snapped[id] = me
        guard SnapSettings.linkedResize else { return }
        let a = me.area, tol: CGFloat = 4, minSide: CGFloat = 160
        let others = snapped.keys.filter { $0 != id }.compactMap { k in inPlace(k).map { (k, $0) } }
            .filter { $0.1.area == a }
        guard !others.isEmpty else { return }
        // inner dividers that moved: (old position, new position, vertical?)
        var moves: [(CGFloat, CGFloat, Bool)] = []
        if abs(old.maxX - new.maxX) > 0.5, abs(old.maxX - a.maxX) > tol { moves.append((old.maxX, new.maxX, true)) }
        if abs(old.minX - new.minX) > 0.5, abs(old.minX - a.minX) > tol { moves.append((old.minX, new.minX, true)) }
        if abs(old.maxY - new.maxY) > 0.5, abs(old.maxY - a.maxY) > tol { moves.append((old.maxY, new.maxY, false)) }
        if abs(old.minY - new.minY) > 0.5, abs(old.minY - a.minY) > tol { moves.append((old.minY, new.minY, false)) }
        guard !moves.isEmpty else { return }
        for (other, var s) in others {
            var r = s.frame
            for (from, to, vertical) in moves {
                // only if the border is really shared (the two windows touch along that border)
                if vertical {
                    let sideBySide = r.maxY > old.minY + 20 && r.minY < old.maxY - 20
                    guard sideBySide || touchesVertically(r, old) else { continue }
                    if abs(r.minX - from) < tol, r.maxX - to >= minSide { r = CGRect(x: to, y: r.minY, width: r.maxX - to, height: r.height) }
                    else if abs(r.maxX - from) < tol, to - r.minX >= minSide { r.size.width = to - r.minX }
                } else {
                    let stacked = r.maxX > old.minX + 20 && r.minX < old.maxX - 20
                    guard stacked || touchesHorizontally(r, old) else { continue }
                    if abs(r.minY - from) < tol, r.maxY - to >= minSide { r = CGRect(x: r.minX, y: to, width: r.width, height: r.maxY - to) }
                    else if abs(r.maxY - from) < tol, to - r.minY >= minSide { r.size.height = to - r.minY }
                }
            }
            guard r != s.frame else { continue }
            s.el.setFrame(r)
            s.frame = s.el.frame ?? r
            snapped[other] = s
        }
    }
    /// Quarters: the window above/below sharing the same vertical divider moves with it.
    private func touchesVertically(_ r: CGRect, _ o: CGRect) -> Bool { abs(r.minY - o.maxY) < 4 || abs(r.maxY - o.minY) < 4 }
    private func touchesHorizontally(_ r: CGRect, _ o: CGRect) -> Bool { abs(r.minX - o.maxX) < 4 || abs(r.maxX - o.minX) < 4 }

    // MARK: Keyboard (left ⌥ = Windows key)

    enum Arrow { case left, right, up, down }

    /// ⌥ + arrows like Win + arrows on Windows.
    func arrow(_ a: Arrow, shift: Bool) {
        guard let w = WindowRef.focused(), let id = w.id, let f = w.frame,
              let screen = ScreenGeo.screen(for: f) else { NSSound.beep(); return }
        SnapAssist.shared.dismiss()
        let area = ScreenGeo.area(screen)
        let current = inPlace(id)
        if shift { shiftArrow(a, w: w, id: id, frame: f, screen: screen, current: current); return }

        let z = current?.zone
        let vertical = current?.vertical == true
        func snap(_ zone: SnapZone, _ ar: CGRect = area, assist: SnapLayout? = nil) {
            apply(zone, to: w, id: id, area: ar, restore: current == nil ? f : nil)
            if let assist, let i = assist.zones.firstIndex(of: zone) {
                SnapAssist.shared.offer(layout: assist, placed: i, area: ar, excluding: id)
            }
        }
        switch a {
        case .left, .right:
            let isLeft = a == .left
            let near: SnapZone = isLeft ? .left : .right, far: SnapZone = isLeft ? .right : .left
            let nearTop: SnapZone = isLeft ? .topLeft : .topRight, nearBottom: SnapZone = isLeft ? .bottomLeft : .bottomRight
            let farTop: SnapZone = isLeft ? .topRight : .topLeft, farBottom: SnapZone = isLeft ? .bottomRight : .bottomLeft
            if z == near || z == nearTop || z == nearBottom {
                // already on that side: move to the adjacent monitor (on its opposite side), if any; otherwise to the opposite side
                let twin: SnapZone = z == near ? far : (z == nearTop ? farTop : farBottom)
                if let other = ScreenGeo.neighbor(of: screen, left: isLeft) {
                    snap(twin, ScreenGeo.area(other), assist: twin == far ? .halves : nil)
                } else {
                    snap(twin, assist: twin == far ? .halves : nil)
                }
            } else if z == far {
                restore(w, id: id) // from the opposite half, go back to the normal window
            } else if z == farTop {
                snap(nearTop)
            } else if z == farBottom {
                snap(nearBottom)
            } else {
                snap(near, assist: .halves)
            }
        case .up:
            if vertical { snap(.maximize) }
            else if z == .left { snap(.topLeft, assist: .quarters) }
            else if z == .right { snap(.topRight, assist: .quarters) }
            else if z == .bottomLeft { snap(.left, assist: .halves) }
            else if z == .bottomRight { snap(.right, assist: .halves) }
            else if z == .topLeft || z == .topRight || z == .maximize { return }
            else { snap(.maximize) }
        case .down:
            if z == .maximize || vertical { restore(w, id: id) }
            else if z == .left { snap(.bottomLeft, assist: .quarters) }
            else if z == .right { snap(.bottomRight, assist: .quarters) }
            else if z == .topLeft { snap(.left, assist: .halves) }
            else if z == .topRight { snap(.right, assist: .halves) }
            else if z == .bottomLeft || z == .bottomRight || current == nil {
                snapped.removeValue(forKey: id)
                w.minimize()
            } else { restore(w, id: id) }
        }
    }

    /// ⌥⇧← / ⌥⇧→: adjacent monitor (same zone or same relative position). ⌥⇧↑: stretch vertically; ⌥⇧↓: restore.
    private func shiftArrow(_ a: Arrow, w: WindowRef, id: CGWindowID, frame f: CGRect, screen: NSScreen, current: Snapped?) {
        let area = ScreenGeo.area(screen)
        switch a {
        case .left, .right:
            guard let other = ScreenGeo.neighbor(of: screen, left: a == .left) else { NSSound.beep(); return }
            let dest = ScreenGeo.area(other)
            if let current, !current.vertical {
                apply(current.zone, to: w, id: id, area: dest)
            } else {
                let rx = (f.minX - area.minX) / max(1, area.width - f.width)
                let ry = (f.minY - area.minY) / max(1, area.height - f.height)
                let size = CGSize(width: min(f.width, dest.width), height: min(f.height, dest.height))
                let origin = CGPoint(x: dest.minX + max(0, min(1, rx)) * (dest.width - size.width),
                                     y: dest.minY + max(0, min(1, ry)) * (dest.height - size.height))
                snapped.removeValue(forKey: id)
                w.setFrame(CGRect(origin: origin, size: size))
            }
        case .up:
            guard current == nil || current?.vertical == false && current?.zone != .maximize else { return }
            let v = CGRect(x: f.minX, y: area.minY, width: f.width, height: area.height)
            w.setFrame(v)
            snapped[id] = Snapped(el: w, frame: w.frame ?? v, zone: .maximize, area: area,
                                  restore: current?.restore ?? f, vertical: true)
        case .down:
            if current?.vertical == true { restore(w, id: id) }
        }
    }

    /// ⌥Z: the layouts next to the active window.
    func showLayoutsForFocusedWindow() {
        guard let w = WindowRef.focused(), let id = w.id, let f = w.frame,
              let screen = ScreenGeo.screen(for: f) else { NSSound.beep(); return }
        SnapAssist.shared.dismiss()
        let area = ScreenGeo.area(screen)
        LayoutFlyout.shared.show(near: f, area: area) { [weak self] layout, index in
            guard let self else { return }
            self.apply(layout.zones[index], to: w, id: id, area: area, restore: self.inPlace(id) == nil ? f : nil)
            SnapAssist.shared.offer(layout: layout, placed: index, area: area, excluding: id)
        }
    }
}
