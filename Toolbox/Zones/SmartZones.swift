import Cocoa

/// Smart layouts: the layout of a monitor depends on how many windows are open on it, e.g. two columns with
/// two windows and a priority grid with three. The windows are counted when you start dragging (the one you
/// drag included): the visible ones on that monitor and desktop, not minimized or hidden ones, nor those of
/// the apps that don't count. Templates get one zone per window; custom layouts are used as they are.
enum SmartZones {
    /// The window counts with a layout of their own; the last one means "this many or more".
    static let counts = [1, 2, 3, 4]
    /// Beyond this, templates stop adding zones.
    private static let maxZones = 6

    /// Count → layout id; no entry means "the monitor's layout".
    static var layouts: [Int: UUID] {
        get {
            guard let data = UserDefaults.standard.data(forKey: Pref.zonesSmartLayouts),
                  let saved = try? JSONDecoder().decode([String: UUID].self, from: data) else { return defaults }
            return saved.reduce(into: [:]) { r, e in if let n = Int(e.key) { r[n] = e.value } }
        }
        set {
            let saved = newValue.reduce(into: [String: UUID]()) { $0[String($1.key)] = $1.value }
            UserDefaults.standard.set(try? JSONEncoder().encode(saved), forKey: Pref.zonesSmartLayouts)
        }
    }

    private static var defaults: [Int: UUID] {
        [2: ZoneLayout.templateIDs[.columns]!, 3: ZoneLayout.templateIDs[.priorityGrid]!, 4: ZoneLayout.templateIDs[.grid]!]
    }

    /// Apps whose windows don't count: small or utility windows that you don't usually put side by side.
    /// Until the user changes the list, a few of those that are installed.
    static var ignoredApps: [String] {
        get {
            if let list = UserDefaults.standard.stringArray(forKey: Pref.zonesSmartIgnoredApps) { return list }
            return suggestedIgnored.filter {
                $0 == Bundle.main.bundleIdentifier || NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil
            }
        }
        set { UserDefaults.standard.set(newValue, forKey: Pref.zonesSmartIgnoredApps) }
    }

    private static let suggestedIgnored = [
        "com.apple.calculator", "com.apple.systempreferences", "com.apple.ActivityMonitor", "com.apple.Stickies",
        "com.apple.DigitalColorMeter", "com.apple.archiveutility", "com.apple.installer",
        Bundle.main.bundleIdentifier ?? "it.saind.switchtab", // Toolbox's own settings
    ]

    /// The layout to use on `screen` while dragging `window` (or moving it with the keyboard).
    static func layout(for screen: NSScreen, window: CGWindowID?) -> ZoneLayout {
        let store = ZoneStore.shared
        guard ZoneSettings.smart else { return store.layout(for: screen) }
        let n = count(on: screen, including: window)
        guard let id = layouts[min(n, counts.last!)], var layout = store.layout(id) else { return store.layout(for: screen) }
        if layout.kind.isTemplate && layout.kind != .blank { layout.zoneCount = max(1, min(n, maxZones)) }
        return layout
    }

    /// Windows that count on that monitor, `window` always included (it's the one being placed there).
    static func count(on screen: NSScreen, including window: CGWindowID?) -> Int {
        let ignored = Set(ignoredApps), excluded = Set(ZoneSettings.excludedApps)
        let visible = WindowManager.visibleWindows()
        let bounds = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []).reduce(into: [CGWindowID: CGRect]()) { r, w in
                if let id = w[kCGWindowNumber as String] as? CGWindowID, let b = w[kCGWindowBounds as String] as? NSDictionary,
                   let rect = CGRect(dictionaryRepresentation: b) { r[id] = rect }
            }
        var n = window == nil ? 0 : 1
        for w in visible where w.id != window {
            guard let frame = bounds[w.id], ScreenGeo.screen(for: frame) == screen else { continue }
            let bundle = NSRunningApplication(processIdentifier: w.pid)?.bundleIdentifier ?? ""
            if ignored.contains(bundle) || excluded.contains(bundle) { continue }
            n += 1
        }
        return max(1, n)
    }
}
