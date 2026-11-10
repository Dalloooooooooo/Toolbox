import Cocoa
import ApplicationServices

enum DockMinimizeScope: String, CaseIterable, Identifiable {
    case allWindows, frontWindow
    var id: String { rawValue }
    var label: String {
        switch self {
        case .allWindows: String(localized: "All windows of the app")
        case .frontWindow: String(localized: "Only the frontmost window")
        }
    }
}

/// Clicking the Dock icon of the app that is already frontmost minimizes it, like the Windows taskbar.
enum DockClick {
    private static var swallowingUp = false

    /// Called by the event tap. Returns true if the click must be swallowed (the Dock must not see it,
    /// otherwise it would immediately reopen the window that was just minimized).
    static func handle(_ type: CGEventType, at point: CGPoint) -> Bool {
        if type == .leftMouseUp {
            defer { swallowingUp = false }
            return swallowingUp
        }
        guard type == .leftMouseDown, Settings.dockMinimize,
              let front = NSWorkspace.shared.frontmostApplication,
              let dockPid = dockPid(),
              let clicked = appURL(dockPid: dockPid, at: point),
              sameApp(clicked, front) else { return false }

        if front.processIdentifier == ProcessInfo.processInfo.processIdentifier { // Toolbox itself: no accessibility calls to ourselves
            let mine = NSApp.windows.filter { $0.isVisible && ($0.cgWindowID.map(WindowManager.isOwnAppWindow) ?? false) }
            guard !mine.isEmpty else { return false }
            mine.forEach { $0.miniaturize(nil) }
            swallowingUp = true
            return true
        }

        let windows = visibleWindows(of: front.processIdentifier)
        guard !windows.isEmpty else { return false } // no open windows: let the Dock handle it
        let targets = Settings.dockMinimizeScope == .frontWindow ? [focusedWindow(front.processIdentifier) ?? windows[0]]
                                                                  : windows
        targets.forEach(minimize)
        swallowingUp = true
        return true
    }

    /// Compare by bundle id: the Dock sometimes uses a different path (e.g. Safari lives in a "cryptex")
    private static func sameApp(_ url: URL, _ app: NSRunningApplication) -> Bool {
        if let id = Bundle(url: url)?.bundleIdentifier, let frontId = app.bundleIdentifier { return id == frontId }
        return url.resolvingSymlinksInPath().standardizedFileURL == app.bundleURL?.resolvingSymlinksInPath().standardizedFileURL
    }

    private static func dockPid() -> pid_t? {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier
    }

    private static func appURL(dockPid: pid_t, at point: CGPoint) -> URL? {
        var el: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateApplication(dockPid),
                                               Float(point.x), Float(point.y), &el) == .success, let el,
              attr(el, kAXSubroleAttribute) as? String == "AXApplicationDockItem" else { return nil }
        if let url = attr(el, kAXURLAttribute) as? URL { return url }
        if let s = attr(el, kAXURLAttribute) as? String { return URL(string: s) }
        return nil
    }

    private static func visibleWindows(of pid: pid_t) -> [AXUIElement] {
        guard let wins = attr(AXUIElementCreateApplication(pid), kAXWindowsAttribute) as? [AXUIElement] else { return [] }
        return wins.filter {
            attr($0, kAXMinimizedAttribute) as? Bool != true
                && [kAXStandardWindowSubrole as String, kAXDialogSubrole as String]
                    .contains(attr($0, kAXSubroleAttribute) as? String ?? "")
        }
    }

    private static func focusedWindow(_ pid: pid_t) -> AXUIElement? {
        guard let v = attr(AXUIElementCreateApplication(pid), kAXFocusedWindowAttribute) else { return nil }
        return (v as! AXUIElement)
    }

    /// Full-screen windows can't be minimized: exit full screen first.
    private static func minimize(_ win: AXUIElement) {
        if attr(win, "AXFullScreen") as? Bool == true {
            AXUIElementSetAttributeValue(win, "AXFullScreen" as CFString, kCFBooleanFalse)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                AXUIElementSetAttributeValue(win, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
            }
        } else {
            AXUIElementSetAttributeValue(win, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
        }
    }

    private static func attr(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success ? v : nil
    }
}
