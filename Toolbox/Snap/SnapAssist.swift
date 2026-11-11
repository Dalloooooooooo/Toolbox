import Cocoa
import SwiftUI

/// After a window is snapped, offers the other windows to place in the remaining free space.
final class SnapAssist: ObservableObject {
    static let shared = SnapAssist()

    struct Candidate: Identifiable {
        let info: WindowInfo
        var id: CGWindowID { info.id }
    }

    @Published var candidates: [Candidate] = []
    @Published var previews: [CGWindowID: NSImage] = [:]
    @Published var zoneLabel = ""
    @Published var selected: Int?

    private var panel: NSPanel?
    /// A space to fill: its logical zone, where exactly the window goes, and how to call it.
    private struct Slot { let zone: SnapZone; let frame: CGRect; let label: String }
    private var pending: [Slot] = []
    private var slot = Slot(zone: .right, frame: .zero, label: "")
    private var area: CGRect = .zero
    private var used: Set<CGWindowID> = []
    private var replacing = false // offering zones that are already taken
    private var layoutFrames: [CGRect] = []

    /// Windows that are part of the layout being filled: snapped, still in place, exactly in one of its zones.
    /// Windows snapped some other way (another layout, a half that doesn't match) are offered like the others.
    private func inLayout(_ id: CGWindowID) -> WindowSnap.Snapped? {
        guard let s = WindowSnap.shared.inPlace(id), s.area == area,
              layoutFrames.contains(where: { $0.distance(to: s.frame) < 12 }) else { return nil }
        return s
    }
    private var quietUntil = Date.distantPast // activations we cause ourselves don't close Snap Assist

    var isVisible: Bool { panel?.isVisible == true }

