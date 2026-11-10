import Cocoa

private let pad: CGFloat = 20, spacing: CGFloat = 10

/// Tile metrics, derived from the preview width chosen in the settings.
struct TileMetrics {
    let preview: CGSize
    var itemW: CGFloat { preview.width + 20 }
    var itemH: CGFloat { preview.height + 50 }

    static var current: TileMetrics {
        let w = Settings.previewWidth
        return TileMetrics(preview: CGSize(width: w, height: (w * 0.64).rounded()))
    }
}

final class FlippedView: NSView { override var isFlipped: Bool { true } }

/// Panel with the grid of previews, in the style of Alt+Tab on Windows.
final class SwitcherController {
    private let panel: NSPanel
    private let grid = FlippedView()
    private var items: [WindowInfo] = []
    private var views: [ItemView] = []
    private var selected = 0
    private var columns = 1
    private var generation = 0
    private var metrics = TileMetrics.current

    var isVisible: Bool { panel.isVisible }

    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]

        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 18
        blur.layer?.masksToBounds = true
        blur.autoresizingMask = [.width, .height]
        grid.autoresizingMask = [.width, .height]
        blur.addSubview(grid)
        panel.contentView = blur
    }

    func show(reverse: Bool) {
        items = WindowManager.listWindows()
        guard !items.isEmpty else { NSSound.beep(); return }
        PreviewStore.prune(keeping: Set(items.map(\.id)))
        generation += 1
        selected = items.count > 1 ? (reverse ? items.count - 1 : 1) : 0
        metrics = .current
        rebuild()
        panel.orderFrontRegardless()

        let gen = generation
        WindowManager.capturePreviews(ids: items.filter { $0.state == .normal }.map(\.id), maxSize: metrics.preview) { [weak self] id, img in
            guard let self else { return }
            PreviewStore.set(img, for: id)
            if gen == self.generation { self.views.first { $0.info.id == id }?.setPreview(img) }
        }
    }

    func move(_ delta: Int) {
        guard !items.isEmpty else { return }
        select((selected + delta + items.count) % items.count)
    }

    func moveRow(_ delta: Int) {
        let target = selected + delta * columns
        if items.indices.contains(target) { select(target) }
    }

    func select(_ index: Int) {
        guard views.indices.contains(index) else { return }
        selected = index
        for (i, v) in views.enumerated() { v.isSelected = (i == index) }
    }

    func commit(_ index: Int? = nil) {
        guard isVisible else { return }
        let i = index ?? selected
        let target = items.indices.contains(i) ? items[i] : nil
        hide()
        if let target { WindowManager.focus(target) }
    }

    func cancel() { hide() }

    func quitSelected() { quit(at: selected) }

    /// The X: quits the app and removes it from the list; the switcher stays open.
    func quit(at index: Int) {
        guard items.indices.contains(index) else { return }
        let pid = items[index].pid
        WindowManager.quitApp(pid: pid)
        remove { $0.pid == pid }
    }

    func closeSelectedWindow() { closeWindow(at: selected) }

    /// The X: closes only that window (as on Windows); the switcher stays open.
    func closeTapped(at index: Int) {
        if Settings.closeButtonQuitsApp { quit(at: index) } else { closeWindow(at: index) }
    }

    func closeWindow(at index: Int) {
        guard items.indices.contains(index) else { return }
        let w = items[index]
        // last window of the app: quit as with ⌘Q, so it saves its session (e.g. Firefox tabs)
        if AutoQuit.isLastWindow(w.pid) { quit(at: index); return }
        if WindowManager.closeWindow(w) {
            remove { $0.id == w.id }
            AutoQuit.windowClosed(pid: w.pid) // if it was the last window, the app quits
        } else if items.filter({ $0.pid == w.pid }).count == 1 {
            quit(at: index) // window on another desktop and the app's only one: closing = quitting
        } else {
            // window on another desktop: macOS only makes it accessible there, so we go there and close it
            hide()
            WindowManager.focus(w)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { WindowManager.closeWindow(w) }
        }
    }

    private func remove(where match: (WindowInfo) -> Bool) {
        let before = items[..<min(selected, items.count)].filter { !match($0) }.count
        items.removeAll(where: match)
        if items.isEmpty { hide(); return }
        selected = min(before, items.count - 1)
        rebuild()
    }

    private func hide() {
        generation += 1
        panel.orderOut(nil)
        views.forEach { $0.removeFromSuperview() }
        views = []
    }

    private func rebuild() {
        views.forEach { $0.removeFromSuperview() }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main!
        let area = screen.visibleFrame

        let itemW = metrics.itemW, itemH = metrics.itemH
        let fit = Int((area.width * 0.9 - 2 * pad + spacing) / (itemW + spacing))
        columns = max(1, min(items.count, fit))
        let rows = (items.count + columns - 1) / columns
        let size = NSSize(width: CGFloat(columns) * (itemW + spacing) - spacing + 2 * pad,
                          height: CGFloat(rows) * (itemH + spacing) - spacing + 2 * pad)
        panel.setFrame(NSRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2,
                              width: size.width, height: size.height), display: false)

        views = items.enumerated().map { i, info in
            let v = ItemView(info: info, index: i, metrics: metrics, controller: self)
            v.frame = NSRect(x: pad + CGFloat(i % columns) * (itemW + spacing),
                             y: pad + CGFloat(i / columns) * (itemH + spacing),
                             width: itemW, height: itemH)
            if let img = PreviewStore.image(for: info.id) { v.setPreview(img) }
            grid.addSubview(v)
            return v
        }
        select(selected)
    }
}

