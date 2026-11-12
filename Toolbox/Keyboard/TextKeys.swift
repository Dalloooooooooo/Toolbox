import Cocoa

/// Cursor movement, selection and deletion like on Windows:
/// Ctrl+←/→ (word), Ctrl+⌫ / Ctrl+Delete (delete word), Home/End (start/end of line),
/// Ctrl+Home/End (start/end of document); always also with Shift to select.
/// The event is rewritten on the fly with the equivalent Mac keys (⌥ for words, ⌘ for lines and document).
enum TextKeys {
    static let left: Int64 = 123, right: Int64 = 124, down: Int64 = 125, up: Int64 = 126
    static let backspace: Int64 = 51, forwardDelete: Int64 = 117, home: Int64 = 115, end: Int64 = 119
    private static let w: Int64 = 13

    struct Row: Identifiable { let id = UUID(); let windows: String; let action: String }
    static let rows: [Row] = [
        Row(windows: "Ctrl + ← / →", action: String(localized: "Previous / next word")),
        Row(windows: String(localized: "Ctrl + ⌫  /  Shift + ⌫"), action: String(localized: "Delete the word to the left")),
        Row(windows: String(localized: "Ctrl + Delete (fn ⌫)"), action: String(localized: "Delete the word to the right")),
        Row(windows: String(localized: "Home / End (fn ← / →)"), action: String(localized: "Start / end of the line")),
        Row(windows: String(localized: "Ctrl + Home / End"), action: String(localized: "Start / end of the text")),
        Row(windows: String(localized: "Shift + ← / →"), action: String(localized: "Select one letter at a time")),
        Row(windows: String(localized: "Ctrl + Shift + ← / →"), action: String(localized: "Select one word at a time")),
        Row(windows: String(localized: "Shift + Home / End"), action: String(localized: "Select to the start / end of the line")),
        Row(windows: "Ctrl + ⌘ + ← / →", action: String(localized: "Previous / next desktop")),
    ]

