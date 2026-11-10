import Cocoa

/// Intercepts ⌥ Tab system-wide with a CGEventTap (requires the Accessibility permission).
final class HotkeyTap {
    let switcher: SwitcherController
    private var tap: CFMachPort?

    init(switcher: SwitcherController) { self.switcher = switcher }

    func start() -> Bool {
        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .leftMouseUp]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                          options: .defaultTap, eventsOfInterest: mask,
                                          callback: hotkeyCallback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { return false }
        self.tap = tap
        let src = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    /// Chosen key + chosen modifier, with no other modifiers (⇧ allowed to go backwards).
    private func isHotkey(_ key: Int64, _ flags: CGEventFlags) -> Bool {
        let mod = Settings.modifier
        guard key == Int64(Settings.key.rawValue), flags.contains(mod.flag) else { return false }
        return HotkeyModifier.allCases.allSatisfy { $0 == mod || !flags.contains($0.flag) }
    }

    fileprivate func handle(_ type: CGEventType, _ event: CGEvent, proxy: CGEventTapProxy) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        if type == .leftMouseDown || type == .leftMouseUp {
            if type == .leftMouseDown {
                if AutoQuit.closeButtonDown(at: event.location) { return nil } // X on the last window → ⌘Q
                AutoQuit.actionStarted()
                let p = event.location
                MainActor.assumeIsolated { DockPreview.mouseDown(at: p) }
                NotificationMover.mouseDown(at: p)
                WindowSnap.shared.mouseDown(at: p) // snap windows to the edges
            } else {
                WindowSnap.shared.mouseUp()
                if AutoQuit.consumeMouseUp() { return nil }
                AutoQuit.actionEnded()
            }
            return DockClick.handle(type, at: event.location) ? nil : Unmanaged.passUnretained(event)
        }
        // Snap Assist open: Esc, arrows and Return belong to it
        if type == .keyDown, SnapAssist.shared.isVisible,
           SnapAssist.shared.handleKey(event.getIntegerValueField(.keyboardEventKeycode)) {
            return nil
        }
        if type == .keyUp, SnapAssist.shared.isVisible { return nil }
        // ⌥Z open (Win+Z): numbers, arrows, Return, Esc
        if type == .keyDown, LayoutFlyout.shared.isVisible,
           LayoutFlyout.shared.handleKey(event.getIntegerValueField(.keyboardEventKeycode)) {
            return nil
        }
        // left ⌥ + arrows / Z like Win + arrows / Win+Z (before Ctrl→⌘ and the text-editing keys)
        if type == .keyDown || type == .keyUp, !MainActor.assumeIsolated({ switcher.isVisible }),
           SnapKeys.handle(type, event) {
            return nil
        }
        // Finder like Windows (before Ctrl→⌘: Ctrl+X in Finder means "cut the files")
        if type == .keyDown || type == .keyUp, !MainActor.assumeIsolated({ switcher.isVisible }),
           FinderKeys.handle(type, event) {
            return nil
        }
        // Ctrl+C → ⌘C etc. (not while the switcher is open: keys mean something else there)
        if type == .keyDown || type == .keyUp || type == .flagsChanged,
           !MainActor.assumeIsolated({ switcher.isVisible }), CtrlShortcuts.handle(type, event) {
            return nil
        }
        if type == .keyDown || type == .keyUp, !MainActor.assumeIsolated({ switcher.isVisible }),
           ScreenSnip.handle(type, event) || AltGr.handle(type, event) || TextKeys.handle(type, event) {
            return nil
        }
        let flags = event.flags
        let key = event.getIntegerValueField(.keyboardEventKeycode)
        let shift = flags.contains(.maskShift)

        return MainActor.assumeIsolated {
            switch type {
            case .flagsChanged:
                if switcher.isVisible && !flags.contains(Settings.modifier.flag) { switcher.commit() }
                return Unmanaged.passUnretained(event)

            case .keyDown:
                if isHotkey(key, flags) {
                    if switcher.isVisible { switcher.move(shift ? -1 : 1) } else {
                        SnapAssist.shared.dismiss() // like Alt+Tab on Windows: Snap Assist closes
                        LayoutFlyout.shared.dismiss()
                        switcher.show(reverse: shift)
                    }
                    return nil
                }
                if !switcher.isVisible && key == Key.w && flags.contains(.maskCommand) {
                    AutoQuit.actionStarted(sync: true)
                    AutoQuit.actionEnded()
                }
                guard switcher.isVisible else { return Unmanaged.passUnretained(event) }
                switch key {
                case Key.escape: switcher.cancel()
                case Key.left: switcher.move(-1)
                case Key.right: switcher.move(1)
                case Key.up: switcher.moveRow(-1)
                case Key.down: switcher.moveRow(1)
                case Key.enter: switcher.commit()
                case Key.q: switcher.quitSelected()
                case Key.w: switcher.closeSelectedWindow()
                default: break
                }
                return nil // while the switcher is open, keys don't reach the apps

            case .keyUp:
                return switcher.isVisible ? nil : Unmanaged.passUnretained(event)

            default:
                return Unmanaged.passUnretained(event)
            }
        }
    }
}

private enum Key {
    static let tab: Int64 = 48, escape: Int64 = 53, enter: Int64 = 36
    static let left: Int64 = 123, right: Int64 = 124, down: Int64 = 125, up: Int64 = 126
    static let q: Int64 = 12, w: Int64 = 13
}

private let hotkeyCallback: CGEventTapCallBack = { proxy, type, event, refcon in
    let me = Unmanaged<HotkeyTap>.fromOpaque(refcon!).takeUnretainedValue()
    return me.handle(type, event, proxy: proxy)
}
