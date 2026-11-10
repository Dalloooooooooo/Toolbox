import Cocoa

/// Window previews when hovering a Dock icon, like the Windows taskbar.
/// The Dock doesn't report hovering: we check the mouse position 15 times per second near the Dock
/// (4 times elsewhere, to save energy), and query the Dock (accessibility) only when the mouse is in its area.
@MainActor
enum DockPreview {
    private struct DockItem { let frame: CGRect; let bundleID: String? } // frame in AX coordinates (origin at top left)

    private static var timer: Timer?
    private static var dockFrame: CGRect = .zero
    private static var itemsTime = Date.distantPast
    private static var dockPid: pid_t = 0

    private static var panel: PreviewPanel?
    private static let model = DockPreviewModel()
    /// App under the mouse and since when (for the short delay before showing the preview).
    private static var hoverBundle: String?
    private static var hoverSince = Date()
    private static var hoverItem: DockItem?
    /// After a click on the icon the preview doesn't reappear until you move to another icon (like on Windows).
    private static var suppressed: String?
    private static var leftAt: Date?

    private static var fastPolling = true

    static func start() { schedule(fast: false) }

    private static func schedule(fast: Bool) {
        timer?.invalidate()
        fastPolling = fast
        let t = Timer(timeInterval: fast ? 1.0 / 15 : 1.0 / 4, repeats: true) { _ in MainActor.assumeIsolated { tick() } }
        t.tolerance = fast ? 0.01 : 0.05
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Mouse click anywhere (from the event tap): outside the panel it closes it.
    static func mouseDown(at axPoint: CGPoint) {
        guard let panel, panel.isVisible else {
            if let hb = hoverBundle { suppressed = hb }
            return
        }
        if !panel.frame.contains(cocoaPoint(axPoint)) {
            suppressed = hoverBundle
            hide()
        }
    }

    // MARK: Loop

    private static func tick() {
        guard Settings.dockPreviews else { if panel?.isVisible == true { hide() }; return }
        let mouse = NSEvent.mouseLocation
        let ax = axPoint(mouse)

        // over the panel (or in the gap between panel and icon): stay open
        if let panel, panel.isVisible, keeps(panel, mouse) { leftAt = nil; return }

        refreshDockFrame()
        // close to the Dock (or with the preview open) check often; elsewhere a slower pace is enough
        let near = dockFrame.insetBy(dx: -250, dy: -250).contains(ax) || panel?.isVisible == true
        if near != fastPolling { schedule(fast: near) }
        // with Dock magnification the icons grow and move: wide area plus exact hit test
        let item = dockFrame.insetBy(dx: -100, dy: -100).contains(ax) ? itemAt(ax) : nil
        let bundle = item?.bundleID

        if bundle != hoverBundle {
            hoverBundle = bundle
            hoverSince = Date()
            if bundle != suppressed { suppressed = nil }
        }
        if let item { hoverItem = item }
        if let bundle, let item, suppressed != bundle {
            leftAt = nil
            let visible = panel?.isVisible == true
            // delay only for the first appearance; moving from one icon to another switches immediately
            if visible ? model.bundleID != bundle : Date().timeIntervalSince(hoverSince) > 0.35 {
                show(bundle: bundle, item: item)
            }
            return
        }
        // outside icons and panel: close after a short grace period
        if panel?.isVisible == true {
            if leftAt == nil { leftAt = Date() }
            if Date().timeIntervalSince(leftAt!) > 0.25 { hide() }
        }
    }

    // MARK: Dock

    private static func refreshDockFrame() {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first
        else { return }
        if dock.processIdentifier != dockPid || Date().timeIntervalSince(itemsTime) > 2 {
            dockPid = dock.processIdentifier
            loadItems()
        }
    }

    private static func loadItems() {
        itemsTime = Date()
        let app = AXUIElementCreateApplication(dockPid)
        let list = (attr(app, kAXChildrenAttribute) as? [AXUIElement])?.first { attr($0, kAXRoleAttribute) as? String == "AXList" }
        dockFrame = list.map(frame) ?? .zero
    }

    /// Icon exactly under the mouse right now (asked to the Dock).
    private static func itemAt(_ p: CGPoint) -> DockItem? {
        var el: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateApplication(dockPid), Float(p.x), Float(p.y), &el) == .success,
              let el, attr(el, kAXSubroleAttribute) as? String == "AXApplicationDockItem" else { return nil }
        var url: URL?
        if let u = attr(el, kAXURLAttribute) as? URL { url = u }
        else if let s = attr(el, kAXURLAttribute) as? String { url = URL(string: s) }
        return DockItem(frame: frame(el), bundleID: url.flatMap { bundleID(for: $0) })
    }

    private static var bundleCache: [URL: String] = [:]
    private static func bundleID(for url: URL) -> String? {
        if let id = bundleCache[url] { return id }
        let id = Bundle(url: url)?.bundleIdentifier
        bundleCache[url] = id
        return id
    }

    // MARK: Panel

