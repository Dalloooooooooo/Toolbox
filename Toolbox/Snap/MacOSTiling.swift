import Cocoa

/// macOS tiling (Sequoia and later) does the same job as "Snap windows" and the two would conflict.
/// While ours is on, Toolbox turns off the macOS one; turning ours off turns it back on, but only if
/// Toolbox was the one that turned it off. The previous state is saved in `Pref.macTilingBackup`.
enum MacOSTiling {
    private static let domain = "com.apple.WindowManager" as CFString
    /// "Drag windows to screen edges to tile" and "…to menu bar to fill screen"
    private static let keys = ["EnableTilingByEdgeDrag", "EnableTopTilingByEdgeDrag"]
    /// Placeholder in the backup: the option had never been touched (macOS default applies, i.e. on).
    private static let untouched = "default"

    static var isSupported: Bool {
        ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0))
    }

    static var isActive: Bool { isSupported && keys.contains { value($0) ?? true } }

    /// Call at launch and whenever settings change: writes only when needed.
    static func sync() {
        guard isSupported else { return }
        let defaults = UserDefaults.standard
        if SnapSettings.enabled {
            guard isActive else { return }
            if defaults.dictionary(forKey: Pref.macTilingBackup) == nil {
                var backup: [String: Any] = [:]
                for k in keys { backup[k] = value(k).map { $0 as Any } ?? untouched }
                defaults.set(backup, forKey: Pref.macTilingBackup)
            }
            write(keys.map { ($0, false) })
            Log.info("macOS tiling turned off (replaced by Toolbox snapping)")
        } else {
            restore()
        }
    }

    /// Restores macOS tiling as it was, if Toolbox was the one that turned it off.
    static func restore() {
        let defaults = UserDefaults.standard
        guard isSupported, let backup = defaults.dictionary(forKey: Pref.macTilingBackup) else { return }
        defaults.removeObject(forKey: Pref.macTilingBackup)
        write(keys.map { ($0, backup[$0] as? Bool) }) // nil → back to the macOS default
        Log.info("macOS tiling restored")
    }

    private static func value(_ key: String) -> Bool? {
        CFPreferencesCopyAppValue(key as CFString, domain) as? Bool
    }

    private static func write(_ values: [(String, Bool?)]) {
        for (key, value) in values {
            CFPreferencesSetAppValue(key as CFString, value.map { NSNumber(value: $0) }, domain)
        }
        CFPreferencesAppSynchronize(domain)
        // WindowManager reads these options at launch; macOS relaunches it on its own right away
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        p.arguments = ["WindowManager"]
        try? p.run()
    }
}
