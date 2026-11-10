import Cocoa
import ApplicationServices

/// Like on Windows: once an app's last window is closed, the app actually quits.
/// Kicks in only after a user action (click or ⌘W) on the frontmost app: it first counts the
/// windows, checks again shortly after, and if they went from at least one to zero it asks the app to quit
/// (like ⌘Q, so the user is still asked about unsaved documents).
enum AutoQuit {
    private static var snapshot: (pid: pid_t, count: Int)?
    /// Finder never quits on macOS; the user picks the others (exclusion list)
    private static var neverQuit: Set<String> { Set(["com.apple.finder"] + Settings.quitExclusions) }

    /// Call at the start of an action that might close a window (mouseDown, ⌘W).
    static func actionStarted(sync: Bool = false) {
        guard Settings.quitOnLastWindow, let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              !neverQuit.contains(app.bundleIdentifier ?? "") else { snapshot = nil; return }
        let pid = app.processIdentifier
        // for the mouse, count asynchronously (doesn't slow down the click, and still happens before release);
        // for ⌘W, count right away, because the window already closes on key down
        if sync { snapshot = (pid, windowCount(pid)) } else { DispatchQueue.main.async { snapshot = (pid, windowCount(pid)) } }
    }

    /// Call at the end of the action (mouseUp, or right after ⌘W).
    static func actionEnded() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            guard let snap = snapshot, snap.count > 0 else { return }
            snapshot = nil
            quitIfNoWindows(snap.pid)
        }
    }

    /// After the switcher closed a window: if it was the last one, the app quits.
    static func windowClosed(pid: pid_t) {
        guard Settings.quitOnLastWindow, pid != ProcessInfo.processInfo.processIdentifier, // Toolbox stays in the menu bar
              !neverQuit.contains(NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? "") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { quitIfNoWindows(pid) }
    }

    // MARK: X on the last window = ⌘Q

    private static var swallowUp = false

    /// Does "close the last window = quit" apply to this app?
    static func applies(to pid: pid_t) -> Bool {
        Settings.quitOnLastWindow && pid != ProcessInfo.processInfo.processIdentifier
            && !neverQuit.contains(NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? "")
    }

    /// Is this the app's only remaining window (also counting minimized ones and those on other desktops)?
    static func isLastWindow(_ pid: pid_t) -> Bool {
        applies(to: pid) && windowCount(pid) <= 1 && !hasWindowsInOtherSpaces(pid)
    }

    /// Click on the red button of the last window: instead of closing it, we quit the app (like ⌘Q).
    /// This way the app saves its session with the window still open: Firefox, Safari, Chrome… reopen their tabs.
    /// Returns true if the click should be swallowed.
    static func closeButtonDown(at point: CGPoint) -> Bool {
        guard Settings.quitOnLastWindow, let button = element(at: point),
              attr(button, kAXSubroleAttribute) as? String == kAXCloseButtonSubrole as String else { return false }
        // only real windows (not panels like the color picker)
        if let win = attr(button, kAXWindowAttribute) {
            let sub = attr(win as! AXUIElement, kAXSubroleAttribute) as? String ?? ""
            guard [kAXStandardWindowSubrole as String, kAXDialogSubrole as String].contains(sub) else { return false }
        }
        var pid: pid_t = 0
        AXUIElementGetPid(button, &pid)
        guard pid > 0, isLastWindow(pid), let app = NSRunningApplication(processIdentifier: pid) else { return false }
        swallowUp = true
        snapshot = nil
        app.terminate()
        return true
    }

    /// The release of a swallowed click must be swallowed too.
    static func consumeMouseUp() -> Bool {
        defer { swallowUp = false }
        return swallowUp
    }

    private static func element(at p: CGPoint) -> AXUIElement? {
        var el: AXUIElement?
        if AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(p.x), Float(p.y), &el) == .success, let el {
            return el
        }
        // sometimes the system-wide request doesn't respond: ask the frontmost app
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              AXUIElementCopyElementAtPosition(AXUIElementCreateApplication(pid), Float(p.x), Float(p.y), &el) == .success
        else { return nil }
        return el
    }

    private static func attr(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success ? v : nil
    }

    private static func quitIfNoWindows(_ pid: pid_t) {
        guard windowCount(pid) == 0, !hasWindowsInOtherSpaces(pid),
              let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else { return }
        app.terminate()
    }

    private static func windowCount(_ pid: pid_t) -> Int {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXWindowsAttribute as CFString, &v)
                == .success, let wins = v as? [AXUIElement] else { return 0 }
        let real = [kAXStandardWindowSubrole as String, kAXDialogSubrole as String]
        return wins.filter { w in
            var s: CFTypeRef?
            AXUIElementCopyAttributeValue(w, kAXSubroleAttribute as CFString, &s)
            return real.contains(s as? String ?? "")
        }.count
    }

    /// Accessibility only sees windows on the current desktop: to be safe, we check that the
    /// app has no titled windows on other desktops (Spaces).
    private static func hasWindowsInOtherSpaces(_ pid: pid_t) -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return false }
        return list.contains { w in
            guard (w[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  (w[kCGWindowLayer as String] as? Int) == 0,
                  (w[kCGWindowIsOnscreen as String] as? Bool) != true,
                  ((w[kCGWindowName as String] as? String) ?? "").isEmpty == false,
                  (w[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let bd = w[kCGWindowBounds as String] as? NSDictionary,
                  let r = CGRect(dictionaryRepresentation: bd) else { return false }
            return r.width >= 100 && r.height >= 100
        }
    }
}