    private static func show(bundle: String, item: DockItem) {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first(where: { !$0.isTerminated })
        else { hide(); return }
        let windows = WindowManager.windows(of: app.processIdentifier)
        guard !windows.isEmpty else { hide(); return } // no windows: the Dock's own label stays
        model.bundleID = bundle
        model.appName = app.localizedName ?? ""
        model.windows = windows
        model.tileWidth = Settings.dockPreviewWidth
        model.images = windows.reduce(into: [:]) { $0[$1.id] = PreviewStore.image(for: $1.id) }

        let p = panel ?? makePanel()
        panel = p
        let size = panelSize()
        p.setContentSize(size)
        p.setFrameOrigin(origin(for: size, item: item))
        p.orderFrontRegardless()

        // fresh previews of the visible windows
        let live = windows.filter { $0.state == .normal }.map(\.id)
        let maxSize = CGSize(width: model.tileWidth, height: model.tileWidth * 0.65)
        WindowManager.capturePreviews(ids: live, maxSize: maxSize) { id, img in
            PreviewStore.set(img, for: id)
            if model.bundleID == bundle { model.images[id] = img }
        }
    }

    static func hide() {
        panel?.orderOut(nil)
        model.bundleID = nil
        leftAt = nil
    }

    /// After a click on a preview or on the X.
    static func focus(_ w: WindowInfo) {
        suppressed = hoverBundle
        hide()
        WindowManager.focus(w)
    }

    static func close(_ w: WindowInfo) {
        if AutoQuit.isLastWindow(w.pid) { // like ⌘Q: the app saves its session
            hide()
            NSRunningApplication(processIdentifier: w.pid)?.terminate()
            return
        }
        if WindowManager.closeWindow(w) {
            model.windows.removeAll { $0.id == w.id }
            AutoQuit.windowClosed(pid: w.pid)
            if model.windows.isEmpty { hide() } else { resize() }
        } else {
            // window on another desktop: go there and close it there
            hide()
            WindowManager.focus(w)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { WindowManager.closeWindow(w) }
        }
    }

    private static func resize() {
        guard let p = panel, let item = hoverItem else { return }
        let size = panelSize()
        p.setContentSize(size)
        p.setFrameOrigin(origin(for: size, item: item))
    }

    /// Computed size (SwiftUI updates the view only on the next pass, so we can't ask the view for it).
    private static func panelSize() -> CGSize {
        let n = CGFloat(DockPreviewView.visibleCount(model.windows.count, tileWidth: model.tileWidth))
        let w = model.tileWidth
        return CGSize(width: n * (w + 16) + (n - 1) * 10 + 20, height: w * 0.62 + 20 + 6 + 16 + 20)
    }

    private static func makePanel() -> PreviewPanel {
        let p = PreviewPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        p.level = .popUpMenu
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.contentView = FirstMouseHostingView(rootView: DockPreviewView(model: model))
        return p
    }

    /// Panel position next to the icon, depending on which side the Dock is on.
    private static func origin(for size: CGSize, item: DockItem) -> CGPoint {
        let icon = cocoaRect(item.frame)
        let screen = NSScreen.screens.first { $0.frame.contains(CGPoint(x: icon.midX, y: icon.midY)) } ?? NSScreen.main!
        let area = screen.frame.insetBy(dx: 8, dy: 8)
        var o: CGPoint
        switch dockOrientation {
        case "left": o = CGPoint(x: icon.maxX + 6, y: icon.midY - size.height / 2)
        case "right": o = CGPoint(x: icon.minX - 6 - size.width, y: icon.midY - size.height / 2)
        default: o = CGPoint(x: icon.midX - size.width / 2, y: icon.maxY + 6)
        }
        o.x = min(max(o.x, area.minX), area.maxX - size.width)
        o.y = min(max(o.y, area.minY), area.maxY - size.height)
        return o
    }

    /// The panel plus the empty space up to the icon, so it doesn't close while moving from the icon to the panel.
    /// (only the "strip" as wide as the icon: neighboring icons must still be able to switch the preview)
    private static func keeps(_ p: NSPanel, _ m: CGPoint) -> Bool {
        if p.frame.insetBy(dx: -4, dy: -4).contains(m) { return true }
        guard let item = hoverItem else { return false }
        let icon = cocoaRect(item.frame), f = p.frame
        let bridge: CGRect
        switch dockOrientation {
        case "left": bridge = CGRect(x: icon.minX, y: icon.minY, width: f.minX - icon.minX, height: icon.height)
        case "right": bridge = CGRect(x: f.maxX, y: icon.minY, width: icon.maxX - f.maxX, height: icon.height)
        default: bridge = CGRect(x: icon.minX, y: icon.minY, width: icon.width, height: f.minY - icon.minY)
        }
        return bridge.insetBy(dx: 0, dy: -2).contains(m)
    }

    private static var dockOrientation: String {
        CFPreferencesCopyAppValue("orientation" as CFString, "com.apple.dock" as CFString) as? String ?? "bottom"
    }

    // MARK: Coordinates (AX: origin at top left of the main screen; Cocoa: at bottom left)

    private static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }
    private static func axPoint(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x, y: primaryHeight - p.y) }
    private static func cocoaPoint(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x, y: primaryHeight - p.y) }
    private static func cocoaRect(_ r: CGRect) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    private static func frame(_ el: AXUIElement) -> CGRect {
        var p = CGPoint.zero, s = CGSize.zero
        if let v = attr(el, kAXPositionAttribute) { AXValueGetValue(v as! AXValue, .cgPoint, &p) }
        if let v = attr(el, kAXSizeAttribute) { AXValueGetValue(v as! AXValue, .cgSize, &s) }
        return CGRect(origin: p, size: s)
    }

    private static func attr(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success ? v : nil
    }
}

private final class PreviewPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
