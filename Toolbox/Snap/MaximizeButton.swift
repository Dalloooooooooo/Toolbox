import Cocoa
import ApplicationServices

/// The green button maximizes the window on the current desktop, like Windows' maximize button, instead of
/// moving it to full screen on a desktop of its own. A second click restores it. Full screen stays one
/// shortcut away (⌃⌘F, or the menu that appears when hovering over the green button).
/// ⌥-click keeps macOS's own behavior.
enum MaximizeButton {
    private static var swallowUp = false

    /// Called by the event tap on mouse down. Returns true if the click is ours (and must be swallowed).
    static func mouseDown(at p: CGPoint, flags: CGEventFlags) -> Bool {
        guard SnapSettings.greenButton, AXIsProcessTrusted(),
              flags.intersection([.maskAlternate, .maskCommand, .maskControl, .maskShift]).isEmpty,
              let window = windowOfGreenButton(at: p) else { return false }
        swallowUp = true
        DispatchQueue.main.async { WindowSnap.shared.toggleMaximize(window) }
        return true
    }

    /// The release of a swallowed click is swallowed too.
    static func consumeMouseUp() -> Bool {
        defer { swallowUp = false }
        return swallowUp
    }

    /// The window whose green button is at `p`, if there is one.
    private static func windowOfGreenButton(at p: CGPoint) -> WindowRef? {
        // Toolbox's own windows through AppKit: Accessibility on ourselves would wait for our own main thread
        if let own = MainActor.assumeIsolated({ ownWindowWithZoomButton(at: p) }) { return .own(own) }
        var hit: AXUIElement?
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.25) // never hold up the click for long
        guard AXUIElementCopyElementAtPosition(system, Float(p.x), Float(p.y), &hit) == .success, let button = hit,
              let subrole = attr(button, kAXSubroleAttribute) as? String,
              subrole == kAXFullScreenButtonSubrole as String || subrole == kAXZoomButtonSubrole as String,
              let w = attr(button, kAXWindowAttribute), CFGetTypeID(w) == AXUIElementGetTypeID() else { return nil }
        let window = w as! AXUIElement
        // only normal windows (not panels, not windows already in full screen)
        guard attr(window, kAXSubroleAttribute) as? String == kAXStandardWindowSubrole as String,
              attr(window, "AXFullScreen") as? Bool != true else { return nil }
        return .other(window)
    }

    @MainActor private static func ownWindowWithZoomButton(at p: CGPoint) -> NSWindow? {
        let ns = ScreenGeo.ns(CGRect(origin: p, size: .zero)).origin
        let top = NSWindow.windowNumber(at: ns, belowWindowWithWindowNumber: 0)
        guard let w = NSApp.windows.first(where: { $0.windowNumber == top && $0.isVisible }),
              !w.styleMask.contains(.fullScreen), let button = w.standardWindowButton(.zoomButton),
              button.isEnabled, !button.isHidden else { return nil }
        let frame = w.convertToScreen(button.convert(button.bounds, to: nil))
        return frame.contains(ns) ? w : nil
    }

    private static func attr(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success ? v : nil
    }
}
