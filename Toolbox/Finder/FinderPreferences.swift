import Cocoa

// MARK: - Finder settings (the ones Apple already provides, often hidden)

/// Each option writes an official Finder setting; turning it off restores Apple's default.
struct FinderPref: Identifiable {
    let id: String              // key in Toolbox settings ("finder.<id>")
    let label: String
    let help: String
    let recommended: Bool       // the "like Windows" value
    let apply: (Bool) -> Void

    var enabled: Bool { UserDefaults.standard.object(forKey: "finder.\(id)") as? Bool ?? recommended }
}

enum FinderPrefs {
    private static let finder = "com.apple.finder" as CFString

    private static func set(_ key: String, _ value: Any?) {
        CFPreferencesSetAppValue(key as CFString, value as CFPropertyList?, finder)
    }
    private static func setGlobal(_ key: String, _ value: Any?) {
        CFPreferencesSetValue(key as CFString, value as CFPropertyList?, kCFPreferencesAnyApplication,
                              kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }

    static let all: [FinderPref] = [
        FinderPref(id: "extensions", label: String(localized: "Always show file extensions"),
                   help: String(localized: "\"photo.jpg\" instead of \"photo\", like Windows with extensions shown."), recommended: true) {
            setGlobal("AppleShowAllExtensions", $0 ? true : nil)
        },
        FinderPref(id: "foldersFirst", label: String(localized: "Folders before files"),
                   help: String(localized: "When sorting by name, folders always stay on top."), recommended: true) {
            set("_FXSortFoldersFirst", $0 ? true : nil)
            set("_FXSortFoldersFirstOnDesktop", $0 ? true : nil)
        },
        FinderPref(id: "pathbar", label: String(localized: "Path bar at the bottom"),
                   help: String(localized: "Shows where you are (Macintosh HD › Users › …); each part is clickable."), recommended: true) {
            set("ShowPathbar", $0 ? true : nil)
        },
        FinderPref(id: "statusbar", label: String(localized: "Status bar"),
                   help: String(localized: "Number of items and free disk space, like in Windows File Explorer."), recommended: true) {
            set("ShowStatusBar", $0 ? true : nil)
        },
        FinderPref(id: "pathTitle", label: String(localized: "Full path in the window title"),
                   help: String(localized: "The title becomes /Users/…/Downloads instead of \"Downloads\"."), recommended: true) {
            set("_FXShowPosixPathInTitle", $0 ? true : nil)
        },
        FinderPref(id: "listView", label: String(localized: "List view (details) by default"),
                   help: String(localized: "Applies to folders you haven't already set differently."), recommended: true) {
            set("FXPreferredViewStyle", $0 ? "Nlsv" : nil)
        },
        FinderPref(id: "folderSizes", label: String(localized: "Calculate folder sizes"),
                   help: String(localized: "In list view, folders also show how big they are."), recommended: true) {
            setListViewSize($0)
        },
        FinderPref(id: "searchHere", label: String(localized: "Search starts in the current folder"),
                   help: String(localized: "Like Windows: it doesn't search the whole Mac."), recommended: true) {
            set("FXDefaultSearchScope", $0 ? "SCcf" : nil)
        },
        FinderPref(id: "noExtWarning", label: String(localized: "Don't ask for confirmation when changing an extension"),
                   help: "", recommended: true) {
            set("FXEnableExtensionChangeWarning", $0 ? false : nil)
        },
        FinderPref(id: "newWindowHome", label: String(localized: "New windows open in your home folder"),
                   help: String(localized: "Instead of \"Recents\"."), recommended: true) {
            set("NewWindowTarget", $0 ? "PfHm" : nil)
            set("NewWindowTargetPath", $0 ? FileManager.default.homeDirectoryForCurrentUser.absoluteString : nil)
        },
        FinderPref(id: "hidden", label: String(localized: "Show hidden files"),
                   help: String(localized: "⌘⇧. also shows and hides them on the fly."), recommended: false) {
            set("AppleShowAllFiles", $0 ? true : nil)
        },
    ]

    /// "Calculate all sizes" lives inside the list view settings.
    private static func setListViewSize(_ on: Bool) {
        var std = CFPreferencesCopyAppValue("StandardViewSettings" as CFString, finder) as? [String: Any] ?? [:]
        for key in ["ExtendedListViewSettingsV2", "ListViewSettings"] {
            var list = std[key] as? [String: Any] ?? [:]
            list["calculateAllSizes"] = on
            std[key] = list
        }
        set("StandardViewSettings", std)
    }

    /// Applies the choices and relaunches the Finder (open windows reopen by themselves).
    /// Finder settings are never changed without asking: the first time, they are applied
    /// from the Finder page of the settings.
    static var applied: Bool { UserDefaults.standard.bool(forKey: Pref.finderPrefsApplied) }

    static func applyAll() {
        UserDefaults.standard.set(true, forKey: Pref.finderPrefsApplied)
        backup()
        for p in all { p.apply(p.enabled) }
        CFPreferencesAppSynchronize(finder)
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        restartFinder()
    }

    /// The first time: backup of the Finder's original settings.
    private static var backupURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Toolbox/finder-backup.plist")
    }

    private static func backup() {
        guard !FileManager.default.fileExists(atPath: backupURL.path) else { return }
        try? FileManager.default.createDirectory(at: backupURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        run("/usr/bin/defaults", ["export", "com.apple.finder", backupURL.path])
        let ext = CFPreferencesCopyValue("AppleShowAllExtensions" as CFString, kCFPreferencesAnyApplication,
                                         kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? Bool
        UserDefaults.standard.set(ext ?? false, forKey: Pref.finderBackupShowExtensions)
    }

    /// Restores the Finder settings to how they were before Toolbox.
    static func restoreOriginal() {
        guard FileManager.default.fileExists(atPath: backupURL.path) else { return }
        run("/usr/bin/defaults", ["import", "com.apple.finder", backupURL.path])
        setGlobal("AppleShowAllExtensions", UserDefaults.standard.bool(forKey: Pref.finderBackupShowExtensions) ? true : nil)
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        for p in all { UserDefaults.standard.set(false, forKey: "finder.\(p.id)") }
        restartFinder()
    }

    static var hasBackup: Bool { FileManager.default.fileExists(atPath: backupURL.path) }

    private static func restartFinder() { run("/usr/bin/killall", ["Finder"], wait: false) }

    private static func run(_ path: String, _ args: [String], wait: Bool = true) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        try? p.run()
        if wait { p.waitUntilExit() }
    }
}
