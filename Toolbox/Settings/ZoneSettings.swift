import Cocoa
import SwiftUI

enum ZoneSettings {
    private static let d = UserDefaults.standard
    private static func flag(_ k: String, _ def: Bool = true) -> Bool { d.object(forKey: k) as? Bool ?? def }
    static var enabled: Bool { flag(Pref.zonesEnabled) }
    static var holdShift: Bool { flag(Pref.zonesHoldShift) }
    static var allMonitors: Bool { flag(Pref.zonesAllMonitors, false) }
    static var showNumbers: Bool { flag(Pref.zonesShowNumbers) }
    static var opacity: Double { d.object(forKey: Pref.zonesOpacity) as? Double ?? 0.5 }
    static var overrideKeys: Bool { flag(Pref.zonesOverrideKeys, false) }
    static var keysByPosition: Bool { flag(Pref.zonesKeysByPosition, false) }
    static var quickSwitch: Bool { flag(Pref.zonesQuickSwitch) }
    static var flash: Bool { flag(Pref.zonesFlash) }
    static var assist: Bool { flag(Pref.zonesAssist) }
    /// Apps whose windows never snap to zones (bundle identifiers).
    static var excludedApps: [String] {
        get { d.stringArray(forKey: Pref.zonesExcludedApps) ?? [] }
        set { d.set(newValue, forKey: Pref.zonesExcludedApps) }
    }
    static func isExcluded(pid: pid_t) -> Bool {
        let list = excludedApps
        guard !list.isEmpty, let id = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier else { return false }
        return list.contains(id)
    }
    /// Highlight color (hex "#RRGGBB"); the system accent color if not chosen.
    static var highlightColor: NSColor {
        guard let hex = d.string(forKey: Pref.zonesHighlightColor), let c = Color(hex: hex) else { return .controlAccentColor }
        return NSColor(c)
    }
}
