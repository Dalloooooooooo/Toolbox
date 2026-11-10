import Cocoa

enum AXWin {
    static func attr(_ el: AXUIElement, _ name: String) -> AnyObject? {
        var v: AnyObject?
        return AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success ? v : nil
    }
    static func frame(_ el: AXUIElement) -> CGRect? {
        guard let p = attr(el, kAXPositionAttribute), let s = attr(el, kAXSizeAttribute) else { return nil }
        var pt = CGPoint.zero, sz = CGSize.zero
        AXValueGetValue(p as! AXValue, .cgPoint, &pt)
        AXValueGetValue(s as! AXValue, .cgSize, &sz)
        return CGRect(origin: pt, size: sz)
    }
    static func setPosition(_ el: AXUIElement, _ p: CGPoint) {
        var pt = p
        if let v = AXValueCreate(.cgPoint, &pt) { AXUIElementSetAttributeValue(el, kAXPositionAttribute as CFString, v) }
    }
    static func setSize(_ el: AXUIElement, _ s: CGSize) {
        var sz = s
        if let v = AXValueCreate(.cgSize, &sz) { AXUIElementSetAttributeValue(el, kAXSizeAttribute as CFString, v) }
    }
    /// Position, size and position again: some apps adjust the position when the size changes.
    static func setFrame(_ el: AXUIElement, _ r: CGRect) {
        setPosition(el, r.origin)
        setSize(el, r.size)
        setPosition(el, r.origin)
    }
    static func id(_ el: AXUIElement) -> CGWindowID? {
        var wid: CGWindowID = 0
        return _AXUIElementGetWindow(el, &wid) == .success && wid != 0 ? wid : nil
    }
    static func pid(_ el: AXUIElement) -> pid_t {
        var p: pid_t = 0
        AXUIElementGetPid(el, &p)
        return p
    }
    static func isMinimized(_ el: AXUIElement) -> Bool { attr(el, kAXMinimizedAttribute) as? Bool == true }

    private static func isStandard(_ win: AXUIElement) -> Bool {
        attr(win, kAXSubroleAttribute) as? String == kAXStandardWindowSubrole &&
        attr(win, "AXFullScreen") as? Bool != true &&
        pid(win) != ProcessInfo.processInfo.processIdentifier
    }
    /// The standard window under the point (no panels, no full-screen windows, not Toolbox).
    static func standardWindow(at p: CGPoint) -> AXUIElement? {
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(p.x), Float(p.y), &hit) == .success,
              let hit else { return nil }
        var win: AXUIElement?
        if attr(hit, kAXRoleAttribute) as? String == kAXWindowRole { win = hit }
        else if let w = attr(hit, kAXWindowAttribute) { win = (w as! AXUIElement) }
        guard let win, isStandard(win) else { return nil }
        return win
    }
    /// The focused window of the frontmost app.
    static func focusedWindow() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        guard let w = attr(ax, kAXFocusedWindowAttribute) else { return nil }
        let win = w as! AXUIElement
        return isStandard(win) ? win : nil
    }
}
