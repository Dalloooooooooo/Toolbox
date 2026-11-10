import Cocoa

/// Turns Ctrl+letter into the corresponding ⌘+letter (Ctrl+C → ⌘C, etc.).
enum CtrlShortcuts {
    struct Mapping {
        let key: Int64          // code of the pressed key (physical position, QWERTY)
        let label: String
        let toKey: Int64
        let addShift: Bool
        var letter: String { ["8": "c", "9": "v", "7": "x", "0": "a", "6": "z", "1": "s", "3": "f"]["\(toKey)"] ?? "" }
    }

    static let mappings: [Mapping] = [
        Mapping(key: 8, label: String(localized: "Ctrl+C → Copy"), toKey: 8, addShift: false),
        Mapping(key: 9, label: String(localized: "Ctrl+V → Paste"), toKey: 9, addShift: false),
        Mapping(key: 7, label: String(localized: "Ctrl+X → Cut"), toKey: 7, addShift: false),
        Mapping(key: 0, label: String(localized: "Ctrl+A → Select All"), toKey: 0, addShift: false),
        Mapping(key: 6, label: String(localized: "Ctrl+Z → Undo"), toKey: 6, addShift: false),
        Mapping(key: 16, label: String(localized: "Ctrl+Y → Redo"), toKey: 6, addShift: true), // on the Mac it's ⌘⇧Z
        Mapping(key: 1, label: String(localized: "Ctrl+S → Save"), toKey: 1, addShift: false),
        Mapping(key: 3, label: String(localized: "Ctrl+F → Find"), toKey: 3, addShift: false),
    ]

    /// In terminals Ctrl+C means "interrupt": we leave them alone.
    static let excludedApps: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "net.kovidgoyal.kitty",
        "org.alacritty", "io.alacritty", "com.mitchellh.ghostty", "co.zeit.hyper", "com.github.wez.wezterm",
    ]

    /// Mark on the events we generate ourselves, so our tap doesn't process them again.
    static let marker: Int64 = 0x7B0C5
    private static let leftCtrl: UInt64 = 0x1, rightCtrl: UInt64 = 0x2000, leftCmd: UInt64 = 0x8, leftShift: UInt64 = 0x2
    private static let ctrlKey: CGKeyCode = 59, rightCtrlKey: CGKeyCode = 62, cmdKey: CGKeyCode = 55, shiftKey: CGKeyCode = 56

    /// Shortcut in progress (key pressed with Ctrl and turned into ⌘).
    private static var active: Mapping?
    /// Real state of the physical Ctrl key (we modify the "system" state ourselves during the shortcut).
    private static var physicalCtrlDown = false

    /// To recognize menu shortcuts macOS doesn't look at the event but at the *hardware* state of the
    /// modifiers. So changing the flags isn't enough: instead of Ctrl+C we send, at the hardware level,
    /// "Ctrl up → ⌘ down → C", and on release "C up → ⌘ up → Ctrl down" (if Ctrl is still really held).
    /// Returns true if the original event must be discarded.
    static func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        guard event.getIntegerValueField(.eventSourceUserData) != marker else { return false }
        let key = event.getIntegerValueField(.keyboardEventKeycode)

        switch type {
        case .flagsChanged:
            if key == Int64(ctrlKey) || key == Int64(rightCtrlKey) {
                physicalCtrlDown = event.flags.contains(.maskControl)
                // Ctrl released before the letter: end the shortcut right away
                if !physicalCtrlDown, let m = active { releaseCommand(m, restoreCtrl: false); active = nil }
            }
            return false

        case .keyDown:
            if let m = active, m.key == key { // auto-repeat of the held key
                post(key: m.toKey, down: true, flags: commandFlags(m), letter: m.letter, autorepeat: 1)
                return true
            }
            let flags = event.flags
            guard Settings.ctrlShortcuts, active == nil, flags.contains(.maskControl),
                  !flags.contains(.maskCommand), !flags.contains(.maskAlternate),
                  let m = mappings.first(where: { $0.key == key }),
                  !excludedApps.contains(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "")
            else { return false }
            physicalCtrlDown = true
            active = m
            postModifier(ctrlKey, down: false, flags: [])
            postModifier(cmdKey, down: true, flags: CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | leftCmd))
            if m.addShift { postModifier(shiftKey, down: true, flags: commandFlags(m)) }
            post(key: m.toKey, down: true, flags: commandFlags(m), letter: m.letter, autorepeat: 0)
            return true

        case .keyUp:
            guard let m = active, m.key == key else { return false }
            post(key: m.toKey, down: false, flags: commandFlags(m), letter: m.letter, autorepeat: 0)
            releaseCommand(m, restoreCtrl: physicalCtrlDown)
            active = nil
            return true

        default:
            return false
        }
    }

    private static func commandFlags(_ m: Mapping) -> CGEventFlags {
        var f = CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | leftCmd)
        if m.addShift { f.formUnion(CGEventFlags(rawValue: CGEventFlags.maskShift.rawValue | leftShift)) }
        return f
    }

    private static func releaseCommand(_ m: Mapping, restoreCtrl: Bool) {
        if m.addShift { postModifier(shiftKey, down: false, flags: CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | leftCmd)) }
        postModifier(cmdKey, down: false, flags: [])
        if restoreCtrl { postModifier(ctrlKey, down: true, flags: CGEventFlags(rawValue: CGEventFlags.maskControl.rawValue | leftCtrl)) }
    }

    private static let source = CGEventSource(stateID: .hidSystemState)

    private static func post(key: Int64, down: Bool, flags: CGEventFlags, letter: String, autorepeat: Int64) {
        guard let e = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(key), keyDown: down) else { return }
        e.flags = flags
        let chars = Array(letter.utf16)
        e.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: chars)
        // undocumented fields with the character code (77: with modifiers, 78: without).
        // macOS computes them when the event is created, while Ctrl is still pressed, and stores the
        // control character (e.g. 3 for Ctrl+C): menus use exactly these, so we fix them.
        let code = Int64(letter.unicodeScalars.first?.value ?? 0)
        let shifted = flags.contains(.maskShift) ? Int64(letter.uppercased().unicodeScalars.first?.value ?? 0) : code
        if let charField = CGEventField(rawValue: 77), let plainField = CGEventField(rawValue: 78) {
            e.setIntegerValueField(charField, value: shifted)
            e.setIntegerValueField(plainField, value: code)
        }
        e.setIntegerValueField(.keyboardEventAutorepeat, value: autorepeat)
        e.setIntegerValueField(.eventSourceUserData, value: marker)
        send(e)
    }

    /// Events must be posted after the tap is done with the original key (queued on the main thread,
    /// so the order stays correct): posted from inside the tap, apps don't recognize them as shortcuts.
    private static func send(_ e: CGEvent) {
        // undocumented field 80: macOS adds bit 0x10 to events posted by an app that has an active
        // event tap, and with that bit apps don't trigger menu shortcuts. We clear it.
        if let field = CGEventField(rawValue: 80) {
            e.setIntegerValueField(field, value: e.getIntegerValueField(field) & ~0x10)
        }
        DispatchQueue.main.async { e.post(tap: .cghidEventTap) }
    }

    /// Press or release of a modifier. It must be created as a real "down"/"up": macOS tracks the key
    /// state from this, not from the event type (otherwise Ctrl would stay "pressed").
    private static func postModifier(_ key: CGKeyCode, down: Bool, flags: CGEventFlags) {
        guard let e = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down) else { return }
        e.flags = flags
        e.setIntegerValueField(.eventSourceUserData, value: marker)
        send(e)
    }
}
