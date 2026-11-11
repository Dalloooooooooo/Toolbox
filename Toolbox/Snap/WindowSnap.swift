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

    private(set) var snapped: [CGWindowID: Snapped] = [:] {
        didSet { for (id, s) in snapped { remembered[id] = Remembered(restore: s.restore, frame: s.frame) } }
    }
    /// The size before snapping, kept apart from `snapped`: a window can leave the snapped group (covered
    /// by another one, minimized, its app hidden) and still get its size back when dragged away, like on Windows.
    private struct Remembered { let restore: CGRect; var frame: CGRect }
    private var remembered: [CGWindowID: Remembered] = [:]
    private var timer: Timer?
    private var win: WindowRef?
    private var winID: CGWindowID = 0
    private var startFrame: CGRect = .zero
    private var lastFrame: CGRect = .zero
    private var grabX: CGFloat = 0.5 // point grabbed in the title bar, as a fraction of the width
    private var onEdge = false        // grabbed by a border (resizing) rather than by the title bar
    private var mode: Mode = .undecided
    private typealias Target = (zone: SnapZone, area: CGRect, layout: SnapLayout?, index: Int)
    private var target: Target?
    private var grabPoint: CGPoint = .zero
    private var verticalTarget: CGRect?
    private var links: [Link] = []  // neighbors that share a border with the window being resized
    private let overlay = SnapOverlay()
    private let bar = LayoutPicker(style: .bar)

    // MARK: Events from the tap (no heavy work there: defer to the main run loop)

    func mouseDown(at p: CGPoint) {
        SnapAssist.shared.mouseDown(at: p)
        LayoutFlyout.shared.mouseDown(at: p)
        guard SnapSettings.enabled || ZoneSettings.enabled || Settings.aeroShake else { return }
        DispatchQueue.main.async { self.begin(at: p) }
    }

    func mouseUp() {
        DispatchQueue.main.async { self.end() }
    }

    private func begin(at p: CGPoint) {
        stopTimer()
        guard AXIsProcessTrusted(), let w = WindowRef.at(p),
              let id = w.id, let f = w.frame else { return }
        WindowAnimator.cancel(id) // grabbed while still moving: it stays under the mouse
        win = w; winID = id; startFrame = f; lastFrame = f
        grabX = f.width > 0 ? (p.x - f.minX) / f.width : 0.5
        grabPoint = p
        // the resize borders are a thin strip around the window
        let edgeDistance = min(abs(p.x - f.minX), abs(f.maxX - p.x), abs(p.y - f.minY), abs(f.maxY - p.y))
        onEdge = edgeDistance <= 8
        mode = .undecided; target = nil; verticalTarget = nil
        AeroShake.dragStarted()
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
            if onEdge, f.size != startFrame.size { mode = .resizing; linkNeighbors() }
            else if abs(f.minX - startFrame.minX) > 2 || abs(f.minY - startFrame.minY) > 2 ||
                        (!onEdge && f.size != startFrame.size) { startMoving(f) }
        }
        switch mode {
        case .moving:
            AeroShake.dragging(win, id: winID, x: ScreenGeo.mouse.x)
            // zones (⇧ held) take over from edge snapping
            if ZoneDrag.shared.update(pid: win.pid, window: winID) { setTarget(nil); bar.hide() }
            else if SnapSettings.enabled { updateTarget() }
        case .resizing:
            if f != lastFrame { resized(to: f) }
            if SnapSettings.enabled { updateVerticalTarget(f) }
        case .undecided: break
        }
        lastFrame = f
    }

    private func startMoving(_ f: CGRect) {
        mode = .moving
        SnapAssist.shared.dismiss()
        LayoutFlyout.shared.dismiss()
        // a snapped window dragged away always returns to its previous size
        snapped.removeValue(forKey: winID)
        guard let win, let r = restoreFrame(for: winID, at: startFrame) else { return }
        remembered.removeValue(forKey: winID)
        startFrame = r // if dropped on another zone, this is still the size to go back to
        let m = ScreenGeo.mouse
        var size = r.size
        if let screen = ScreenGeo.screen(at: m) {
            let a = ScreenGeo.area(screen)
            size = CGSize(width: min(size.width, a.width), height: min(size.height, a.height))
        }
        guard size != f.size else { return }
        win.setSize(size)
        win.setPosition(CGPoint(x: m.x - grabX * size.width, y: f.minY))
    }

    /// The frame the window had before being snapped, if it still is where snapping put it (or at least
    /// against two edges of the screen, as every snap zone is). If something else moved it meanwhile,
    /// the memory is stale and is forgotten.
    private func restoreFrame(for id: CGWindowID, at frame: CGRect) -> CGRect? {
        guard let r = remembered[id] else { return nil }
        if frame.distance(to: r.frame) < 10 { return r.restore }
        if let screen = ScreenGeo.screen(for: frame) {
            let a = ScreenGeo.area(screen), tol: CGFloat = 10
            let edges = [abs(frame.minX - a.minX), abs(frame.maxX - a.maxX),
                         abs(frame.minY - a.minY), abs(frame.maxY - a.maxY)].filter { $0 <= tol }.count
            if edges >= 2 { return r.restore }
        }
        remembered.removeValue(forKey: id)
        return nil
    }

    /// Forgets windows that no longer exist.
    private func pruneRemembered() {
        guard remembered.count > 20,
              let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return }
        let alive = Set(list.compactMap { $0[kCGWindowNumber as String] as? CGWindowID })
        remembered = remembered.filter { alive.contains($0.key) }
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
            // not on a layout: only the top edge itself counts (maximize, below)
            if m.y > full.minY + edge { setTarget(nil); return }
        } else {
            bar.hide()
        }

        setTarget(edgeTarget(at: m))
    }

    /// Edges, corners and top edge (not the layout bar) under `m`.
    private func edgeTarget(at m: CGPoint) -> Target? {
        guard let screen = ScreenGeo.screen(at: m) else { return nil }
        let full = ScreenGeo.cg(screen.frame)
        let area = ScreenGeo.area(screen)
        let edge: CGFloat = SnapSettings.nearEdge ? 18 : 3
        let corner = max(60, full.height * 0.12)
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
        guard let z else { return nil }
        let layout: SnapLayout? = z == .maximize ? nil : (z == .left || z == .right ? .halves : .quarters)
        return (z, area, layout, layout?.zones.firstIndex(of: z) ?? 0)
    }

    private func setTarget(_ t: Target?) {
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
        defer { win = nil; mode = .undecided; target = nil; verticalTarget = nil; links = [] }
        guard let w else { return }
        if mode == .resizing {
            if let f = w.frame, f != lastFrame { resized(to: f) }
            finishLinkedResize(w, id: id)
            if let v = verticalTarget, let screen = ScreenGeo.screen(for: v) {
                let restore = restoreFrame(for: id, at: start) ?? start
                snapped[id] = Snapped(el: w, frame: v, zone: .maximize, area: ScreenGeo.area(screen),
                                      restore: restore, vertical: true)
                WindowAnimator.move(w, to: v)
            }
            return
        }
        let release = ScreenGeo.mouse
        if mode == .moving, let z = ZoneDrag.shared.target {
            ZoneDrag.shared.stop()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self.place(z.frame, zone: SnapZone(unit: z.unit), to: w, id: id, area: z.area, restore: start)
                // like Snap Assist: the other open windows for the remaining zones
                SnapAssist.shared.offer(zoneFrames: z.zones, placed: z.lit, area: z.area, excluding: id)
            }
            return
        }
        ZoneDrag.shared.stop()
        if mode == .undecided, !onEdge, SnapSettings.enabled, hypot(release.x - grabPoint.x, release.y - grabPoint.y) > 10 {
            // thrown and dropped at once: macOS hasn't moved the window yet, look again in a moment
            let grab = grabX
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                self.thrown(w, id: id, start: start, release: release, grabX: grab)
            }
            return
        }
        if mode == .moving, SnapSettings.enabled { updateTarget() } // where the mouse is at release
        guard mode == .moving, let t = target else { return }
        // let macOS finish the drag, then place the window
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.apply(t.zone, to: w, id: id, area: t.area, restore: start)
            if let layout = t.layout { SnapAssist.shared.offer(layout: layout, placed: t.index, area: t.area, excluding: id) }
        }
    }

    private func stopTimer() { timer?.invalidate(); timer = nil }

    /// A drag so quick that it ended before we saw the window move. If the window did move (it's not,
    /// say, a text selection), it is snapped where it was dropped, or gets its previous size back.
    private func thrown(_ w: WindowRef, id: CGWindowID, start: CGRect, release: CGPoint, grabX: CGFloat) {
        guard let f = w.frame, abs(f.minX - start.minX) > 2 || abs(f.minY - start.minY) > 2 else { return }
        let previous = snapped.removeValue(forKey: id)?.restore ?? restoreFrame(for: id, at: start)
        if let t = edgeTarget(at: release) {
            apply(t.zone, to: w, id: id, area: t.area, restore: previous ?? start)
            if let layout = t.layout { SnapAssist.shared.offer(layout: layout, placed: t.index, area: t.area, excluding: id) }
        } else if let previous, previous.size != f.size {
            remembered.removeValue(forKey: id)
            w.setSize(previous.size)
            w.setPosition(CGPoint(x: release.x - grabX * previous.width, y: f.minY))
        }
    }

    // MARK: Snapping

    /// Puts the window in the zone and remembers it. `restore` is where it was before (if it wasn't already snapped).
    func apply(_ z: SnapZone, to w: WindowRef, id: CGWindowID, area: CGRect, restore: CGRect? = nil) {
        place(z.frame(in: area), zone: z, to: w, id: id, area: area, restore: restore)
    }

    /// Like `apply`, at an exact frame (zones with spacing between them).
    func place(_ target: CGRect, zone z: SnapZone, to w: WindowRef, id: CGWindowID, area: CGRect, restore: CGRect? = nil) {
        let before = w.frame
        let keep = snapped[id]?.restore ?? before.flatMap { restoreFrame(for: id, at: $0) } ?? restore ?? before ?? target
        pruneRemembered()
        snapped[id] = Snapped(el: w, frame: target, zone: z, area: area, restore: keep)
        // another window already in that zone is no longer part of it (it was covered)
        for (other, s) in snapped where other != id && s.area == area &&
            s.frame.intersection(target).area > 0.5 * min(s.frame.area, target.area) {
            snapped.removeValue(forKey: other)
        }
        WindowAnimator.move(w, to: target) { [weak self] in
            // apps may round the size (e.g. to whole text lines): record where it really is
            if let f = w.frame, self?.snapped[id]?.frame == target { self?.snapped[id]?.frame = f }
            self?.keepInPlace(w, id: id, target: target)
        }
    }

    /// If something else moves the window right afterwards (e.g. macOS tiling still active),
    /// puts it back where you left it.
    private func keepInPlace(_ w: WindowRef, id: CGWindowID, target: CGRect) {
        for delay in [0.35, 0.8] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard self.timer == nil, !WindowAnimator.isAnimating(id), var s = self.snapped[id], s.frame.distance(to: target) <= 8,
                      let f = w.frame, f.distance(to: target) > 8 else { return }
                w.setFrame(target)
                s.frame = w.frame ?? target
                self.snapped[id] = s
            }
        }
    }

    /// Puts the window back where it was before being snapped.
    private func restore(_ w: WindowRef, id: CGWindowID) {
        let s = snapped.removeValue(forKey: id)
        guard var r = s?.restore ?? remembered[id]?.restore else { return }
        remembered.removeValue(forKey: id)
        if let screen = ScreenGeo.screen(for: r) {
            let a = ScreenGeo.area(screen)
            r.size.width = min(r.width, a.width); r.size.height = min(r.height, a.height)
            r.origin.x = min(max(r.minX, a.minX), a.maxX - r.width)
            r.origin.y = min(max(r.minY, a.minY), a.maxY - r.height)
        }
        WindowAnimator.move(w, to: r)
    }

    /// Is the window still snapped where we put it (not moved, not minimized, app not hidden)?
    func inPlace(_ id: CGWindowID) -> Snapped? {
        guard let s = snapped[id] else { return nil }
        if WindowAnimator.isAnimating(id) { return s } // on its way there
        guard !s.el.isAppHidden, !s.el.isMinimized, let f = s.el.frame,
              f.distance(to: s.frame) < 6 else {
            snapped.removeValue(forKey: id)
            return nil
        }
        return s
    }

    // MARK: Resize together
    //
    // Like Windows' "When I resize a snapped window, simultaneously resize any adjacent snapped window":
    // only between snapped windows, and only along the shared border. The neighbors are found once, when
    // the resize starts, and every step is computed from where they were then: a step the neighbor can't
    // follow (too narrow) doesn't detach it, and going back still works.

    private enum Edge { case minX, maxX, minY, maxY
        var vertical: Bool { self == .minX || self == .maxX }
        func value(of r: CGRect) -> CGFloat {
            switch self { case .minX: r.minX; case .maxX: r.maxX; case .minY: r.minY; case .maxY: r.maxY }
        }
        /// `r` with this edge moved to `v`, the opposite edge staying put.
        func moving(_ r: CGRect, to v: CGFloat) -> CGRect {
            switch self {
            case .minX: CGRect(x: v, y: r.minY, width: r.maxX - v, height: r.height)
            case .maxX: CGRect(x: r.minX, y: r.minY, width: v - r.minX, height: r.height)
            case .minY: CGRect(x: r.minX, y: v, width: r.width, height: r.maxY - v)
            case .maxY: CGRect(x: r.minX, y: r.minY, width: r.width, height: v - r.minY)
            }
        }
    }

    /// The neighbor's `edge` follows our `mine`.
    private struct Link { let id: CGWindowID; let el: WindowRef; let start: CGRect; let edge: Edge; let mine: Edge }
    private static let minSide: CGFloat = 160

    private func linkNeighbors() {
        links = []
        guard SnapSettings.linkedResize, let me = snapped[winID] else { return }
        let old = startFrame, a = me.area, tol: CGFloat = 6
        let others = snapped.keys.filter { $0 != winID }.compactMap { k in inPlace(k).map { (k, $0) } }
            .filter { $0.1.area == a }
        for mine in [Edge.minX, .maxX, .minY, .maxY] {
            let line = mine.value(of: old)
            guard abs(line - mine.value(of: a)) > tol else { continue } // screen edge, not a divider
            for (id, s) in others {
                let r = s.frame
                // side by side along that border, or (quarters) above/below us on the same divider
                let alongside = mine.vertical
                    ? (r.maxY > old.minY + 20 && r.minY < old.maxY - 20) || abs(r.minY - old.maxY) < tol || abs(r.maxY - old.minY) < tol
                    : (r.maxX > old.minX + 20 && r.minX < old.maxX - 20) || abs(r.minX - old.maxX) < tol || abs(r.maxX - old.minX) < tol
                guard alongside else { continue }
                let candidates: [Edge] = mine.vertical ? [.minX, .maxX] : [.minY, .maxY]
                if let edge = candidates.first(where: { abs($0.value(of: r) - line) < tol }) {
                    links.append(Link(id: id, el: s.el, start: r, edge: edge, mine: mine))
                }
            }
        }
    }

    /// The window being resized now has frame `f`: the linked neighbors follow.
    private func resized(to f: CGRect) {
        snapped[winID]?.frame = f
        for (id, group) in Dictionary(grouping: links, by: \.id) {
            var r = group[0].start
            for l in group { r = l.edge.moving(r, to: l.mine.value(of: f)) }
            guard r.width >= Self.minSide, r.height >= Self.minSide, var s = snapped[id], r != s.frame else { continue }
            group[0].el.setFrame(r)
            s.frame = r
            snapped[id] = s
        }
    }

    /// At the end, records where everything really is. If a neighbor couldn't get as small as asked
    /// (apps have a minimum width), the border stops there, as on Windows, so the two don't overlap.
    private func finishLinkedResize(_ w: WindowRef, id: CGWindowID) {
        guard !links.isEmpty else { return }
        var mine = w.frame ?? snapped[id]?.frame ?? .zero
        for l in links {
            guard let actual = l.el.frame else { continue }
            snapped[l.id]?.frame = actual
            let theirs = l.edge.value(of: actual)
            if abs(theirs - l.mine.value(of: mine)) > 2 { mine = l.mine.moving(mine, to: theirs) }
        }
        if mine.width >= Self.minSide, mine.height >= Self.minSide, mine != w.frame {
            w.setFrame(mine)
        }
        snapped[id]?.frame = w.frame ?? mine
    }

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
                WindowAnimator.move(w, to: CGRect(origin: origin, size: size))
            }
        case .up:
            guard current == nil || current?.vertical == false && current?.zone != .maximize else { return }
            let v = CGRect(x: f.minX, y: area.minY, width: f.width, height: area.height)
            WindowAnimator.move(w, to: v)
            snapped[id] = Snapped(el: w, frame: v, zone: .maximize, area: area,
                                  restore: current?.restore ?? restoreFrame(for: id, at: f) ?? f, vertical: true)
        case .down:
            if current?.vertical == true { restore(w, id: id) }
        }
    }

    /// Maximize button (the green one): fills the screen the window is on, on the same desktop;
    /// if it already fills it, gives it back its previous size.
    func toggleMaximize(_ w: WindowRef) {
        guard let id = w.id, let f = w.frame, let screen = ScreenGeo.screen(for: f) else { return }
        SnapAssist.shared.dismiss()
        LayoutFlyout.shared.dismiss()
        let area = ScreenGeo.area(screen)
        guard f.distance(to: area) < 8 else {
            apply(.maximize, to: w, id: id, area: area, restore: inPlace(id) == nil ? f : nil)
            return
        }
        if snapped[id] != nil || remembered[id] != nil { restore(w, id: id); return }
        // it was already this big and we don't know its previous size: a centered window, as Windows does
        let size = CGSize(width: (area.width * 0.7).rounded(), height: (area.height * 0.75).rounded())
        WindowAnimator.move(w, to: CGRect(x: (area.midX - size.width / 2).rounded(), y: (area.midY - size.height / 2).rounded(),
                          width: size.width, height: size.height))
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
