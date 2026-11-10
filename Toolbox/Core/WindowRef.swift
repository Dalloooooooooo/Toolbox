import Cocoa

/// A window to move or resize, in CoreGraphics coordinates (origin at the top left).
/// Other apps' windows go through Accessibility; Toolbox's own go through AppKit, because
/// querying Accessibility on yourself deadlocks: the thread that answers would be the one asking.
enum WindowRef {
    case other(AXUIElement)
    case own(NSWindow)

    // MARK: Finding the window

    /// The standard window under the point (no panels or full-screen windows).
    static func at(_ p: CGPoint) -> WindowRef? {
        if let mine = ownWindows.first(where: { ScreenGeo.cg($0.frame).contains(p) }) {
            // another app's window may be above ours: the on-screen order decides
            if let top = topWindowID(at: p), top != mine.cgWindowID {
                return AXWin.standardWindow(at: p).map(WindowRef.other)
            }
            return .own(mine)
        }
        return AXWin.standardWindow(at: p).map(WindowRef.other)
    }

    /// The focused window of the frontmost app.
    static func focused() -> WindowRef? {
        if NSApp.isActive, let key = NSApp.keyWindow, isOwnSnappable(key) { return .own(key) }
        return AXWin.focusedWindow().map(WindowRef.other)
    }

    /// The window of a switcher / Snap Assist item.
    static func of(_ info: WindowInfo) -> WindowRef? {
        if info.pid == ProcessInfo.processInfo.processIdentifier {
            return NSApp.window(withWindowNumber: Int(info.id)).map(WindowRef.own)
        }
        return WindowManager.axWindow(for: info).map(WindowRef.other)
    }

    private static var ownWindows: [NSWindow] { NSApp.windows.filter { $0.isVisible && isOwnSnappable($0) } }

    private static func isOwnSnappable(_ w: NSWindow) -> Bool {
        guard let id = w.cgWindowID else { return false }
        return WindowManager.isOwnAppWindow(id) && w.styleMask.contains(.resizable) &&
            !w.styleMask.contains(.fullScreen)
    }

    private static func topWindowID(at p: CGPoint) -> CGWindowID? {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        for w in list where (w[kCGWindowLayer as String] as? Int) == 0 {
            guard let bounds = w[kCGWindowBounds as String] as? NSDictionary,
                  let r = CGRect(dictionaryRepresentation: bounds), r.contains(p) else { continue }
            return w[kCGWindowNumber as String] as? CGWindowID
        }
        return nil
    }

    // MARK: Properties

    var id: CGWindowID? {
        switch self {
        case .other(let el): AXWin.id(el)
        case .own(let w): w.cgWindowID
        }
    }

    var frame: CGRect? {
        switch self {
        case .other(let el): AXWin.frame(el)
        case .own(let w): ScreenGeo.cg(w.frame)
        }
    }

    var isMinimized: Bool {
        switch self {
        case .other(let el): AXWin.isMinimized(el)
        case .own(let w): w.isMiniaturized
        }
    }

    /// Is the window's app hidden (⌘H)?
    var isAppHidden: Bool {
        switch self {
        case .other(let el): NSRunningApplication(processIdentifier: AXWin.pid(el))?.isHidden == true
        case .own: NSApp.isHidden
        }
    }

    // MARK: Actions

    func setFrame(_ r: CGRect) {
        switch self {
        case .other(let el): AXWin.setFrame(el, r)
        case .own(let w): w.setFrame(ScreenGeo.ns(r), display: true)
        }
    }

    func setSize(_ s: CGSize) {
        guard let f = frame else { return }
        setFrame(CGRect(origin: f.origin, size: s))
    }

    func setPosition(_ p: CGPoint) {
        guard let f = frame else { return }
        setFrame(CGRect(origin: p, size: f.size))
    }

    func minimize(_ on: Bool = true) {
        switch self {
        case .other(let el):
            AXUIElementSetAttributeValue(el, kAXMinimizedAttribute as CFString, on ? kCFBooleanTrue : kCFBooleanFalse)
        case .own(let w):
            on ? w.miniaturize(nil) : w.deminiaturize(nil)
        }
    }
}

extension NSWindow {
    /// The window number as a CGWindowID, if it has a valid one: windows not yet on screen
    /// have a number ≤ 0, and some internal macOS windows have a number that doesn't fit in 32 bits.
    var cgWindowID: CGWindowID? {
        guard let id = CGWindowID(exactly: windowNumber), id > 0 else { return nil }
        return id
    }
}
