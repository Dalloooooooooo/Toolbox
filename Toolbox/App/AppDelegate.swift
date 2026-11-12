import Cocoa
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let switcher = SwitcherController()
    private lazy var hotkey = HotkeyTap(switcher: switcher)
    private var statusItem: NSStatusItem!
    private var statusLine: NSMenuItem!
    private let settings = SettingsWindowController()
    private var hotkeyActive = false
    private let wallpaperService = WallpaperService()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenu()
        // after the rename (SwitchTab → Toolbox), open-at-login must be registered again for the new path
        if UserDefaults.standard.bool(forKey: Pref.reRegisterLogin) {
            UserDefaults.standard.removeObject(forKey: Pref.reRegisterLogin)
            try? SMAppService.mainApp.register()
        }
        WindowManager.startTracking()
        PreviewStore.startBackgroundRefresh()
        CtrlScrollZoom.start()
        NotificationMover.start()
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        Log.info("starting Toolbox \(Updater.currentVersion) on macOS \(os), Accessibility \(AXIsProcessTrusted() ? "yes" : "no")")
        CrashReporter.checkOnLaunch()
        MacOSTiling.sync()
        PowerButton.sync()
        ToolboxDockIcon.sync()
        MinimizeIntoAppIcon.sync()
        DockPreview.start()
        Updater.shared.start()
        DispatchQueue.global(qos: .utility).async { AppIndex.build(force: true) } // for notification icons
        NSApp.servicesProvider = wallpaperService
        NSUpdateDynamicServices()
        // asks for permissions the first time
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
        if !CGPreflightScreenCaptureAccess() { CGRequestScreenCaptureAccess() }
        startHotkey()
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil,
                                               queue: .main) { [weak self] _ in self?.hotkeyChanged() }
        // if the app is killed, give ⌘Tab back to macOS
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig) { _ in SystemHotkeys.restoreAll(); exit(0) }
        }
        // opened by the user (Dock, Launchpad, Finder) → settings; at login or after an automatic
        // update it stays quietly in the menu bar
        let firstLaunch = !UserDefaults.standard.bool(forKey: Pref.launchedBefore)
        UserDefaults.standard.set(true, forKey: Pref.launchedBefore)
        let background = CommandLine.arguments.contains("--background")
        let atLogin = launchedAsLoginItem || justLoggedIn
        Log.info("launch: \(firstLaunch ? "first launch" : background ? "background" : atLogin ? "at login" : "by the user")")
        if firstLaunch || !(atLogin || background) {
            settings.show()
        }
    }

    /// A safety net for the login-item check: macOS doesn't always say so (for example when it reopens the
    /// apps that were open at shutdown). The Dock starts when you log in: if it started moments ago,
    /// nobody opened Toolbox by hand. Opening it again from the Dock or Launchpad still shows the settings.
    private var justLoggedIn: Bool {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first,
              let started = Self.startDate(of: dock.processIdentifier) else { return false }
        return Date().timeIntervalSince(started) < 90
    }

    /// When a process started, from the kernel (`launchDate` is empty for the Dock: launchd starts it).
    private static func startDate(of pid: pid_t) -> Date? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let t = info.kp_proc.p_un.__p_starttime
        guard t.tv_sec > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(t.tv_sec) + TimeInterval(t.tv_usec) / 1_000_000)
    }

    private var launchedAsLoginItem = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        let event = NSAppleEventManager.shared().currentAppleEvent
        launchedAsLoginItem = event?.eventID == kAEOpenApplication &&
            event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }

    /// Right-click on the Dock icon.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(item(String(localized: "Settings…"), #selector(openSettings as () -> Void)))
        menu.addItem(item(String(localized: "Check for Updates…"), #selector(checkUpdates)))
        return menu
    }

    func applicationWillTerminate(_ notification: Notification) { SystemHotkeys.restoreAll() }

    /// Double-clicking the app while it is already running → settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        settings.show()
        return false
    }

    private func hotkeyChanged() {
        MacOSTiling.sync()
        PowerButton.sync()
        ToolboxDockIcon.sync()
        MinimizeIntoAppIcon.sync()
        guard hotkeyActive else { return }
        SystemHotkeys.sync()
        statusLine.title = String(localized: "Active — press \(Settings.modifier.symbol) \(Settings.key.short)")
    }

    /// Retries until the user grants the Accessibility permission.
    private func startHotkey() {
        if AXIsProcessTrusted(), hotkey.start() {
            hotkeyActive = true
            hotkeyChanged()
        } else {
            statusLine.title = String(localized: "Waiting for Accessibility permission…")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.startHotkey() }
        }
    }

    private func setupMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "wrench.and.screwdriver",
                                           accessibilityDescription: "Toolbox")
        let menu = NSMenu()
        statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        menu.addItem(statusLine)
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Settings…"), #selector(openSettings as () -> Void), key: ","))
        menu.addItem(item(String(localized: "Check for Updates…"), #selector(checkUpdates)))
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Quit Toolbox"), #selector(quit), key: "q"))
        statusItem.menu = menu
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        return i
    }

    @objc private func openSettings() { settings.show() }

    func openSettings(section: SettingsSection) {
        UserDefaults.standard.set(section.rawValue, forKey: Pref.settingsSection)
        settings.show()
    }

    @objc private func checkUpdates() {
        openSettings(section: .updates)
        Updater.shared.check(.user)
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
