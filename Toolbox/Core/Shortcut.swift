import Cocoa

/// A shortcut chosen by the user: a key or a mouse button, with modifiers; or modifiers alone / a mouse button
/// to hold down (for gestures such as the shake that shows the desktop). Recorded with `ShortcutField`.
/// ⌥ and ⌘ remember the side when it matters (left ⌥ is the Windows key, right ⌘ is AltGr).
struct Shortcut: Codable, Equatable {
    enum Side: String, Codable { case none, either, left, right }
    /// `press`: a key or button pressed once. `hold`: modifiers or a mouse button kept down.
    enum Mode { case press, hold }

    var keyCode: Int?
    var mouseButton: Int?     // CGEvent numbering: 1 right, 2 middle, 3… side buttons
    var shift = false
    var control = false
    var option: Side = .none
    var command: Side = .none

    var hasModifiers: Bool { shift || control || option != .none || command != .none }

    // MARK: Matching

    func modifiersMatch(_ f: CGEventFlags) -> Bool {
        func side(_ s: Side, _ on: Bool, left: UInt64, right: UInt64) -> Bool {
            switch s {
            case .none: !on
            case .either: on
            case .left: on && f.rawValue & left != 0
            case .right: on && f.rawValue & right != 0
            }
        }
        return f.contains(.maskShift) == shift && f.contains(.maskControl) == control
            && side(option, f.contains(.maskAlternate), left: 0x20, right: 0x40)
            && side(command, f.contains(.maskCommand), left: 0x08, right: 0x10)
    }

    func matches(key: Int64, flags: CGEventFlags) -> Bool {
        keyCode.map { Int64($0) == key || Self.sameKey(Int64($0), key) } == true && mouseButton == nil && modifiersMatch(flags)
    }

    func matches(button: Int64, flags: CGEventFlags) -> Bool {
        mouseButton.map { Int64($0) == button } == true && keyCode == nil && modifiersMatch(flags)
    }

    /// Modifiers alone, held down right now.
    func isHeld(_ flags: CGEventFlags) -> Bool { keyCode == nil && mouseButton == nil && hasModifiers && modifiersMatch(flags) }

    /// The key above Tab and the one next to left ⇧ swap places on some ISO keyboards.
    private static func sameKey(_ a: Int64, _ b: Int64) -> Bool { Set([a, b]) == [10, 50] }

    /// The modifiers of an event (side recorded for ⌥ and ⌘).
    static func modifiers(_ f: CGEventFlags) -> Shortcut {
        var s = Shortcut()
        s.shift = f.contains(.maskShift)
        s.control = f.contains(.maskControl)
        if f.contains(.maskAlternate) { s.option = f.rawValue & 0x40 != 0 ? .right : .left }
        if f.contains(.maskCommand) { s.command = f.rawValue & 0x10 != 0 ? .right : .left }
        return s
    }

    // MARK: Showing it

    var display: String {
        var parts: [String] = []
        if control { parts.append("⌃") }
        if option != .none { parts.append(Self.sided("⌥", option)) }
        if shift { parts.append("⇧") }
        if command != .none { parts.append(Self.sided("⌘", command)) }
        if let k = keyCode { parts.append(Self.keyName(k)) }
        if let b = mouseButton { parts.append(Self.buttonName(b)) }
        return parts.isEmpty ? String(localized: "None") : parts.joined(separator: " + ")
    }

    private static func sided(_ symbol: String, _ s: Side) -> String {
        switch s {
        case .left: String(localized: "left \(symbol)")
        case .right: String(localized: "right \(symbol)")
        default: symbol
        }
    }

    static let functionKeys: [Int: String] = [
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10",
        103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20",
    ]
    private static let specialKeys: [Int: String] = [
        36: "↩", 76: "⌤", 48: "⇥", 49: String(localized: "Space"), 51: "⌫", 117: "⌦", 53: "Esc",
        123: "←", 124: "→", 125: "↓", 126: "↑", 115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
    ]

    /// Keys that type nothing: they can be a shortcut on their own (F5, Home…).
    static func isNonTyping(_ k: Int) -> Bool { functionKeys[k] != nil || specialKeys[k] != nil }

    static func keyName(_ k: Int) -> String {
        if let n = functionKeys[k] ?? specialKeys[k] { return n }
        if k == 10 || k == 50 { return String(localized: "the key above Tab") }
        return KeyboardLayout.character(for: Int64(k), shift: false)?.uppercased() ?? "#\(k)"
    }

    static func buttonName(_ b: Int) -> String {
        switch b {
        case 1: String(localized: "right click")
        case 2: String(localized: "middle mouse button")
        default: String(localized: "mouse button \(b + 1)")
        }
    }

    // MARK: Saved in the preferences (JSON)

    static func load(_ pref: String, default d: Shortcut) -> Shortcut {
        guard let data = UserDefaults.standard.data(forKey: pref),
              let s = try? JSONDecoder().decode(Shortcut.self, from: data) else { return d }
        return s
    }

    func save(_ pref: String) {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: pref) }
    }
}

/// The shortcuts that can be changed, with their defaults.
extension Shortcut {
    static let defaultShakeHold = Shortcut(shift: true)
    static let defaultShowDesktop = Shortcut(keyCode: 2, option: .left)                    // left ⌥ + D (Win+D)
    static let defaultZoneEditor = Shortcut(keyCode: 50, shift: true, option: .left)       // left ⌥ ⇧ + key above Tab
    static let defaultScreenSnip = Shortcut(keyCode: 1, shift: true, option: .either)      // ⌥ ⇧ S (Win+Shift+S)

    static var shakeHold: Shortcut { load(Pref.showDesktopShakeHold, default: defaultShakeHold) }
    static var showDesktop: Shortcut { load(Pref.showDesktopShortcut, default: defaultShowDesktop) }
    static var zoneEditor: Shortcut { load(Pref.zonesEditorShortcut, default: defaultZoneEditor) }
    static var screenSnip: Shortcut { load(Pref.screenSnipShortcut, default: defaultScreenSnip) }
}
