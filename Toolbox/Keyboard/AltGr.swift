import Cocoa
import Carbon

/// Right ⌘ + ò → @, à → #, è → [ {, + → ] }, e → € (like AltGr on the Windows Italian keyboard).
/// The character is the one the current layout produces with ⌥ (Option); the event is rewritten with ⌥ instead of ⌘.
enum AltGr {
    /// Keys by physical position (Italian keyboard): ò, à, è, +, e
    static let keys: Set<Int64> = [41, 39, 33, 30, 14]
    static let rows: [(String, String)] = [
        (String(localized: "Right ⌘ + ò"), "@"), (String(localized: "Right ⌘ + à"), "#"),
        (String(localized: "Right ⌘ + è  /  + Shift"), "[  {"),
        (String(localized: "Right ⌘ + +  /  + Shift"), "]  }"), (String(localized: "Right ⌘ + e"), "€"),
    ]
    private static let rightCmdBit: UInt64 = 0x10, leftCmdBit: UInt64 = 0x08
    private static var pressed: [Int64: (flags: CGEventFlags, text: String)] = [:]

    static func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        guard type == .keyDown || type == .keyUp,
              event.getIntegerValueField(.eventSourceUserData) != CtrlShortcuts.marker else { return false }
        let key = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .keyUp {
            if let p = pressed.removeValue(forKey: key) { rewrite(event, p.flags, p.text) }
            return false
        }
        if let p = pressed[key] { rewrite(event, p.flags, p.text); return false } // key repeat
        let raw = event.flags.rawValue
        guard Settings.rightCommandAltGr, keys.contains(key), raw & rightCmdBit != 0, raw & leftCmdBit == 0,
              !event.flags.contains(.maskControl), !event.flags.contains(.maskAlternate) else { return false }
        let shift = event.flags.contains(.maskShift)
        guard let text = character(for: key, shift: shift), !text.isEmpty else { return false }
        let flags = CGEventFlags(rawValue: (raw & ~(CGEventFlags.maskCommand.rawValue | rightCmdBit))
                                 | CGEventFlags.maskAlternate.rawValue | 0x40) // 0x40 = right ⌥
        pressed[key] = (flags, text)
        rewrite(event, flags, text)
        return false
    }

    private static func rewrite(_ e: CGEvent, _ flags: CGEventFlags, _ text: String) {
        e.flags = flags
        let chars = Array(text.utf16)
        e.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: chars)
    }

    /// The character the current keyboard layout produces with ⌥ (+ Shift).
    private static func character(for key: Int64, shift: Bool) -> String? {
        guard let src = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(src, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue()
        var dead: UInt32 = 0, len = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let mods = UInt32(optionKey | (shift ? shiftKey : 0)) >> 8
        let status = CFDataGetBytePtr(data).withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) {
            UCKeyTranslate($0, UInt16(key), UInt16(kUCKeyActionDown), mods & 0xFF, UInt32(LMGetKbdType()),
                           OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, 4, &len, &chars)
        }
        return status == noErr ? String(utf16CodeUnits: chars, count: len) : nil
    }
}
