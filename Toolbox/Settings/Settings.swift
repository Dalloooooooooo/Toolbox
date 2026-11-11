import Cocoa

enum HotkeyModifier: String, CaseIterable, Identifiable {
    case command, option, control
    var id: String { rawValue }
    var flag: CGEventFlags {
        switch self {
        case .command: .maskCommand
        case .option: .maskAlternate
        case .control: .maskControl
        }
    }
    var label: String {
        switch self {
        case .command: String(localized: "⌘ Command")
        case .option: String(localized: "⌥ Option")
        case .control: String(localized: "⌃ Control")
        }
    }
    var symbol: String { String(label.prefix(1)) }
}

enum HotkeyKey: Int, CaseIterable, Identifiable {
    case tab = 48, grave = 50, space = 49
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .tab: String(localized: "Tab ⇥")
        case .grave: String(localized: "Key above Tab (\\ or `)")
        case .space: String(localized: "Space")
        }
    }
    var short: String {
        switch self {
        case .tab: "Tab"
        case .grave: "\\"
        case .space: String(localized: "Space")
        }
    }
}

enum Settings {
    static let defaultPreviewWidth = 220.0
    private static var d: UserDefaults { .standard }

    static var previewWidth: CGFloat {
        CGFloat(d.object(forKey: Pref.previewWidth) as? Double ?? defaultPreviewWidth)
    }
    static var notificationStyle: NotificationStyleKind {
        NotificationStyleKind(rawValue: d.string(forKey: Pref.notificationStyle) ?? "") ?? .toolbox
    }
    static var centerNotifications: Bool { d.object(forKey: Pref.centerNotifications) as? Bool ?? true }
    static var notificationDropAnimation: Bool { d.object(forKey: Pref.notificationDropAnimation) as? Bool ?? true }
    static var ctrlShortcuts: Bool { d.object(forKey: Pref.ctrlShortcuts) as? Bool ?? true }
    static var textKeys: Bool { d.object(forKey: Pref.textKeys) as? Bool ?? true }
    static var rightCommandAltGr: Bool { d.object(forKey: Pref.rightCommandAltGr) as? Bool ?? true }
    static var capsLockAccents: Bool { d.object(forKey: Pref.capsLockAccents) as? Bool ?? true }
    static var showDesktopShake: Bool { d.object(forKey: Pref.showDesktopShake) as? Bool ?? true }
    static var showDesktopKey: Bool { d.object(forKey: Pref.showDesktopKey) as? Bool ?? true }
    static var showDesktopMinimizes: Bool { d.object(forKey: Pref.showDesktopMinimizes) as? Bool ?? true }
    static var aeroShake: Bool { d.object(forKey: Pref.aeroShake) as? Bool ?? true }
    static var toolboxInDock: Bool { d.object(forKey: Pref.toolboxInDock) as? Bool ?? true }
    /// Apps that stay open even when their last window is closed (e.g. WhatsApp, to keep receiving messages)
    static var quitExclusions: [String] {
        get { d.stringArray(forKey: Pref.quitExclusions) ?? ["net.whatsapp.WhatsApp"] }
        set { d.set(newValue, forKey: Pref.quitExclusions) }
    }
    static var finderKeys: Bool { d.object(forKey: Pref.finderKeys) as? Bool ?? true }
    static var screenSnip: Bool { d.object(forKey: Pref.screenSnip) as? Bool ?? true }
    static var dockPreviews: Bool { d.object(forKey: Pref.dockPreviews) as? Bool ?? true }
    static var dockPreviewWidth: Double { d.object(forKey: Pref.dockPreviewWidth) as? Double ?? 240 }
    static var quitOnLastWindow: Bool { d.object(forKey: Pref.quitOnLastWindow) as? Bool ?? true }
    static var powerButton: Bool { d.object(forKey: Pref.powerButton) as? Bool ?? true }
    static var dockMinimize: Bool { d.object(forKey: Pref.dockMinimize) as? Bool ?? true }
    static var minimizeIntoAppIcon: Bool { d.object(forKey: Pref.minimizeIntoAppIcon) as? Bool ?? true }
    static var dockMinimizeScope: DockMinimizeScope {
        DockMinimizeScope(rawValue: d.string(forKey: Pref.dockMinimizeScope) ?? "") ?? .allWindows
    }
    static var backgroundPreviews: Bool { d.object(forKey: Pref.backgroundPreviews) as? Bool ?? true }
    static var closeButtonQuitsApp: Bool { d.bool(forKey: Pref.closeButtonQuitsApp) }
    static var showOtherDesktops: Bool { d.object(forKey: Pref.showOtherDesktops) as? Bool ?? true }
    static var showMinimized: Bool { d.object(forKey: Pref.showMinimized) as? Bool ?? true }
    static var titleOnTop: Bool { d.object(forKey: Pref.titleOnTop) as? Bool ?? true }
    static var modifier: HotkeyModifier {
        HotkeyModifier(rawValue: d.string(forKey: Pref.switcherModifier) ?? "") ?? .command
    }
    static var key: HotkeyKey {
        HotkeyKey(rawValue: d.object(forKey: Pref.switcherKey) as? Int ?? -1) ?? .tab
    }
}
