import Cocoa
import ScreenCaptureKit
import SwiftUI

/// The Win+Shift+S overlay: the screen is frozen (a capture of every display, taken the moment the
/// shortcut is pressed), dimmed, and a toolbar at the top offers the four Windows modes:
/// rectangle, freeform, window and full screen. Esc or the X cancels.
@MainActor
final class SnipOverlay {
    enum Mode: String, CaseIterable {
        case rectangle, freeform, window, fullScreen

        var icon: String {
            switch self {
            case .rectangle: "rectangle.dashed"
            case .freeform: "lasso"
            case .window: "macwindow"
            case .fullScreen: "display"
            }
        }
        var label: String {
            switch self {
            case .rectangle: String(localized: "Rectangle")
            case .freeform: String(localized: "Freeform")
            case .window: String(localized: "Window")
            case .fullScreen: String(localized: "Full screen")
            }
        }
        /// The last mode used, like Windows.
        static var saved: Mode {
            get { Mode(rawValue: UserDefaults.standard.string(forKey: Pref.screenSnipMode) ?? "") ?? .rectangle }
            set { UserDefaults.standard.set(newValue.rawValue, forKey: Pref.screenSnipMode) }
        }
    }

    /// One frozen display.
    struct Frozen {
        let screen: NSScreen
        let frame: CGRect      // CG coordinates (origin top left)
        let image: CGImage
        var scale: CGFloat { CGFloat(image.width) / frame.width }
    }

    /// Windows on screen at the moment of the freeze, front to back (CG coordinates).
    struct FrozenWindow { let frame: CGRect }

    private static var current: SnipOverlay?
    static var isOpen: Bool { current != nil }

    let displays: [Frozen]
    let windows: [FrozenWindow]
    private var panels: [SnipPanel] = []
    private let model = SnipToolbarModel()
    private let done: (CGImage?) -> Void

    /// Captures every display, then shows the overlay. `done` gets the snip (nil if cancelled);
    /// `failed` is called if the screen can't be captured (no Screen Recording permission).
    static func show(done: @escaping (CGImage?) -> Void, failed: @escaping () -> Void) {
        guard current == nil else { return }
        let windows = frozenWindows()
        Task {
            let displays = await capture()
            guard !displays.isEmpty else { failed(); return }
            let overlay = SnipOverlay(displays: displays, windows: windows, done: done)
            current = overlay
            overlay.open()
        }
    }

    private init(displays: [Frozen], windows: [FrozenWindow], done: @escaping (CGImage?) -> Void) {
        self.displays = displays
        self.windows = windows
        self.done = done
    }

    private func open() {
        model.mode = Mode.saved
        model.choose = { [weak self] in self?.choose($0) }
        model.cancel = { [weak self] in self?.finish(nil) }
        let toolbarScreen = ScreenGeo.screen(at: ScreenGeo.mouse) ?? displays[0].screen
        for d in displays {
            let panel = SnipPanel(frozen: d, overlay: self,
                                  toolbar: d.screen == toolbarScreen ? model : nil)
            panels.append(panel)
            panel.orderFrontRegardless()
        }
        let main = panels.first { $0.frozen.screen == toolbarScreen } ?? panels[0]
        main.makeKey()
        main.makeFirstResponder(main.snipView)
    }

    var mode: Mode { model.mode }

    private func choose(_ m: Mode) {
        Mode.saved = m
        if m == .fullScreen { finish(fullScreen()); return } // like Windows: captured right away
        model.mode = m
        panels.forEach { $0.snipView.reset() }
    }

    /// Called by the views when a snip is complete (or cancelled).
    func finish(_ image: CGImage?) {
        guard SnipOverlay.current === self else { return }
        SnipOverlay.current = nil
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()
        done(image)
    }

    // MARK: Results

    /// Part of a frozen display, `rect` in the display's own points (origin top left).
    func crop(_ d: Frozen, _ rect: CGRect) -> CGImage? {
        let r = rect.intersection(CGRect(origin: .zero, size: d.frame.size))
        guard r.width >= 1, r.height >= 1 else { return nil }
        let px = CGRect(x: r.minX * d.scale, y: r.minY * d.scale,
                        width: r.width * d.scale, height: r.height * d.scale).integral
        return d.image.cropping(to: px)
    }

