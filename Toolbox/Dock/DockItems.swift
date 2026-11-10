import Cocoa

/// Power button in the Dock: a "Power" app inside Toolbox.app, which Toolbox launches and quits.
enum PowerButton {
    private static let bundleID = "it.saind.toolbox.power"
    private static var url: URL { Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/Power.app") }
    private static var lastLaunch = Date.distantPast
    private static var isRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty }

    /// Tells Power that the settings have changed (icon color).
    static func notifyChanged() {
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("it.saind.toolbox.power.reload"), object: nil, deliverImmediately: true)
    }

    // MARK: Position in the Dock (Dock configuration: com.apple.dock → persistent-apps)

    private static let dockDomain = "com.apple.dock" as CFString

    static var dockApps: [[String: Any]] {
        CFPreferencesAppSynchronize(dockDomain)
        return CFPreferencesCopyAppValue("persistent-apps" as CFString, dockDomain) as? [[String: Any]] ?? []
    }

    private static func isPower(_ entry: [String: Any]) -> Bool {
        (entry["tile-data"] as? [String: Any])?["bundle-identifier"] as? String == bundleID
    }

    static var isPinned: Bool { dockApps.contains(where: isPower) }

    /// Places Power as the first app in the Dock, right after the Finder (which macOS always keeps first).
    static func pinNextToFinder() {
        if !UserDefaults.standard.bool(forKey: Pref.powerWasPinned) { UserDefaults.standard.set(true, forKey: Pref.powerWasPinned) }
        backupDock()
        var apps = dockApps.filter { !isPower($0) }
        let entry: [String: Any] = [
            "tile-type": "file-tile",
            "tile-data": [
                "bundle-identifier": bundleID,
                "file-label": "Power",
                "file-type": 41,
                "file-data": ["_CFURLString": url.absoluteString, "_CFURLStringType": 15],
            ],
        ]
        apps.insert(entry, at: 0)
        saveDock(apps)
    }

    static func unpin(rememberForLater: Bool = false) {
        if !rememberForLater, UserDefaults.standard.bool(forKey: Pref.powerWasPinned) {
            UserDefaults.standard.set(false, forKey: Pref.powerWasPinned)
        }
        backupDock()
        saveDock(dockApps.filter { !isPower($0) })
    }

    static func saveDock(_ apps: [[String: Any]]) {
        CFPreferencesSetAppValue("persistent-apps" as CFString, apps as CFArray, dockDomain)
        CFPreferencesAppSynchronize(dockDomain)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        p.arguments = ["Dock"] // the Dock relaunches by itself with the new layout
        try? p.run()
    }

    /// Backup of the Dock configuration before every change.
    static func backupDock() {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Toolbox")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
        p.arguments = ["export", "com.apple.dock", dir.appendingPathComponent("dock-backup.plist").path]
        try? p.run()
        p.waitUntilExit()
    }

    /// Called at launch and on every settings change. We only touch the Dock when the
    /// switch actually changes (modifying it makes the Dock relaunch).
    static func sync() {
        let d = UserDefaults.standard
        let enabled = Settings.powerButton
        let previous = d.object(forKey: Pref.powerLastApplied) as? Bool
        // every write to the settings calls sync() again: write only on change, otherwise it's an infinite loop
        if previous != enabled { d.set(enabled, forKey: Pref.powerLastApplied) }

        if enabled {
            if previous == false, d.bool(forKey: Pref.powerWasPinned) { pinNextToFinder() } // back where it was
            // already running or launching: for macOS, reopening it equals a click on the icon (and would show the menu)
            guard !isRunning, Date().timeIntervalSince(lastLaunch) > 10 else { return }
            lastLaunch = Date()
            let cfg = NSWorkspace.OpenConfiguration()
            cfg.activates = false
            cfg.addsToRecentItems = false
            cfg.arguments = ["--background"] // launched by us, not by a click in the Dock: no menu
            NSWorkspace.shared.openApplication(at: url, configuration: cfg)
        } else {
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).forEach { $0.terminate() }
            if previous != false, isPinned {
                if !d.bool(forKey: Pref.powerWasPinned) { d.set(true, forKey: Pref.powerWasPinned) }
                unpin(rememberForLater: true) // to be put back next to the Finder if re-enabled
            }
        }
    }
}

/// Toolbox kept in the Dock (right after Power, if present). Clicking the icon opens the settings.
enum ToolboxDockIcon {
    private static let bundleID = Bundle.main.bundleIdentifier ?? "it.saind.switchtab"

    private static func isToolbox(_ entry: [String: Any]) -> Bool {
        (entry["tile-data"] as? [String: Any])?["bundle-identifier"] as? String == bundleID
    }

    static var isPinned: Bool { PowerButton.dockApps.contains(where: isToolbox) }

    static func pin() {
        PowerButton.backupDock()
        var apps = PowerButton.dockApps.filter { !isToolbox($0) }
        let entry: [String: Any] = [
            "tile-type": "file-tile",
            "tile-data": [
                "bundle-identifier": bundleID,
                "file-label": "Toolbox",
                "file-type": 41,
                "file-data": ["_CFURLString": Bundle.main.bundleURL.absoluteString, "_CFURLStringType": 15],
            ],
        ]
        let afterPower = apps.firstIndex { ($0["tile-data"] as? [String: Any])?["bundle-identifier"] as? String == "it.saind.toolbox.power" }
        apps.insert(entry, at: afterPower.map { $0 + 1 } ?? 0)
        PowerButton.saveDock(apps)
    }

    static func unpin() {
        PowerButton.backupDock()
        PowerButton.saveDock(PowerButton.dockApps.filter { !isToolbox($0) })
    }

    /// As with Power: we only touch the Dock when the switch actually changes.
    static func sync() {
        let d = UserDefaults.standard
        let enabled = Settings.toolboxInDock
        guard d.object(forKey: Pref.toolboxDockLastApplied) as? Bool != enabled else { return }
        d.set(enabled, forKey: Pref.toolboxDockLastApplied)
        if enabled, !isPinned { pin() } else if !enabled, isPinned { unpin() }
    }
}
