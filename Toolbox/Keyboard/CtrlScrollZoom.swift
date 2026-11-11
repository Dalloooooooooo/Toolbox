import Cocoa

/// Ctrl + mouse wheel zooms, like on Windows: wheel away from you zooms in, towards you zooms out, one
/// step per notch. It works in the app under the pointer, only if that app can zoom: Toolbox looks in
/// its menus for the ⌘+ / ⌘− items (Zoom In / Zoom Out in browsers, Preview, Photos, Maps, Office…)
/// and presses them. Elsewhere Ctrl + wheel stays a normal scroll. Font size items (⌘+ next to
/// Bold and Italic, as in TextEdit's and Mail's Font menu) are not zoom and are left alone.
///
/// Scroll events are frequent, so this has its own event tap on its own thread: the rest of Toolbox
/// (and scrolling everywhere) doesn't wait for it.
enum CtrlScrollZoom {
    private static var tap: CFMachPort?
    private static let queue = DispatchQueue(label: "ctrl-scroll-zoom")

    static func start() {
        let thread = Thread {
            let mask = CGEventMask(1) << CGEventType.scrollWheel.rawValue
            guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                            eventsOfInterest: mask, callback: callback, userInfo: nil) else {
                Log.info("Ctrl + wheel zoom: no event tap")
                return
            }
            tap = t
            CFRunLoopAddSource(CFRunLoopGetCurrent(), CFMachPortCreateRunLoopSource(nil, t, 0), .commonModes)
            CGEvent.tapEnable(tap: t, enable: true)
            CFRunLoopRun()
        }
        thread.name = "Ctrl + wheel zoom"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    private static let callback: CGEventTapCallBack = { _, type, event, _ in
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        return handle(event) ? nil : Unmanaged.passUnretained(event)
    }

    // MARK: Wheel → steps (tap thread)

    private static var accumulated: Double = 0