    /// A freeform shape: its bounding box, transparent outside the shape. `path` in display points.
    func crop(_ d: Frozen, path: CGPath) -> CGImage? {
        let box = path.boundingBox.intersection(CGRect(origin: .zero, size: d.frame.size)).integral
        guard box.width >= 2, box.height >= 2, let part = crop(d, box) else { return nil }
        let w = part.width, h = part.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // points (y down, from the box) → pixels (y up)
        var t = CGAffineTransform(translationX: 0, y: CGFloat(h)).scaledBy(x: d.scale, y: -d.scale)
            .translatedBy(x: -box.minX, y: -box.minY)
        guard let shape = path.copy(using: &t) else { return nil }
        ctx.addPath(shape)
        ctx.clip()
        ctx.draw(part, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    /// Every display in one image, placed as they are arranged (like Windows' full screen snip).
    private func fullScreen() -> CGImage? {
        if displays.count == 1 { return displays[0].image }
        let union = displays.map(\.frame).reduce(CGRect.null) { $0.union($1) }
        let scale = displays.map(\.scale).max() ?? 2
        guard let ctx = CGContext(data: nil, width: Int(union.width * scale), height: Int(union.height * scale),
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        for d in displays {
            let r = CGRect(x: (d.frame.minX - union.minX) * scale, y: (union.maxY - d.frame.maxY) * scale,
                           width: d.frame.width * scale, height: d.frame.height * scale)
            ctx.draw(d.image, in: r)
        }
        return ctx.makeImage()
    }

    // MARK: Freezing

    private static func capture() async -> [Frozen] {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        else { return [] }
        var result: [Frozen] = []
        for screen in NSScreen.screens {
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
                  let display = content.displays.first(where: { $0.displayID == id }) else { continue }
            let cfg = SCStreamConfiguration()
            cfg.width = Int(screen.frame.width * screen.backingScaleFactor)
            cfg.height = Int(screen.frame.height * screen.backingScaleFactor)
            cfg.showsCursor = false
            let filter = SCContentFilter(display: display, excludingWindows: [])
            guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
            else { continue }
            result.append(Frozen(screen: screen, frame: ScreenGeo.cg(screen.frame), image: image))
        }
        return result
    }

    private static func frozenWindows() -> [FrozenWindow] {
        let me = ProcessInfo.processInfo.processIdentifier
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        return list.compactMap { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowOwnerPID as String] as? pid_t) != me,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let b = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: b),
                  frame.width > 40, frame.height > 40 else { return nil }
            return FrozenWindow(frame: frame)
        }
    }
}

// MARK: - Panel and view

/// A borderless panel above everything (menu bar and Dock included) that shows one frozen display.
final class SnipPanel: NSPanel {
    let frozen: SnipOverlay.Frozen
    let snipView: SnipView

