import Cocoa

/// Minimized windows go into their app's Dock icon instead of next to the Trash, like on the Windows
/// taskbar (it's the macOS option "Minimize windows into application icon"). Toolbox remembers how it was
/// before changing it (`Pref.minimizeIntoAppBackup`) and puts it back when the option is turned off or on uninstall.
enum MinimizeIntoAppIcon {
    private static let dock = "com.apple.dock" as CFString
    private static let key = "minimize-to-application" as CFString

    private static var current: Bool {
        CFPreferencesAppSynchronize(dock)
        return CFPreferencesCopyAppValue(key, dock) as? Bool ?? false
    }

    /// Call at launch and whenever settings change: writes (and restarts the Dock) only when needed.
    static func sync() {
        let d = UserDefaults.standard
        if Settings.minimizeIntoAppIcon {
            guard !current else { return }
            if d.object(forKey: Pref.minimizeIntoAppBackup) == nil { d.set(false, forKey: Pref.minimizeIntoAppBackup) }
            write(true)
        } else {
            restore()
        }
    }

    /// Back to how it was, if Toolbox was the one that changed it.
    static func restore() {
        let d = UserDefaults.standard
        guard let before = d.object(forKey: Pref.minimizeIntoAppBackup) as? Bool else { return }
        d.removeObject(forKey: Pref.minimizeIntoAppBackup)
        if current != before { write(before) }
    }

    private static func write(_ on: Bool) {
        CFPreferencesSetAppValue(key, on as CFBoolean, dock)
        CFPreferencesAppSynchronize(dock)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        p.arguments = ["Dock"] // the Dock relaunches by itself with the new setting
        try? p.run()
        Log.info("Minimize into app icon: \(on)")
    }
}
