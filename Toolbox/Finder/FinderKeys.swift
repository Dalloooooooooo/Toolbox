import Cocoa

/// Return opens, F2 renames, Delete moves to the Trash (⌫ too on the desktop), ⌫ goes back, Ctrl/⌘+X then Ctrl/⌘+V moves files.
/// Instead of simulating keys, we "click" the Finder's menu items: the Finder itself does all the work
/// (progress windows, name conflicts, Undo…). While renaming or typing, the keys behave normally.
@MainActor
enum FinderKeys {
    private static let finderID = "com.apple.finder"
    private static var swallowUp = Set<Int64>()
    /// Clipboard state at the time of the "cut": if it hasn't changed when you paste, files are moved instead of copied.
    private static var cutChangeCount: Int?

    // key codes
    private static let ret: Int64 = 36, enter: Int64 = 76, f2: Int64 = 120, fwdDelete: Int64 = 117
    private static let backspace: Int64 = 51, x: Int64 = 7, v: Int64 = 9

    nonisolated static func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        guard type == .keyDown || type == .keyUp,
              event.getIntegerValueField(.eventSourceUserData) != CtrlShortcuts.marker else { return false }
        return MainActor.assumeIsolated { process(type, event) }
    }

    private static func process(_ type: CGEventType, _ event: CGEvent) -> Bool {
        let key = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .keyUp {
            return swallowUp.remove(key) != nil
        }
        guard Settings.finderKeys,
              NSWorkspace.shared.frontmostApplication?.bundleIdentifier == finderID else { return false }
        let f = event.flags
        let cmd = f.contains(.maskCommand), ctrl = f.contains(.maskControl)
        let alt = f.contains(.maskAlternate), shift = f.contains(.maskShift)
        let plain = !cmd && !ctrl && !alt && !shift
        let shortcut = (cmd != ctrl) && !alt && !shift // ⌘ or Ctrl (like Windows), on their own

        // only the keys we care about, so we don't query the Finder on every letter
        let relevant = (plain && [ret, enter, f2, fwdDelete, backspace].contains(key))
            || (shift && !cmd && !ctrl && !alt && key == fwdDelete)
            || (shortcut && (key == x || key == v))
        // renaming a file or typing in the search field: the keys work as usual
        guard relevant, !TextKeys.isEditingText(fieldsOnly: true) else { return false }

        switch key {
        case ret, enter:
            return press(char: "O", mods: 0, key: key)                 // File › Open
        case f2:
            return press(titles: ["Rinomina", "Rename"], key: key)     // File › Rename
        case fwdDelete:
            return press(char: "\u{8}", mods: shift ? 2 : 0, key: key)  // Move to Trash / Delete Immediately…
        case backspace:
            // on the desktop there's nothing to go back to: the Mac's delete key (⌫) works like Windows' Del there
            if onDesktop() { return press(char: "\u{8}", mods: 0, key: key) } // Move to Trash
            return press(titles: ["Indietro", "Back"], key: key)         // Go › Back
        case x:
            guard press(char: "C", mods: 0, key: key) else { return false } // copy, and remember it's a "cut"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { cutChangeCount = NSPasteboard.general.changeCount }
            return true
        case v:
            guard let cut = cutChangeCount, cut == NSPasteboard.general.changeCount else { return false }
            cutChangeCount = nil
            return press(char: "V", mods: 2, key: key)                 // Edit › Move Item Here
        default:
            return false
        }
    }

    // MARK: Finder menu items

    /// Finds the menu item with that shortcut (character + modifiers: 0 = ⌘, 2 = ⌘⌥) and "clicks" it.
    private static func press(char: String, mods: Int, key: Int64) -> Bool {
        guard let item = menuItem(where: { item in
            (attr(item, "AXMenuItemCmdChar") as? String)?.uppercased() == char.uppercased()
                && (attr(item, "AXMenuItemCmdModifiers") as? Int) == mods
        }) else { return false }
        swallowUp.insert(key)
        DispatchQueue.main.async { AXUIElementPerformAction(item, kAXPressAction as CFString) }
        return true
    }

    /// By title (Italian and English): "Rename" has no shortcut, and "Back" uses the character of the
    /// layout's [ key (on the Italian layout, "ò").
    private static func press(titles: [String], key: Int64) -> Bool {
        guard let item = menuItem(where: { el in
            let t = attr(el, kAXTitleAttribute) as? String ?? ""
            return titles.contains { t == $0 || t.hasPrefix($0 + "…") }
        }) else { return false }
        swallowUp.insert(key)
        DispatchQueue.main.async { AXUIElementPerformAction(item, kAXPressAction as CFString) }
        return true
    }

    private static func menuItem(where match: (AXUIElement) -> Bool) -> AXUIElement? {
        guard let finder = NSRunningApplication.runningApplications(withBundleIdentifier: finderID).first,
              let bar = attr(AXUIElementCreateApplication(finder.processIdentifier), kAXMenuBarAttribute) else { return nil }
        for top in attr(bar as! AXUIElement, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
            guard let menu = (attr(top, kAXChildrenAttribute) as? [AXUIElement])?.first else { continue }
            for item in attr(menu, kAXChildrenAttribute) as? [AXUIElement] ?? [] where match(item) {
                return item // the "enabled" state may be stale: the Finder checks it again when we press it
            }
        }
        return nil
    }

    /// The desktop has the focus (it is a Finder "window" without the window: no focused window).
    private static func onDesktop() -> Bool {
        guard let finder = NSRunningApplication.runningApplications(withBundleIdentifier: finderID).first else { return false }
        return attr(AXUIElementCreateApplication(finder.processIdentifier), kAXFocusedWindowAttribute) == nil
    }

    private static func attr(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success ? v : nil
    }
}
