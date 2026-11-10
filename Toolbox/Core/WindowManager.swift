import Cocoa
import ScreenCaptureKit
import ApplicationServices

// Private API (used by all switchers) to get the CGWindowID of an AX window
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ wid: UnsafeMutablePointer<CGWindowID>) -> AXError

enum WindowState { case normal, minimized, hidden, otherDesktop, fullscreen }

struct WindowInfo {
    let id: CGWindowID
    let pid: pid_t
    let appName: String
    let title: String
    let icon: NSImage?
    var state: WindowState = .normal
}

enum WindowManager {
    /// Apps in most-recently-used order, to sort minimized/hidden windows.
    private static var appOrder: [pid_t] = []

    static func startTracking() {
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.25) // a hung app doesn't hang us
        if let front = NSWorkspace.shared.frontmostApplication { appOrder = [front.processIdentifier] }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                          object: nil, queue: .main) { note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            appOrder.removeAll { $0 == app.processIdentifier }
            appOrder.insert(app.processIdentifier, at: 0)
        }
    }

    /// Visible windows and windows on other desktops (most recent first), then minimized windows and those of hidden apps.
    static func listWindows() -> [WindowInfo] {
        var result = visibleWindows()
        if Settings.showOtherDesktops {
            let seen = Set(result.map(\.id))
            result += otherDesktopWindows().filter { !seen.contains($0.id) }
            // "Windows-like" order: by most recently used app; ties keep the on-screen order
            let rank = { (pid: pid_t) in appOrder.firstIndex(of: pid) ?? Int.max }
            result = result.enumerated()
                .sorted { (rank($0.element.pid), $0.offset) < (rank($1.element.pid), $1.offset) }
                .map(\.element)
        }
        if Settings.showMinimized {
            let seen = Set(result.map(\.id))
            result += backgroundWindows().filter { !seen.contains($0.id) }
        }
        return result
    }

    /// Windows on other desktops, including full-screen apps.
    private static func otherDesktopWindows() -> [WindowInfo] {
        let others = Spaces.windowsInOtherSpaces()
        guard !others.isEmpty,
              let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else { return [] }
        var info: [CGWindowID: [String: Any]] = [:]
        for w in list { if let id = w[kCGWindowNumber as String] as? CGWindowID { info[id] = w } }
        let myPid = ProcessInfo.processInfo.processIdentifier
        var seen = Set<CGWindowID>()
        return others.compactMap { id, fullscreen in
            guard seen.insert(id).inserted, let w = info[id],
                  (w[kCGWindowLayer as String] as? Int) == 0,
                  (w[kCGWindowAlpha as String] as? Double ?? 1) > 0.01,
                  let pid = w[kCGWindowOwnerPID as String] as? pid_t, pid != myPid || isOwnAppWindow(id),
                  let bd = w[kCGWindowBounds as String] as? NSDictionary,
                  let r = CGRect(dictionaryRepresentation: bd), r.width >= 100, r.height >= 100, // no toolbars
                  let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular || pid == myPid
            else { return nil }
            let appName = app.localizedName ?? "App"
            let name = (w[kCGWindowName as String] as? String) ?? ""
            return WindowInfo(id: id, pid: pid, appName: appName, title: name.isEmpty ? appName : name,
                              icon: app.icon, state: fullscreen ? .fullscreen : .otherDesktop)
        }
    }

    /// All windows of a single app (for the Dock previews), in the same order as the switcher.
    static func windows(of pid: pid_t) -> [WindowInfo] {
        var result = visibleWindows().filter { $0.pid == pid }
        if Settings.showOtherDesktops {
            let seen = Set(result.map(\.id))
            result += otherDesktopWindows().filter { $0.pid == pid && !seen.contains($0.id) }
        }
        let seen = Set(result.map(\.id))
        result += backgroundWindows(only: pid).filter { !seen.contains($0.id) }
        return result
    }

    private static func backgroundWindows(only onlyPid: pid_t? = nil) -> [WindowInfo] {
        let myPid = ProcessInfo.processInfo.processIdentifier
        let rank = { (pid: pid_t) in appOrder.firstIndex(of: pid) ?? Int.max }
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != myPid }
            .filter { onlyPid == nil || $0.processIdentifier == onlyPid }
            .sorted { rank($0.processIdentifier) < rank($1.processIdentifier) }
        var result: [WindowInfo] = []
        for app in apps {
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value) == .success,
                  let wins = value as? [AXUIElement] else { continue }
            for win in wins {
                var wid: CGWindowID = 0
                guard _AXUIElementGetWindow(win, &wid) == .success, wid != 0 else { continue }
                // a window minimized to the Dock is always "real" (e.g. System Settings is an AXDialog);
                // for hidden apps, instead, we skip panels and popups
                let minimized = boolAttr(win, kAXMinimizedAttribute)
                let realSubroles = [kAXStandardWindowSubrole as String, kAXDialogSubrole as String]
                guard minimized || (app.isHidden && realSubroles.contains(stringAttr(win, kAXSubroleAttribute) ?? ""))
                else { continue }
                let appName = app.localizedName ?? "App"
                let title = stringAttr(win, kAXTitleAttribute) ?? ""
                result.append(WindowInfo(id: wid, pid: app.processIdentifier, appName: appName,
                                         title: title.isEmpty ? appName : title, icon: app.icon,
                                         state: minimized ? .minimized : .hidden))
            }
        }
        // the Toolbox settings window minimized to the Dock (no Accessibility needed: it's ours)
        for win in NSApp.windows where (onlyPid == nil || onlyPid == myPid) && win.isMiniaturized {
            guard let id = win.cgWindowID, isOwnAppWindow(id) else { continue }
            let me = NSRunningApplication.current
            result.append(WindowInfo(id: id, pid: myPid, appName: "Toolbox",
                                     title: win.title, icon: me.icon, state: .minimized))
        }
        return result
    }

    /// Toolbox's "real" windows (settings), not the switcher and notification panels.
    static func isOwnAppWindow(_ id: CGWindowID) -> Bool {
        guard let w = NSApp.window(withWindowNumber: Int(id)) else { return false }
        return w.styleMask.contains(.titled) && w.level == .normal && !(w is NSPanel)
    }

    private static func ownWindow(_ w: WindowInfo) -> NSWindow? {
        w.pid == ProcessInfo.processInfo.processIdentifier ? NSApp.window(withWindowNumber: Int(w.id)) : nil
    }

    private static func stringAttr(_ el: AXUIElement, _ attr: String) -> String? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success ? v as? String : nil
    }

    private static func boolAttr(_ el: AXUIElement, _ attr: String) -> Bool {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success && (v as? Bool ?? false)
    }

    static func visibleWindows() -> [WindowInfo] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else { return [] }
        let myPid = ProcessInfo.processInfo.processIdentifier
        var result: [WindowInfo] = []
        for w in list {
            guard let layer = w[kCGWindowLayer as String] as? Int, layer == 0,
                  let pid = w[kCGWindowOwnerPID as String] as? pid_t,
                  let id = w[kCGWindowNumber as String] as? CGWindowID,
                  pid != myPid || isOwnAppWindow(id),
                  let bd = w[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bd),
                  rect.width >= 80, rect.height >= 60 else { continue }
            if let alpha = w[kCGWindowAlpha as String] as? Double, alpha <= 0.01 { continue }
            guard let app = NSRunningApplication(processIdentifier: pid),
                  app.activationPolicy == .regular || pid == myPid else { continue }
            let appName = app.localizedName ?? (w[kCGWindowOwnerName as String] as? String) ?? "App"
            let name = (w[kCGWindowName as String] as? String) ?? ""
            result.append(WindowInfo(id: id, pid: pid, appName: appName,
                                     title: name.isEmpty ? appName : name, icon: app.icon))
        }
        return result
    }

    static func axWindow(for w: WindowInfo) -> AXUIElement? {
        let axApp = AXUIElementCreateApplication(w.pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value) == .success,
              let wins = value as? [AXUIElement] else { return nil }
        for win in wins {
            var wid: CGWindowID = 0
            if _AXUIElementGetWindow(win, &wid) == .success, wid == w.id { return win }
        }
        return nil
    }

    /// Brings the chosen window to the front.
    static func focus(_ w: WindowInfo) {
        if let own = ownWindow(w) { // Toolbox window: no Accessibility calls to ourselves
            if own.isMiniaturized { own.deminiaturize(nil) }
            NSApp.activate()
            own.makeKeyAndOrderFront(nil)
            return
        }
        if w.state == .otherDesktop || w.state == .fullscreen {
            Spaces.focus(windowID: w.id, pid: w.pid) // macOS switches to that desktop
            return
        }
        let axApp = AXUIElementCreateApplication(w.pid)
        let app = NSRunningApplication(processIdentifier: w.pid)
        if app?.isHidden == true { app?.unhide() }
        app?.activate(options: [])
        AXUIElementSetAttributeValue(axApp, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        if let win = axWindow(for: w) {
            if w.state == .minimized {
                AXUIElementSetAttributeValue(win, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            }
            AXUIElementSetAttributeValue(win, kAXMainAttribute as CFString, kCFBooleanTrue)
            AXUIElementPerformAction(win, kAXRaiseAction as CFString)
        }
    }

    /// Quits the whole app (like the X in Windows' Alt+Tab, but for the whole app).
    static func quitApp(pid: pid_t) {
        // Toolbox isn't quit from the switcher (the switcher is Toolbox): only the settings window is closed
        if pid == ProcessInfo.processInfo.processIdentifier {
            NSApp.windows.filter { $0.cgWindowID.map(isOwnAppWindow) ?? false }.forEach { $0.close() }
            return
        }
        NSRunningApplication(processIdentifier: pid)?.terminate()
    }

    /// Closes just the window by pressing its red button. Returns false if the window can't be
    /// reached (macOS only gives access to windows on the current desktop, minimized ones included).
    @discardableResult
    static func closeWindow(_ w: WindowInfo) -> Bool {
        if let own = ownWindow(w) { own.close(); return true }
        guard let win = axWindow(for: w) else { return false }
        var button: CFTypeRef?
        guard AXUIElementCopyAttributeValue(win, kAXCloseButtonAttribute as CFString, &button) == .success,
              let button else { return false }
        return AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString) == .success
    }

    /// Captures the previews in parallel; `handler` is called on the main thread for each one.
    static func capturePreviews(ids: [CGWindowID], maxSize: CGSize,
                                handler: @escaping (CGWindowID, NSImage) -> Void) {
        Task.detached {
            guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            else { return }
            let scale: CGFloat = 2
            await withTaskGroup(of: Void.self) { group in
                for id in ids {
                    guard let scw = content.windows.first(where: { $0.windowID == id }) else { continue }
                    group.addTask {
                        let f = scw.frame
                        let ratio = min(maxSize.width / f.width, maxSize.height / f.height, 1)
                        let cfg = SCStreamConfiguration()
                        cfg.width = max(1, Int(f.width * ratio * scale))
                        cfg.height = max(1, Int(f.height * ratio * scale))
                        cfg.showsCursor = false
                        cfg.ignoreShadowsSingleWindow = true
                        let filter = SCContentFilter(desktopIndependentWindow: scw)
                        guard let cg = try? await SCScreenshotManager.captureImage(contentFilter: filter,
                                                                                   configuration: cfg) else { return }
                        let img = NSImage(cgImage: cg, size: NSSize(width: CGFloat(cg.width) / scale,
                                                                    height: CGFloat(cg.height) / scale))
                        await MainActor.run { handler(id, img) }
                    }
                }
            }
        }
    }
}
