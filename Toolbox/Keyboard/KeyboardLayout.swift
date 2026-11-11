import Cocoa
import Carbon

// MARK: - Keyboard layout

enum KeyboardLayout {
    /// The "Italian – Pro" layout (similar to the PC keyboard). In recent macOS versions it's just called "Italian".
    static let italianPro = "com.apple.keylayout.Italian-Pro"

    struct Info: Identifiable, Equatable {
        let id: String
        let name: String
    }

    static var current: Info { info(TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue()) }

    /// Enabled keyboard layouts (the ones shown in the 🌐 menu).
    static var enabled: [Info] {
        let filter = [kTISPropertyInputSourceType as String: kTISTypeKeyboardLayout as String] as CFDictionary
        let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource] ?? []
        return list.map(info)
    }

    /// Enables and selects Italian – Pro.
    @discardableResult
    static func useItalianPro() -> Bool {
        guard let src = source(italianPro) else { return false }
        TISEnableInputSource(src)
        return TISSelectInputSource(src) == noErr
    }

    /// Removes a layout from the 🌐 menu (it can be added back in System Settings → Keyboard).
    static func disable(_ id: String) {
        guard id != current.id, let src = source(id) else { return }
        TISDisableInputSource(src)
    }

    /// The character the current layout types for a key, with or without ⇧ and ⌥ (ignoring Caps Lock).
    static func character(for key: Int64, shift: Bool, option: Bool = false) -> String? {
        guard let src = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(src, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue()
        var dead: UInt32 = 0, len = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let mods = UInt32((option ? optionKey : 0) | (shift ? shiftKey : 0)) >> 8
        let status = CFDataGetBytePtr(data).withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) {
            UCKeyTranslate($0, UInt16(key), UInt16(kUCKeyActionDown), mods & 0xFF, UInt32(LMGetKbdType()),
                           OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, 4, &len, &chars)
        }
        return status == noErr ? String(utf16CodeUnits: chars, count: len) : nil
    }

    private static func source(_ id: String) -> TISInputSource? {
        let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
        return (TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource])?.first
    }

    private static func info(_ s: TISInputSource) -> Info {
        Info(id: prop(s, kTISPropertyInputSourceID), name: prop(s, kTISPropertyLocalizedName))
    }

    private static func prop(_ s: TISInputSource, _ key: CFString) -> String {
        guard let p = TISGetInputSourceProperty(s, key) else { return "" }
        return Unmanaged<CFString>.fromOpaque(p).takeUnretainedValue() as String
    }
}