    /// True if the event becomes a zoom (and is swallowed).
    private static func handle(_ event: CGEvent) -> Bool {
        let other: CGEventFlags = [.maskCommand, .maskAlternate, .maskShift]
        guard event.flags.contains(.maskControl), event.flags.isDisjoint(with: other),
              UserDefaults.standard.object(forKey: Pref.ctrlScrollZoom) as? Bool ?? true,
              let pid = appUnderPointer(event.location), pid != ProcessInfo.processInfo.processIdentifier,
              Menus.zoomable(pid) != false else { accumulated = 0; return false }
        // momentum after lifting the fingers from a trackpad / Magic Mouse: no more zooming
        if event.getIntegerValueField(.scrollWheelEventMomentumPhase) != 0 { return true }

        // the physical direction: with natural scrolling macOS flips the deltas, Windows doesn't
        let inverted = NSEvent(cgEvent: event)?.isDirectionInvertedFromDevice ?? false
        var steps = 0
        if event.getIntegerValueField(.scrollWheelEventIsContinuous) == 0 {
            let d = event.getIntegerValueField(.scrollWheelEventDeltaAxis1) * (inverted ? -1 : 1)
            steps = d > 0 ? 1 : d < 0 ? -1 : 0 // a notch is a step, however fast the wheel turns
        } else {
            accumulated += event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1) * (inverted ? -1 : 1)
            let unit = 40.0
            if abs(accumulated) >= unit {
                steps = accumulated > 0 ? 1 : -1
                accumulated = 0
            }
        }
        if steps != 0 { queue.async { Menus.zoom(pid, in: steps > 0) } }
        return true
    }

    /// The app that owns the topmost window under the pointer.
    private static func appUnderPointer(_ p: CGPoint) -> pid_t? {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        for info in list {
            guard let b = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: b), frame.contains(p),
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0 else { continue }
            if (info[kCGWindowLayer as String] as? Int) != 0 {
                // the Dock keeps a transparent window as big as the screen: look through it
                if let screen = ScreenGeo.screen(at: p), frame.width >= screen.frame.width,
                   frame.height >= screen.frame.height { continue }
                return nil // the Dock itself, the menu bar and the like are not windows to zoom
            }
            return info[kCGWindowOwnerPID as String] as? pid_t
        }
        return nil
    }

    // MARK: Zoom menu items (serial queue, except the cache read)

    private enum Menus {
        struct Items { let zoomIn: AXUIElement; let zoomOut: AXUIElement; let found: Date }
        struct Missing { let since: Date }

        private static let lock = NSLock()
        private static var found: [pid_t: Items] = [:]
        private static var missing: [pid_t: Missing] = [:]

        /// false if the app is known to have no zoom; nil if not looked at yet.
        static func zoomable(_ pid: pid_t) -> Bool? {
            lock.lock(); defer { lock.unlock() }
            if found[pid] != nil { return true }
            // apps change their menus (a document opens…): look again after a while
            if let m = missing[pid], Date().timeIntervalSince(m.since) < 15 { return false }
            return nil
        }

        static func zoom(_ pid: pid_t, in zoomIn: Bool) {
            lock.lock()
            var items = found[pid]
            lock.unlock()
            if items == nil || !press(items!, zoomIn) {
                items = scan(pid)
                lock.lock()
                if let items { found[pid] = items; missing[pid] = nil } else { found[pid] = nil; missing[pid] = Missing(since: Date()) }
                lock.unlock()
                if let items { _ = press(items, zoomIn) }
            }
        }

        /// False if the item is no longer valid (the menus were rebuilt).
        private static func press(_ items: Items, _ zoomIn: Bool) -> Bool {
            let item = zoomIn ? items.zoomIn : items.zoomOut
            var enabled: CFTypeRef?
            guard AXUIElementCopyAttributeValue(item, kAXEnabledAttribute as CFString, &enabled) == .success else { return false }
            guard enabled as? Bool == true else { return true } // can't zoom further, or no document: nothing to do
            return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
        }

        private static func scan(_ pid: pid_t) -> Items? {
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, 0.5)
            guard let bar: AXUIElement = value(app, kAXMenuBarAttribute) else { return nil }
            var zoomIn: AXUIElement?, zoomOut: AXUIElement?
            func walk(_ menu: AXUIElement, depth: Int) {
                let items: [AXUIElement] = value(menu, kAXChildrenAttribute) ?? []
                // the Font menu (⌘B and ⌘I next to ⌘+) changes the text size, it doesn't zoom
                let chars = Set(items.compactMap { (value($0, kAXMenuItemCmdCharAttribute) as String?)?.lowercased() })
                let isFontMenu = chars.contains("b") && chars.contains("i")
                for item in items {
                    if !isFontMenu, let c: String = value(item, kAXMenuItemCmdCharAttribute) {
                        let mods: Int = value(item, kAXMenuItemCmdModifiersAttribute) ?? 0
                        // ⌘ alone (0), or ⇧⌘ for "+" typed as ⇧= (1)
                        if zoomIn == nil, (c == "+" || c == "="), mods == 0 || mods == 1 { zoomIn = item }
                        if zoomOut == nil, c == "-", mods == 0 { zoomOut = item }
                    }
                    if depth < 3, let sub: [AXUIElement] = value(item, kAXChildrenAttribute) {
                        sub.forEach { walk($0, depth: depth + 1) }
                    }
                }
            }
            let menus: [AXUIElement] = value(bar, kAXChildrenAttribute) ?? []
            for top in menus.dropFirst() { // not the Apple menu
                (value(top, kAXChildrenAttribute) as [AXUIElement]?)?.forEach { walk($0, depth: 1) }
                if zoomIn != nil && zoomOut != nil { break }
            }
            guard let zoomIn, let zoomOut else { return nil }
            return Items(zoomIn: zoomIn, zoomOut: zoomOut, found: Date())
        }

        private static func value<T>(_ el: AXUIElement, _ attr: String) -> T? {
            var v: CFTypeRef?
            guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success else { return nil }
            return v as? T
        }
    }
}
