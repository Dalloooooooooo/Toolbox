import Cocoa

// MARK: - System shortcuts (native ⌘Tab)

@_silgen_name("CGSSetSymbolicHotKeyEnabled")
private func CGSSetSymbolicHotKeyEnabled(_ hotKey: Int32, _ enabled: Bool) -> CGError

enum SystemHotkeys {
    private static let commandTab: Int32 = 1, commandShiftTab: Int32 = 2, commandKeyAboveTab: Int32 = 6

    /// Disables the system switcher only if our shortcut overrides it.
    static func sync() {
        let cmd = Settings.modifier == .command
        _ = CGSSetSymbolicHotKeyEnabled(commandTab, !(cmd && Settings.key == .tab))
        _ = CGSSetSymbolicHotKeyEnabled(commandShiftTab, !(cmd && Settings.key == .tab))
        _ = CGSSetSymbolicHotKeyEnabled(commandKeyAboveTab, !(cmd && Settings.key == .grave))
        // Ctrl+←/→ are used for words: switching desktops moves to Ctrl+⌘+←/→ (see TextKeys)
        for k in TextKeys.spaceHotkeys { _ = CGSSetSymbolicHotKeyEnabled(k, !Settings.textKeys) }
    }

    static func setEnabled(_ hotkey: Int32, _ enabled: Bool) { _ = CGSSetSymbolicHotKeyEnabled(hotkey, enabled) }

    static func restoreAll() {
        for k in [commandTab, commandShiftTab, commandKeyAboveTab] + TextKeys.spaceHotkeys {
            _ = CGSSetSymbolicHotKeyEnabled(k, true)
        }
    }
}
