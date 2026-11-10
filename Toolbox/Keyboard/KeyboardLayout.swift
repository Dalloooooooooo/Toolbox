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
