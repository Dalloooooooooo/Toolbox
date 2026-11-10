import Cocoa

/// Snapping shortcuts, from the event tap. Left ⌥ alone (or with ⇧) + arrows/Z.
enum SnapKeys {
    private static var swallowUp: Int64?

    static func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        let key = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .keyUp {
            if swallowUp == key { swallowUp = nil; return true }
            return false
        }
        guard type == .keyDown, SnapSettings.enabled, SnapSettings.keys else { return false }
        let flags = event.flags
        let leftOption = flags.rawValue & 0x20 != 0
        guard flags.contains(.maskAlternate), leftOption,
              !flags.contains(.maskCommand), !flags.contains(.maskControl) else { return false }
        let shift = flags.contains(.maskShift)
        let arrow: WindowSnap.Arrow?
        switch key {
        case 123: arrow = .left
        case 124: arrow = .right
        case 126: arrow = .up
        case 125: arrow = .down
        case 6 where !shift: arrow = nil // Z
        default: return false
        }
        swallowUp = key
        if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return true } // held down: only once
        DispatchQueue.main.async {
            if let arrow { WindowSnap.shared.arrow(arrow, shift: shift) } else { WindowSnap.shared.showLayoutsForFocusedWindow() }
        }
        return true
    }
}