    private init() {
        // switching to another app (click, ⌘Tab, Dock…) closes Snap Assist, as on Windows
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                          object: nil, queue: .main) { [weak self] _ in
            guard let self, self.isVisible, Date() > self.quietUntil else { return }
            self.dismiss()
        }
    }

    /// After a window has been placed in zone `placed` of `layout`: offers the layout's zones that are still free.
    func offer(layout: SnapLayout, placed: Int, area: CGRect, excluding id: CGWindowID) {
        guard SnapSettings.assist else { return }
        let n = layout.zones.count
        let order = (1..<max(1, n)).map { layout.zones[(placed + $0) % n] }
        start(order.map { Slot(zone: $0, frame: $0.frame(in: area), label: $0.label) }, area: area, excluding: id,
              layout: layout.zones.map { $0.frame(in: area) })
    }

    /// After a window has been dropped on zones `placed` of a zone layout (`frames`, numbered from 1):
    /// offers the other zones, the ones after it first. Zones overlapping where the window went are skipped.
    func offer(zoneFrames frames: [CGRect], placed: Set<Int>, area: CGRect, excluding id: CGWindowID) {
        guard ZoneSettings.assist, let last = placed.max() else { return }
        let taken = placed.map { frames[$0] }.reduce(CGRect.null) { $0.union($1) }
        let n = frames.count
        let order = (1..<max(1, n)).map { (last + $0) % n }.filter { i in
            !placed.contains(i) && frames[i].intersection(taken).area <= 0.3 * min(frames[i].area, taken.area)
        }
        let slots = order.map { i -> Slot in
            let f = frames[i]
            let unit = CGRect(x: (f.minX - area.minX) / area.width, y: (f.minY - area.minY) / area.height,
                              width: f.width / area.width, height: f.height / area.height)
            return Slot(zone: SnapZone(unit: unit), frame: f, label: String(localized: "zone \(i + 1)"))
        }
        start(slots, area: area, excluding: id, layout: frames)
    }

    /// `layout`: every zone of the layout being filled, to tell which windows are already part of it.
    private func start(_ order: [Slot], area: CGRect, excluding id: CGWindowID, layout: [CGRect]) {
        guard !order.isEmpty else { Log.info("Snap Assist: no other zones to fill"); return }
        self.area = area
        layoutFrames = layout
        used = [id]
        pending = order.filter { isFree($0, ignoring: id) }
        // the other zones are all taken (e.g. a window snapped next to one already snapped): ask anyway,
        // to replace what's there; clicking elsewhere or Esc leaves everything as it is
        replacing = pending.isEmpty
        if replacing { pending = order }
        quietUntil = Date().addingTimeInterval(0.6)
        next()
    }

    /// A zone is free unless a window of the layout is already in it.
    private func isFree(_ z: Slot, ignoring id: CGWindowID) -> Bool {
        !WindowSnap.shared.snapped.keys.contains { k in
            k != id && inLayout(k).map { $0.frame.distance(to: z.frame) < 12 } == true
        }
    }

    private func next() {
        guard let z = pending.first else { dismiss(); return }
        pending.removeFirst()
        guard replacing || isFree(z, ignoring: 0) else { next(); return }
        slot = z
        // windows already in the layout are not offered again, unless every zone is taken: then Snap Assist
        // still asks (you may want to swap them), offering also the windows that are already there
        let placedHere = replacing ? [] : Set(WindowSnap.shared.snapped.keys.filter { inLayout($0) != nil })
        let list = WindowManager.listWindows()
            .filter { !used.contains($0.id) && !placedHere.contains($0.id) }
            .filter { $0.state == .normal || $0.state == .minimized || $0.state == .hidden }
        guard !list.isEmpty else {
            Log.info("Snap Assist: no windows to offer (\(placedHere.count) already in the layout)")
            dismiss()
            return
        }
        candidates = list.map { Candidate(info: $0) }
        previews = list.reduce(into: [:]) { $0[$1.id] = PreviewStore.image(for: $1.id) }
        zoneLabel = slot.label
        selected = 0 // Return immediately picks the first one (the most recent)
        let r = slot.frame
        show(r)
        let visible = list.filter { $0.state == .normal }.map(\.id)
        if CGPreflightScreenCaptureAccess(), !visible.isEmpty {
            // captured at the size they are shown, not larger: sharp, without wasting memory
            let size = AssistGrid.previewSize(count: list.count, panel: r.insetBy(dx: 6, dy: 6).size)
            WindowManager.capturePreviews(ids: visible, maxSize: size) { [weak self] id, img in
                self?.previews[id] = img
            }
        }
    }

    private func show(_ r: CGRect) {
        let p = panel ?? make()
        panel = p
        p.setFrame(ScreenGeo.ns(r.insetBy(dx: 6, dy: 6)), display: true)
        p.alphaValue = 0
        p.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.15; p.animator().alphaValue = 1 }
    }

    func choose(_ c: Candidate) {
        let info = c.info
        used.insert(info.id)
        let z = slot, a = area
        panel?.orderOut(nil)
        quietUntil = Date().addingTimeInterval(1.2)
        if info.state == .hidden { NSRunningApplication(processIdentifier: info.pid)?.unhide() }
        // hidden apps show their windows with a slight delay
        DispatchQueue.main.asyncAfter(deadline: .now() + (info.state == .hidden ? 0.25 : 0)) {
            guard let w = WindowRef.of(info) else { self.next(); return }
            if info.state == .minimized { w.minimize(false) }
            WindowSnap.shared.place(z.frame, zone: z.zone, to: w, id: info.id, area: a)
            var s = info
            s.state = .normal
            WindowManager.focus(s)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { self.next() }
        }
    }

    /// The X on the thumbnail closes that window (as on Windows).
    func close(_ c: Candidate) {
        _ = WindowManager.closeWindow(c.info)
        candidates.removeAll { $0.id == c.id }
        if candidates.isEmpty { dismiss() } else if let s = selected, s >= candidates.count { selected = candidates.count - 1 }
    }

    func dismiss() {
        pending = []
        panel?.orderOut(nil)
        candidates = []
        previews = [:]
    }

    /// A click outside the panel leaves the space empty.
    func mouseDown(at p: CGPoint) {
        guard let panel, panel.isVisible, !ScreenGeo.cg(panel.frame).contains(p) else { return }
        DispatchQueue.main.async { self.dismiss() }
    }

    /// Esc closes, arrows/Tab and Return choose; any other key closes Snap Assist and reaches the app.
    /// Returns true if the key should be swallowed.
    func handleKey(_ key: Int64) -> Bool {
        guard isVisible else { return false }
        let n = candidates.count
        let nav: [Int64] = [53, 123, 124, 125, 126, 48, 36, 76]
        DispatchQueue.main.async {
            switch key {
            case 53: self.dismiss()
            case 123, 126: self.selected = n == 0 ? nil : ((self.selected ?? 0) - 1 + n) % n
            case 124, 125, 48: self.selected = n == 0 ? nil : ((self.selected ?? -1) + 1) % n
            case 36, 76: if let i = self.selected, i < n { self.choose(self.candidates[i]) }
            default: self.dismiss()
            }
        }
        return nav.contains(key)
    }

    private func make() -> NSPanel {
        let p = AssistPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        p.hidesOnDeactivate = false
        p.contentView = FirstMouseHostingView(rootView: SnapAssistView(model: self))
        return p
    }
}

private final class AssistPanel: NSPanel {
    override var canBecomeMain: Bool { false }
}
