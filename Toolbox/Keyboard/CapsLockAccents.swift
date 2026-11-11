import Cocoa

/// With Caps Lock on, the accented letters of the Italian keyboard become capitals too:
/// è → È, é → É (⇧ + è), ò → Ò, à → À, ù → Ù, ì → Ì. On a Mac Caps Lock leaves them lowercase.
/// The key event goes through unchanged, only with the capital letter as its text.
enum CapsLockAccents {
    private static let capitals: [String: String] = ["è": "È", "é": "É", "ò": "Ò", "à": "À", "ù": "Ù", "ì": "Ì"]
    static let rows: [(String, String)] = [("è  é", "È  É"), ("ò", "Ò"), ("à", "À"), ("ù", "Ù"), ("ì", "Ì")]

    static func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        guard type == .keyDown || type == .keyUp, Settings.capsLockAccents else { return false }
        let flags = event.flags
        guard flags.contains(.maskAlphaShift), !flags.contains(.maskCommand), !flags.contains(.maskControl),
              !flags.contains(.maskAlternate) else { return false }
        let key = event.getIntegerValueField(.keyboardEventKeycode)
        guard let typed = KeyboardLayout.character(for: key, shift: flags.contains(.maskShift)),
              let capital = capitals[typed] else { return false }
        let chars = Array(capital.utf16)
        event.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: chars)
        return false // not swallowed: it continues, with the capital letter
    }
}
