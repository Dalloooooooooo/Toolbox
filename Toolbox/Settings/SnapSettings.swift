import Cocoa

/// Which zones Snap Assist asks about after a window is snapped.
enum AssistMode: String, CaseIterable, Identifiable {
    case every, empty, never
    var id: String { rawValue }

    var label: String {
        switch self {
        case .every: String(localized: "In every other zone")
        case .empty: String(localized: "Only in empty zones")
        case .never: String(localized: "Never")
        }
    }

    /// The saved choice; before there was one, the old on/off switch (off = never).
    static func read(_ key: String, old: String) -> AssistMode {
        let d = UserDefaults.standard
        if let raw = d.string(forKey: key), let m = AssistMode(rawValue: raw) { return m }
        return d.object(forKey: old) as? Bool == false ? .never : .every
    }
}

enum SnapSettings {
    private static let d = UserDefaults.standard
    private static func flag(_ k: String) -> Bool { d.object(forKey: k) as? Bool ?? true }
    static var enabled: Bool { flag(Pref.snapEnabled) }
    static var assist: AssistMode { AssistMode.read(Pref.snapAssistMode, old: Pref.snapAssist) }
    static var linkedResize: Bool { flag(Pref.snapLinkedResize) }
    static var layoutBar: Bool { flag(Pref.snapLayoutBar) }
    static var nearEdge: Bool { flag(Pref.snapNearEdge) }
    static var keys: Bool { flag(Pref.snapKeys) }
    static var greenButton: Bool { flag(Pref.greenButtonMaximizes) }
    static var animate: Bool { flag(Pref.snapAnimate) }
}