    /// Keys rewritten on keyDown, so keyUp is rewritten the same way.
    private static var pressed: [Int64: (key: Int64, flags: CGEventFlags)] = [:]
    private static let ctrlBits = CGEventFlags.maskControl.rawValue | 0x1 | 0x2000
    private static let leftAlt = CGEventFlags(rawValue: CGEventFlags.maskAlternate.rawValue | 0x20)
    private static let leftCmd = CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | 0x8)

    /// Modifies the event in place. Returns true if the event must be discarded.
    static func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        guard type == .keyDown || type == .keyUp,
              event.getIntegerValueField(.eventSourceUserData) != CtrlShortcuts.marker else { return false }
        let key = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .keyUp {
            if let r = pressed.removeValue(forKey: key) { rewrite(event, r.key, r.flags) }
            return key == left || key == right ? swallowedSpaceKeys.remove(key) != nil : false
        }
        if event.getIntegerValueField(.keyboardEventAutorepeat) != 0, let r = pressed[key] {
            rewrite(event, r.key, r.flags); return false
        }
        let flags = event.flags
        guard Settings.textKeys else { return false }
        let ctrl = flags.contains(.maskControl), cmd = flags.contains(.maskCommand), alt = flags.contains(.maskAlternate)
        if CtrlShortcuts.excludedApps.contains(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "") {
            // terminals: Ctrl stays Ctrl, but Ctrl+⌫ deletes the word to the left like in Windows Terminal.
            // The shell does it with ^W (zsh, bash, fish…), unless the text is in a Spotlight-like panel.
            guard key == backspace, ctrl, !cmd, !alt, !flags.contains(.maskShift), floatingTextField() == nil
            else { return false }
            pressed[key] = (w, flags)
            rewrite(event, w, flags)
            event.keyboardSetUnicodeString(stringLength: 1, unicodeString: [0x17]) // ^W
            return false
        }
        let base = CGEventFlags(rawValue: flags.rawValue & ~ctrlBits)

        // Ctrl+⌘+←/→: switch desktop (Ctrl+←/→ is now used for words)
        if ctrl, cmd, !alt, key == left || key == right {
            switchSpace(right: key == right)
            swallowedSpaceKeys.insert(key)
            return true
        }
        guard !cmd, !alt else { return false }
        var target: (key: Int64, flags: CGEventFlags)?
        let shift = flags.contains(.maskShift)
        if key == backspace, ctrl || shift {
            // Ctrl+⌫ and Shift+⌫: delete a word (Shift must not select anything here)
            target = (key, base.subtracting([.maskShift]).subtracting(CGEventFlags(rawValue: 0x2 | 0x4)).union(leftAlt))
        } else if ctrl, [left, right, forwardDelete].contains(key) {
            target = (key, base.union(leftAlt)) // with Shift, selects word by word
        } else if [home, end].contains(key), isEditingText() {
            let arrow = ctrl ? (key == home ? up : down) : (key == home ? left : right)
            // arrow keys always also carry the fn and numeric-pad flags
            target = (arrow, base.union(leftCmd).union([.maskSecondaryFn, .maskNumericPad]))
        }
        guard let target else { return false }
        pressed[key] = target
        rewrite(event, target.key, target.flags)
        return false
    }

    private static func rewrite(_ e: CGEvent, _ key: Int64, _ flags: CGEventFlags) {
        e.setIntegerValueField(.keyboardEventKeycode, value: key)
        e.flags = flags
    }

    // MARK: Desktops

    /// System shortcuts "Move left/right a space" (Ctrl+←/→, also with Shift).
    static let spaceHotkeys: [Int32] = [79, 80, 81, 82]
    private static var swallowedSpaceKeys = Set<Int64>()

    /// Briefly re-enables the system shortcut and "presses" it on the user's behalf.
    private static func switchSpace(right: Bool) {
        let hotkey: Int32 = right ? 81 : 79
        SystemHotkeys.setEnabled(hotkey, true)
        let src = CGEventSource(stateID: .privateState)
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(right ? self.right : left), keyDown: down)
            else { continue }
            e.flags = CGEventFlags(rawValue: CGEventFlags.maskControl.rawValue | 0x1).union([.maskSecondaryFn, .maskNumericPad])
            e.setIntegerValueField(.eventSourceUserData, value: CtrlShortcuts.marker)
            DispatchQueue.main.async { e.post(tap: .cghidEventTap) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { SystemHotkeys.sync() }
    }

    // MARK: Text field?

    /// Home/End must be rewritten only while typing: outside a text field, on the Mac (and on Windows)
    /// they scroll the page, while ⌘← in browsers would mean "previous page".
    /// `fieldsOnly`: only real text fields count. The Finder's desktop, for one, says it has a text selection
    /// even when you have just selected a file on it.
    static func isEditingText(fieldsOnly: Bool = false) -> Bool {
        if floatingTextField() != nil { return true }
        // ask the frontmost app: the "system-wide" query often doesn't respond
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let el = focusedElement(of: pid) else { return false }
        if isTextField(el) { return true }
        if fieldsOnly { return false }
        var range: CFTypeRef?
        return AXUIElementCopyAttributeValue(el, kAXSelectedTextRangeAttribute as CFString, &range) == .success && range != nil
    }

    /// Spotlight, Raycast, Alfred and the like: a panel above the windows that gets the keys without becoming
    /// the frontmost app (the Finder, say, stays frontmost). Returns its app if it has a text field focused.
    static func floatingTextField() -> pid_t? {
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let me = ProcessInfo.processInfo.processIdentifier
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        var checked = Set<pid_t>()
        for info in list {
            let layer = info[kCGWindowLayer as String] as? Int ?? 0
            if layer <= 0 { break } // the normal windows: no panels above them
            guard layer < Int(CGWindowLevelForKey(.screenSaverWindow)),
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != front, pid != me,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  !["Window Server", "Dock"].contains(info[kCGWindowOwnerName as String] as? String ?? ""),
                  checked.insert(pid).inserted else { continue }
            if let el = focusedElement(of: pid, timeout: 0.1), isTextField(el) { return pid }
        }
        return nil
    }

    private static func focusedElement(of pid: pid_t, timeout: Float = 0) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        if timeout > 0 { AXUIElementSetMessagingTimeout(app, timeout) }
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused else { return nil }
        return (focused as! AXUIElement)
    }

    private static func isTextField(_ el: AXUIElement) -> Bool {
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &role)
        return ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"].contains(role as? String ?? "")
    }
}