    init(frozen: SnipOverlay.Frozen, overlay: SnipOverlay, toolbar: SnipToolbarModel?) {
        self.frozen = frozen
        snipView = SnipView(frozen: frozen, overlay: overlay)
        super.init(contentRect: frozen.screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = true
        hasShadow = false
        backgroundColor = .black
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        setFrame(frozen.screen.frame, display: false)
        contentView = snipView
        if let toolbar {
            let host = ArrowCursorHostingView(rootView: SnipToolbar(model: toolbar))
            host.translatesAutoresizingMaskIntoConstraints = false
            snipView.addSubview(host)
            NSLayoutConstraint.activate([
                host.centerXAnchor.constraint(equalTo: snipView.centerXAnchor),
                host.topAnchor.constraint(equalTo: snipView.topAnchor, constant: 4),
            ])
            snipView.toolbar = host
        }
    }

    override var canBecomeKey: Bool { true }
}

private final class ArrowCursorHostingView<V: View>: NSHostingView<V> {
    override func resetCursorRects() { addCursorRect(bounds, cursor: .arrow) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class SnipView: NSView {
    let frozen: SnipOverlay.Frozen
    unowned let overlay: SnipOverlay
    weak var toolbar: NSView?
    private let image: NSImage

    private var start: CGPoint?
    private var selection: CGRect?        // rectangle mode
    private var lasso: CGMutablePath?     // freeform mode
    private var hovered: CGRect?          // window mode, in view points

    init(frozen: SnipOverlay.Frozen, overlay: SnipOverlay) {
        self.frozen = frozen
        self.overlay = overlay
        image = NSImage(cgImage: frozen.image, size: frozen.frame.size)
        super.init(frame: CGRect(origin: .zero, size: frozen.frame.size))
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true } // y down, like CG coordinates
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    func reset() {
        start = nil; selection = nil; lasso = nil; hovered = nil
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { overlay.finish(nil) } // Esc
    }

    private func point(_ e: NSEvent) -> CGPoint { convert(e.locationInWindow, from: nil) }

    override func mouseMoved(with event: NSEvent) {
        guard overlay.mode == .window else { return }
        let global = CGPoint(x: point(event).x + frozen.frame.minX, y: point(event).y + frozen.frame.minY)
        let w = overlay.windows.first { $0.frame.contains(global) }?.frame
        let local = w.map { $0.offsetBy(dx: -frozen.frame.minX, dy: -frozen.frame.minY) }
        if local != hovered { hovered = local; needsDisplay = true }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        let p = point(event)
        switch overlay.mode {
        case .rectangle: start = p; selection = CGRect(origin: p, size: .zero)
        case .freeform: lasso = CGMutablePath(); lasso?.move(to: p)
        case .window:
            mouseMoved(with: event)
            if let hovered { overlay.finish(overlay.crop(frozen, hovered)) }
        case .fullScreen: break
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let p = clamp(point(event))
        switch overlay.mode {
        case .rectangle:
            guard let start else { return }
            selection = CGRect(x: min(start.x, p.x), y: min(start.y, p.y),
                               width: abs(p.x - start.x), height: abs(p.y - start.y))
        case .freeform: lasso?.addLine(to: p)
        default: return
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        mouseDragged(with: event) // the last position counts
        switch overlay.mode {
        case .rectangle:
            if let s = selection, s.width >= 2, s.height >= 2 { overlay.finish(overlay.crop(frozen, s)); return }
        case .freeform:
            if let l = lasso, l.boundingBox.width >= 2, l.boundingBox.height >= 2 {
                l.closeSubpath()
                overlay.finish(overlay.crop(frozen, path: l)); return
            }
        default: return
        }
        reset() // a click without dragging: nothing, like Windows
    }

    private func clamp(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max(p.x, 0), bounds.width), y: min(max(p.y, 0), bounds.height))
    }

    override func draw(_ dirtyRect: NSRect) {
        image.draw(in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
        NSColor.black.withAlphaComponent(0.4).setFill()
        bounds.fill(using: .sourceOver)

        let lit: NSBezierPath?
        switch overlay.mode {
        case .rectangle: lit = selection.map { NSBezierPath(rect: $0) }
        case .window: lit = hovered.map { NSBezierPath(rect: $0) }
        case .freeform: lit = lasso.map { NSBezierPath(cgPath: $0) }
        case .fullScreen: lit = nil
        }
        guard let lit, !lit.isEmpty else { return }
        NSGraphicsContext.saveGraphicsState()
        lit.addClip()
        image.draw(in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
        NSGraphicsContext.restoreGraphicsState()
        NSColor.white.withAlphaComponent(0.9).setStroke()
        lit.lineWidth = 1
        lit.stroke()
    }
}

private extension NSBezierPath {
    convenience init(cgPath: CGPath) {
        self.init()
        cgPath.applyWithBlock { el in
            let p = el.pointee.points
            switch el.pointee.type {
            case .moveToPoint: move(to: p[0])
            case .addLineToPoint: line(to: p[0])
            case .addQuadCurveToPoint: curve(to: p[1], controlPoint1: p[0], controlPoint2: p[0])
            case .addCurveToPoint: curve(to: p[2], controlPoint1: p[0], controlPoint2: p[1])
            case .closeSubpath: close()
            @unknown default: break
            }
        }
    }
}

// MARK: - Toolbar

@MainActor
final class SnipToolbarModel: ObservableObject {
    @Published var mode: SnipOverlay.Mode = .rectangle
    var choose: (SnipOverlay.Mode) -> Void = { _ in }
    var cancel: () -> Void = {}
}

private struct SnipToolbar: View {
    @ObservedObject var model: SnipToolbarModel

    var body: some View {
        HStack(spacing: 4) {
            ForEach(SnipOverlay.Mode.allCases, id: \.self) { m in
                button(m.icon, help: m.label, selected: model.mode == m) { model.choose(m) }
            }
            Divider().frame(height: 20).padding(.horizontal, 4)
            button("xmark", help: String(localized: "Close"), selected: false) { model.cancel() }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .windowBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(0.12)))
        .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
        .padding(14) // room for the shadow
    }

    private func button(_ icon: String, help: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 34, height: 30)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Color.accentColor : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
