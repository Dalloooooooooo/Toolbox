import Cocoa

/// Shortcuts recorded as a mouse button (middle, side buttons, or right click with a modifier).
enum MouseShortcuts {
    private static var swallowUp: Int64?

    static func handle(_ type: CGEventType, button: Int64, flags: CGEventFlags) -> Bool {
        if ShowDesktop.mouse(type, button: button, flags: flags) { return true }
        let down = type == .otherMouseDown || type == .rightMouseDown
        if !down { defer { if swallowUp == button { swallowUp = nil } }; return swallowUp == button }
        let actions: [(Shortcut, Bool, () -> Void)] = [
            (Shortcut.zoneEditor, ZoneSettings.enabled, { ZoneEditor.shared.show() }),
            (Shortcut.screenSnip, Settings.screenSnip, { MainActor.assumeIsolated { ScreenSnip.start() } }),
        ]
        for (shortcut, enabled, run) in actions where enabled && shortcut.matches(button: button, flags: flags) {
            swallowUp = button
            DispatchQueue.main.async(execute: run)
            return true
        }
        return false
    }
}
