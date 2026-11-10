import Cocoa

/// "Power": a power button in the Dock. Left or right click → menu with the actions chosen in
/// Toolbox settings (Power tab). It is launched by Toolbox and stays open, with no windows.
/// Its settings are Toolbox's (same preferences domain).
private let prefsDomain = "it.saind.switchtab"
private let reloadNotification = Notification.Name("it.saind.toolbox.power.reload")

private enum Prefs {
    static var defaults: UserDefaults {
        CFPreferencesAppSynchronize(prefsDomain as CFString)
        return UserDefaults(suiteName: prefsDomain) ?? .standard
    }
    static func bool(_ key: String, _ def: Bool) -> Bool { defaults.object(forKey: key) as? Bool ?? def }
    static var confirm: Bool { bool(Pref.powerConfirm, false) }
    static var iconVariant: PowerIconVariant {
        PowerIconVariant(rawValue: defaults.string(forKey: Pref.powerIconColor) ?? "") ?? .yellow
    }
}

final class PowerDelegate: NSObject, NSApplicationDelegate {
    private var scheduled: (date: Date, timer: Timer, badge: Timer)?
    private let backgroundLaunch = CommandLine.arguments.contains("--background")
    private let launchTime = Date()

    func applicationDidFinishLaunching(_ notification: Notification) {
        updateIcon()
        DistributedNotificationCenter.default().addObserver(forName: reloadNotification, object: nil, queue: .main) {
            [weak self] _ in self?.updateIcon()
        }
        // launched by a click in the Dock (not by Toolbox, which opens it in the background): show the menu right away
        // (Toolbox launches it with --background: in that case, no menu)
        guard !CommandLine.arguments.contains("--background") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [self] in
            if NSApp.isActive { _ = applicationShouldHandleReopen(NSApp, hasVisibleWindows: false) }
        }
    }

    // MARK: Menu

    /// The menu is rebuilt every time it opens, so it always reflects the settings.
    private func buildMenu() -> NSMenu {
        let m = NSMenu()
        if let s = scheduled {
            let mins = max(1, Int(ceil(s.date.timeIntervalSinceNow / 60)))
            m.addItem(item(String(localized: "Cancel shutdown (in \(mins) min)"), "xmark.circle", #selector(cancelSchedule)))
            m.addItem(.separator())
        }
        if Prefs.bool(Pref.powerShowLock, true) { m.addItem(item(String(localized: "Lock Screen"), "lock.fill", #selector(lock))) }
        if Prefs.bool(Pref.powerShowDisplayOff, false) { m.addItem(item(String(localized: "Turn Off Display"), "display", #selector(displayOff))) }
        if Prefs.bool(Pref.powerShowSleep, true) { m.addItem(item(String(localized: "Sleep"), "moon.fill", #selector(sleepNow))) }
        if Prefs.bool(Pref.powerShowLogout, false) { m.addItem(item(String(localized: "Log Out…"), "person.crop.circle.badge.xmark", #selector(logout))) }
        if m.items.contains(where: { !$0.isSeparatorItem }) { m.addItem(.separator()) }
        if Prefs.bool(Pref.powerShowRestart, true) { m.addItem(item(String(localized: "Restart"), "arrow.clockwise", #selector(restart))) }
        if Prefs.bool(Pref.powerShowShutdown, true) { m.addItem(item(String(localized: "Shut Down"), "power", #selector(shutDown))) }
        if Prefs.bool(Pref.powerShowTimer, true) && scheduled == nil {
            let sub = NSMenu()
            for (label, minutes) in [(String(localized: "15 minutes"), 15), (String(localized: "30 minutes"), 30),
                                    (String(localized: "1 hour"), 60), (String(localized: "2 hours"), 120)] {
                let i = item(label, nil, #selector(schedule(_:)))
                i.tag = minutes
                sub.addItem(i)
            }
            let parent = item(String(localized: "Shut Down In…"), "timer", nil)
            parent.submenu = sub
            m.addItem(parent)
        }
        if m.items.last?.isSeparatorItem == true { m.removeItem(at: m.items.count - 1) }
        return m
    }

    private func item(_ title: String, _ symbol: String?, _ action: Selector?) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
        if let symbol { i.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        i.target = self
        return i
    }

    /// Right click on the Dock icon: the items appear at the top of the Dock menu.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? { buildMenu() }

    /// Left click on the icon (the app is already running): menu under the pointer.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        // launched by Toolbox: in the first few seconds a "reopen" comes from Toolbox, not from a user click
        if backgroundLaunch, Date().timeIntervalSince(launchTime) < 5 { return false }
        DispatchQueue.main.async { [self] in
            buildMenu().popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
            NSApp.hide(nil) // the previous app comes back to the front
        }
        return false
    }

    // MARK: Actions

    @objc private func lock() {
        // the system function used by the  menu → Lock Screen
        typealias LockFn = @convention(c) () -> Void
        if let h = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_LAZY),
           let sym = dlsym(h, "SACLockScreenImmediate") {
            unsafeBitCast(sym, to: LockFn.self)()
        } else {
            run("/usr/bin/pmset", ["displaysleepnow"])
        }
    }
    @objc private func displayOff() { run("/usr/bin/pmset", ["displaysleepnow"]) }
    @objc private func sleepNow() { run("/usr/bin/pmset", ["sleepnow"]) }
    @objc private func logout() { confirmThen(String(localized: "Do you want to log out?")) { self.sendToSystem(AEEventID(kAELogOut)) } }
    @objc private func restart() { confirmThen(String(localized: "Do you want to restart your Mac?")) { self.sendToSystem(AEEventID(kAERestart)) } }
    @objc private func shutDown() { confirmThen(String(localized: "Do you want to shut down your Mac?")) { self.sendToSystem(AEEventID(kAEShutDown)) } }

    // MARK: Scheduled shutdown (number of minutes on the Dock icon)

    @objc private func schedule(_ sender: NSMenuItem) {
        let date = Date().addingTimeInterval(TimeInterval(sender.tag * 60))
        let timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(sender.tag * 60), repeats: false) { [weak self] _ in
            self?.scheduled = nil
            NSApp.dockTile.badgeLabel = nil
            self?.sendToSystem(AEEventID(kAEShutDown))
        }
        let badge = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in self?.updateBadge() }
        scheduled = (date, timer, badge)
        updateBadge()
    }

    @objc private func cancelSchedule() {
        scheduled?.timer.invalidate()
        scheduled?.badge.invalidate()
        scheduled = nil
        NSApp.dockTile.badgeLabel = nil
    }

    private func updateBadge() {
        guard let s = scheduled else { return }
        let mins = max(1, Int(ceil(s.date.timeIntervalSinceNow / 60)))
        NSApp.dockTile.badgeLabel = mins >= 60 ? "\(mins / 60)h\(mins % 60 > 0 ? "\(mins % 60)" : "")" : "\(mins)'"
    }

    // MARK: Utilities

    private func confirmThen(_ question: String, _ action: @escaping () -> Void) {
        guard Prefs.confirm else { action(); return }
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = question
        alert.informativeText = String(localized: "Open apps will ask you to save their documents.")
        alert.addButton(withTitle: String(localized: "Confirm"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        if alert.runModal() == .alertFirstButtonReturn { action() }
        NSApp.hide(nil)
    }

    /// The approach recommended by Apple: ask the system (loginwindow) to restart/shut down/log out.
    /// Apps quit normally and ask to save open documents.
    private func sendToSystem(_ id: AEEventID) {
        var psn = ProcessSerialNumber(highLongOfPSN: 0, lowLongOfPSN: UInt32(kSystemProcess))
        let target = NSAppleEventDescriptor(descriptorType: typeProcessSerialNumber, bytes: &psn,
                                            length: MemoryLayout<ProcessSerialNumber>.size)
        let event = NSAppleEventDescriptor(eventClass: AEEventClass(kCoreEventClass), eventID: id,
                                           targetDescriptor: target, returnID: AEReturnID(kAutoGenerateReturnID),
                                           transactionID: AETransactionID(kAnyTransactionID))
        if let desc = event.aeDesc { AESendMessage(desc, nil, AESendMode(kAENoReply), kAEDefaultTimeout) }
    }

    private func run(_ path: String, _ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        try? p.run()
    }

    /// Dock icon in the chosen color variant (yellow = the original icon).
    private func updateIcon() {
        guard let base = PowerIconVariant.baseImage(in: .main) else { return }
        NSApp.applicationIconImage = Prefs.iconVariant.apply(to: base)
    }
}

let app = NSApplication.shared
let delegate = PowerDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
