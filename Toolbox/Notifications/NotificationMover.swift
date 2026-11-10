import Cocoa
import ApplicationServices

/// macOS notifications, in two ways:
/// - "macOS" style: the system banner is moved to the top center and slides down;
/// - "Toolbox" style: the system banner is hidden (moved off-screen) and we show our own
///   notification in its place (see NotificationUI.swift); clicking it "clicks" the real one.
/// macOS draws banners inside a transparent, screen-sized window that only exists
/// while at least one banner is visible.
enum NotificationMover {
    private static var observer: AXObserver?
    private static var observedPid: pid_t = 0
    private static let bannerSubrole = "AXNotificationCenterBanner"
    /// distance of the banner from the right edge when macOS puts it in its normal position
    private static let systemRightMargin: CGFloat = 16
    /// outside every screen: there the system banner keeps existing (and responding to clicks via
    /// accessibility), but it isn't visible
    private static let hiddenPosition = CGPoint(x: 30000, y: 0)

    /// Banner window we are tracking in "Toolbox" style, and banners already shown.
    private static var trackedWindow: AXUIElement?
    private static var trackTimer: Timer?
    private static var shownBanners: Set<String> = []
    /// A banner we can't read: let the macOS one show (better than losing it).
    private static var systemFallback = false
    /// Last click on the right side of the menu bar (date and time → opens Notification Center).
    static var menuBarClickAt = Date.distantPast

    static func start() {
        attach()
        // the Notification Center process can restart: check again every now and then
        let t = Timer(timeInterval: 5, repeats: true) { _ in attach() }
        RunLoop.main.add(t, forMode: .common)
    }