final class ItemView: NSView {
    let info: WindowInfo
    private let index: Int
    private weak var controller: SwitcherController?
    private let preview = NSImageView()
    private let closeButton = NSButton()
    private var hovering = false { didSet { updateLook() } }
    var isSelected = false { didSet { updateLook() } }

    override var isFlipped: Bool { true }

    init(info: WindowInfo, index: Int, metrics: TileMetrics, controller: SwitcherController) {
        self.info = info
        self.index = index
        self.controller = controller
        let itemW = metrics.itemW, previewSize = metrics.preview
        // title on top: name row at the top and preview below; otherwise the other way around
        let titleOnTop = Settings.titleOnTop
        let previewY: CGFloat = titleOnTop ? 40 : 10
        let titleY: CGFloat = titleOnTop ? 10 : previewSize.height + 18
        super.init(frame: NSRect(x: 0, y: 0, width: itemW, height: metrics.itemH))
        wantsLayer = true
        layer?.cornerRadius = 12

        // until the preview arrives, show the large icon
        preview.frame = NSRect(x: 10, y: previewY, width: previewSize.width, height: previewSize.height)
        preview.imageScaling = .scaleProportionallyUpOrDown
        preview.image = info.icon
        preview.wantsLayer = true
        preview.layer?.cornerRadius = 6
        preview.layer?.masksToBounds = true
        addSubview(preview)

        let icon = NSImageView(frame: NSRect(x: 10, y: titleY, width: 22, height: 22))
        icon.image = info.icon
        addSubview(icon)

        let title = NSTextField(labelWithString: info.title)
        title.frame = NSRect(x: 38, y: titleY + 2, width: itemW - 48, height: 18)
        title.font = .systemFont(ofSize: 12, weight: .medium)
        title.textColor = .labelColor
        title.lineBreakMode = .byTruncatingTail
        title.toolTip = "\(info.appName) — \(info.title)"
        addSubview(title)

        if let badgeInfo = Self.badge(for: info.state) {
            let badge = NSImageView(frame: NSRect(x: 16, y: previewY + previewSize.height - 30, width: 24, height: 24))
            badge.image = NSImage(systemSymbolName: badgeInfo.symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 18, weight: .bold))
            badge.contentTintColor = badgeInfo.color
            badge.toolTip = badgeInfo.tip
            if info.state == .minimized || info.state == .hidden { preview.alphaValue = 0.75 }
            addSubview(badge)
        }

        let xImage = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: String(localized: "Close"))?
            .withSymbolConfiguration(.init(pointSize: 20, weight: .bold))
        closeButton.image = xImage
        closeButton.isBordered = false
        closeButton.contentTintColor = .systemRed
        closeButton.frame = NSRect(x: itemW - 36, y: previewY - 6, width: 30, height: 30)
        closeButton.toolTip = Settings.closeButtonQuitsApp ? String(localized: "Quit \(info.appName)") : String(localized: "Close this window")
        closeButton.target = self
        closeButton.action = #selector(closeTapped)
        addSubview(closeButton)

        updateLook()
    }

    required init?(coder: NSCoder) { fatalError() }

    private static func badge(for state: WindowState) -> (symbol: String, color: NSColor, tip: String)? {
        switch state {
        case .normal: nil
        case .minimized: ("minus.circle.fill", .systemYellow, String(localized: "Minimized to the Dock"))
        case .hidden: ("eye.slash.circle.fill", .systemGray, String(localized: "App hidden"))
        case .fullscreen: ("arrow.up.left.and.arrow.down.right.circle.fill", .systemGreen, String(localized: "Full screen"))
        case .otherDesktop: ("square.stack.3d.up.fill", .systemBlue, String(localized: "On another desktop"))
        }
    }

    func setPreview(_ img: NSImage) { preview.image = img }

    @objc private func closeTapped() { controller?.closeTapped(at: index) }

    private func updateLook() {
        layer?.backgroundColor = isSelected ? NSColor.white.withAlphaComponent(0.22).cgColor
                                            : (hovering ? NSColor.white.withAlphaComponent(0.08).cgColor : nil)
        layer?.borderWidth = isSelected ? 2 : 0
        layer?.borderColor = NSColor.controlAccentColor.cgColor
        closeButton.isHidden = !(isSelected || hovering)
    }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways],
                                       owner: self))
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) { hovering = true; controller?.select(index) }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseUp(with event: NSEvent) { controller?.commit(index) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
