import Cocoa
import ServiceManagement

/// Complete one-click uninstall: restores everything Toolbox changed and deletes everything it
/// created. The app goes to the Trash (recoverable); screenshots stay, because they are the
/// user's files.
enum Uninstaller {
    static let bundleIDs = [Bundle.main.bundleIdentifier ?? "it.saind.switchtab",
                            "it.saind.toolbox.power", "it.saind.toolbox.explorer"]

    static func confirmAndUninstall() {
        let alert = NSAlert()
        alert.messageText = String(localized: "Uninstall Toolbox?")
        alert.informativeText = String(localized: """
            Toolbox restores the Finder, macOS window tiling and the system ⌘Tab as they were, \
            removes its Dock icons and open at login, and deletes its settings, permissions and logs. \
            The app goes to the Trash. Screenshots you saved stay where they are.
            """)
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "Uninstall"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.buttons.first?.hasDestructiveAction = true
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        uninstall()
    }

    private static func uninstall() {
        Log.info("uninstalling")
        // with the features turned off, their sync calls no longer put anything back (Dock, Power, tiling)
        let d = UserDefaults.standard
        for key in [Pref.snapEnabled, Pref.toolboxInDock, Pref.powerButton] { d.set(false, forKey: key) }
        // 1. whatever Toolbox changed in the system goes back to how it was
        MacOSTiling.restore()
        MinimizeIntoAppIcon.restore()
        if FinderPrefs.hasBackup { FinderPrefs.restoreOriginal() }
        SystemHotkeys.restoreAll()
        try? SMAppService.mainApp.unregister()
        ToolboxDockIcon.unpin()
        PowerButton.unpin()
        for id in bundleIDs.dropFirst() {
            NSRunningApplication.runningApplications(withBundleIdentifier: id).forEach { $0.terminate() }
        }
        // 2. the app goes to the Trash (this works even while it is running)
        NSWorkspace.shared.recycle([Bundle.main.bundleURL]) { _, error in
            if let error { Log.error("app not moved to the Trash: \(error.localizedDescription)") }
        }
        // 3. once Toolbox has quit (otherwise it would rewrite its preferences on exit): preferences, permissions, files
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var commands: [String] = []
        for id in bundleIDs {
            commands.append("/usr/bin/defaults delete \(id)")
            commands.append("/usr/bin/tccutil reset All \(id)")
            for folder in ["Library/Caches/\(id)", "Library/HTTPStorages/\(id)", "Library/Saved Application State/\(id).savedState",
                           "Library/Preferences/\(id).plist"] {
                commands.append("/bin/rm -rf \(Relauncher.shellQuoted("\(home)/\(folder)"))")
            }
        }
        for folder in ["Library/Application Support/Toolbox", "Library/Logs/Toolbox"] {
            commands.append("/bin/rm -rf \(Relauncher.shellQuoted("\(home)/\(folder)"))")
        }
        Relauncher.quit(then: commands.map { $0 + " >/dev/null 2>&1" }.joined(separator: "; "))
    }
}