    private static func attach() {
        guard let nc = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.notificationcenterui").first,
              nc.processIdentifier != observedPid else { return }
        if let old = observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(old), .defaultMode)
        }
        let pid = nc.processIdentifier
        var obs: AXObserver?
        guard AXObserverCreate(pid, { _, element, _, _ in
            MainActor.assumeIsolated { NotificationMover.windowAppeared(element) }
        }, &obs) == .success, let obs else { return }
        AXObserverAddNotification(obs, AXUIElementCreateApplication(pid), kAXWindowCreatedNotification as CFString, nil)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        observer = obs
        observedPid = pid
    }

    fileprivate static func windowAppeared(_ window: AXUIElement, attempt: Int = 0) {
        // the banner content arrives a moment after the window
        guard let banner = findBanners(window).first else {
            if attempt < 10 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { windowAppeared(window, attempt: attempt + 1) }
            } else {
                NotificationLog.add(app: "?", outcome: "notification window without a recognizable banner (left to macOS)")
            }
            return
        }
        // Notification Center opened by the user is not a new notification: leave it to macOS
        if let reason = panelReason(window) {
            NotificationLog.add(app: "-", outcome: "Notification Center opened (\(reason)): left to macOS")
            NotificationLog.structure(window, label: "panel")
            return
        }
        NotificationLog.structure(window, label: "banner")
        switch Settings.notificationStyle {
        case .toolbox: startTracking(window)
        case .system: centerSystemBanner(window, banner)
        }
    }

    // MARK: "macOS" style: system banner centered

    private static func centerSystemBanner(_ window: AXUIElement, _ banner: AXUIElement) {
        guard Settings.centerNotifications else { return }
        let win = frame(window), b = frame(banner)
        // final banner position (while it slides in from the right, its x isn't final yet)
        let finalBannerX = win.maxX - systemRightMargin - b.width
        let x = win.minX + (win.midX - b.width / 2) - finalBannerX

        guard Settings.notificationDropAnimation else { setPosition(window, CGPoint(x: x, y: win.minY)); return }
        // slides down from the top, easing out at the end (~0.3 s)
        let endY = win.minY, startY = endY - (b.maxY - win.minY) // starts just above the screen
        let steps = 18
        for i in 0...steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) / 60) {
                let t = Double(i) / Double(steps)
                let ease = 1 - pow(1 - t, 3)
                setPosition(window, CGPoint(x: x, y: startY + (endY - startY) * ease))
            }
        }
    }

    // MARK: "Toolbox" style: system banner hidden, we show our own

    private static func startTracking(_ window: AXUIElement) {
        trackedWindow = window
        setPosition(window, hiddenPosition)
        trackTimer?.invalidate()
        let t = Timer(timeInterval: 0.2, repeats: true) { _ in track() }
        RunLoop.main.add(t, forMode: .common)
        trackTimer = t
        track()
    }

    /// While the banner window exists: keep it hidden and show every new banner.
    private static func track() {
        guard let window = trackedWindow, attr(window, kAXRoleAttribute) != nil else { stopTracking(); return }
        // the banner window can turn into Notification Center (click on date and time while a banner is showing)
        if let reason = panelReason(window) {
            setPosition(window, .zero)
            stopTracking()
            NotificationLog.add(app: "-", outcome: "Notification Center opened while a banner was showing (\(reason)): handed back to macOS")
            return
        }
        let banners = findBanners(window)
        if banners.isEmpty {
            // no more banners: it might turn into Notification Center (click on date and time), so put it back
            setPosition(window, .zero)
            stopTracking()
            return
        }
        for banner in banners {
            let desc = attr(banner, kAXDescriptionAttribute) as? String ?? ""
            let id = attr(banner, kAXIdentifierAttribute) as? String ?? "desc:\(desc)"
            guard !shownBanners.contains(id) else { continue }
            shownBanners.insert(id)
            let app = (desc.components(separatedBy: ", ").first ?? "?").withoutInvisibles
            if let content = read(banner, id: id) {
                NotificationPresenter.shared.show(content, original: banner)
                NotificationLog.add(app: app, outcome: "shown by Toolbox")
            } else {
                systemFallback = true
                NotificationLog.add(app: app, outcome: "unreadable: showing the macOS one")
            }
        }
        if systemFallback {
            if frame(window).origin == hiddenPosition { setPosition(window, .zero) }
        } else if frame(window).origin != hiddenPosition {
            setPosition(window, hiddenPosition)
        }
    }

    private static func stopTracking() {
        trackTimer?.invalidate()
        trackTimer = nil
        trackedWindow = nil
        systemFallback = false
        if shownBanners.count > 200 { shownBanners.removeAll() }
    }

    /// Reads the app, title, subtitle and body of a banner.
    private static func read(_ banner: AXUIElement, id: String) -> NotificationContent? {
        var fields: [String: String] = [:]
        for child in attr(banner, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
            if let key = attr(child, kAXIdentifierAttribute) as? String, let value = attr(child, kAXValueAttribute) as? String {
                fields[key] = value
            }
        }
        // the description is "App, Title, Subtitle, Body": the app name is the first part
        let desc = attr(banner, kAXDescriptionAttribute) as? String ?? ""
        let appName = (desc.components(separatedBy: ", ").first ?? "").withoutInvisibles
        let title = fields["title"] ?? "", subtitle = fields["subtitle"] ?? "", body = fields["body"] ?? ""
        guard !(title.isEmpty && body.isEmpty && appName.isEmpty) else { return nil }
        return NotificationContent(id: id, appName: appName, title: title, subtitle: subtitle, body: body)
    }

    // MARK: actions on the original banner

    /// Like clicking the real notification (opens the right app or conversation).
    @discardableResult
    static func press(_ banner: AXUIElement) -> Bool {
        AXUIElementPerformAction(banner, kAXPressAction as CFString) == .success
    }

    /// Closes the real notification (the banner's "Close" action, "Chiudi" in Italian).
    static func close(_ banner: AXUIElement) {
        var names: CFArray?
        guard AXUIElementCopyActionNames(banner, &names) == .success, let list = names as? [String],
              let action = list.first(where: { $0.contains("Name:Chiudi") || $0.contains("Name:Close") }) else { return }
        AXUIElementPerformAction(banner, action as CFString)
    }

    // MARK: Notification Center or new banner?

    /// Notification Center (the panel on the right) contains widgets; a new banner doesn't (the scrolling
    /// list, instead, is in both). Also: if the user just clicked the date and time, it's definitely the panel.
    /// Returns the reason, or nil if it's a new banner.
    private static func panelReason(_ window: AXUIElement) -> String? {
        if Date().timeIntervalSince(menuBarClickAt) < 2 { return "click on date and time" }
        return containsWidgets(window, depth: 0) ? "contains widgets" : nil
    }

    private static func containsWidgets(_ el: AXUIElement, depth: Int) -> Bool {
        // real widgets: "widget-local:com.apple.iCal…". The banner window only has the empty
        // "widgets-overlay-view" container, which doesn't count.
        let id = attr(el, kAXIdentifierAttribute) as? String ?? ""
        if id.hasPrefix("widget-") { return true }
        let kids = attr(el, kAXChildrenAttribute) as? [AXUIElement] ?? []
        if id == "widgets-overlay-view" { return !kids.isEmpty }
        guard depth < 10 else { return false }
        return kids.contains { containsWidgets($0, depth: depth + 1) }
    }

    /// From the event tap: click in the menu bar, in the date and time area (on the right).
    static func mouseDown(at p: CGPoint) {
        guard let screen = NSScreen.screens.first else { return }
        let menuBar = max(24, screen.frame.maxY - screen.visibleFrame.maxY)
        if p.y <= menuBar, p.x > screen.frame.width * 0.6 { menuBarClickAt = Date() }
    }

    // MARK: Utilities

    private static func findBanners(_ el: AXUIElement, depth: Int = 0) -> [AXUIElement] {
        if attr(el, kAXSubroleAttribute) as? String == bannerSubrole { return [el] }
        guard depth < 7 else { return [] }
        return (attr(el, kAXChildrenAttribute) as? [AXUIElement] ?? []).flatMap { findBanners($0, depth: depth + 1) }
    }

    private static func frame(_ el: AXUIElement) -> CGRect {
        var p = CGPoint.zero, s = CGSize.zero
        if let v = attr(el, kAXPositionAttribute) { AXValueGetValue(v as! AXValue, .cgPoint, &p) }
        if let v = attr(el, kAXSizeAttribute) { AXValueGetValue(v as! AXValue, .cgSize, &s) }
        return CGRect(origin: p, size: s)
    }

    private static func setPosition(_ el: AXUIElement, _ point: CGPoint) {
        var p = point
        AXUIElementSetAttributeValue(el, kAXPositionAttribute as CFString, AXValueCreate(.cgPoint, &p)!)
    }

    private static func attr(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success ? v : nil
    }

    /// Test notification (sent through Script Editor, which needs no permissions for Toolbox).
    static func sendTest() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        let body = String(localized: "This is how your notifications will look. You can change their size, colors and duration in settings.")
        let title = String(localized: "Test Notification")
        p.arguments = ["-e", "display notification \"\(body)\" with title \"\(title)\" subtitle \"Toolbox\""]
        try? p.run()
    }
}
