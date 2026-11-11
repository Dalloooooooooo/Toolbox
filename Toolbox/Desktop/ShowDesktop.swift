import Cocoa

/// Show the desktop like Windows (Win+D): hold ⇧ and shake the mouse hard, or press ⌥D (both can be changed).
/// Do it again and every window comes back. By default every window is minimized into the Dock; the other
/// choice is macOS's own "Show Desktop" (the one on F11 and the trackpad), which moves them aside.
enum ShowDesktop {
    /// Private Dock function (ApplicationServices): "com.apple.showdesktop.awake" toggles Show Desktop.
    @_silgen_name("CoreDockSendNotification")
    private static func CoreDockSendNotification(_ name: CFString, _ unknown: UnsafeMutableRawPointer?) -> Void

    static func toggle() {
        if Settings.showDesktopMinimizes { MinimizeAll.toggle() }
        else { CoreDockSendNotification("com.apple.showdesktop.awake" as CFString, nil) }
    }

    // MARK: Shortcut (⌥D by default, like Win+D) and the key held while shaking (⇧ by default)

    private static var swallowUp = false

    static func handleKey(_ type: CGEventType, _ event: CGEvent) -> Bool {
        let key = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .keyUp {
            guard swallowUp, key == Int64(Shortcut.showDesktop.keyCode ?? -1) else { return false }
            swallowUp = false
            return true
        }
        guard type == .keyDown, Settings.showDesktopKey, Shortcut.showDesktop.matches(key: key, flags: event.flags) else { return false }
        swallowUp = true
        if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 { DispatchQueue.main.async(execute: toggle) }
        return true
    }

    /// Mouse buttons other than the left one: the shortcut (if it's a button) or the button to hold while shaking.
    private static var swallowButtonUp: Int64?

    static func mouse(_ type: CGEventType, button: Int64, flags: CGEventFlags) -> Bool {
        let down = type == .otherMouseDown || type == .rightMouseDown
        if Settings.showDesktopShake, Shortcut.shakeHold.matches(button: button, flags: flags) {
            Shake.shared.following = down
        }
        if down, Settings.showDesktopKey, Shortcut.showDesktop.matches(button: button, flags: flags) {
            swallowButtonUp = button
            DispatchQueue.main.async(execute: toggle)
            return true
        }
        if !down, swallowButtonUp == button { swallowButtonUp = nil; return true }
        return false
    }

    /// Called on every modifier change: the mouse is followed only while the chosen keys are held down,
    /// so the rest of the time this costs nothing.
    static func flagsChanged(_ flags: CGEventFlags) {
        let hold = Shortcut.shakeHold
        guard hold.mouseButton == nil else { return }
        Shake.shared.following = Settings.showDesktopShake && hold.isHeld(flags)
    }
}

/// Recognizes a hard shake from the pointer's horizontal position: it goes back and forth at least 4 times
/// within a second, each stroke long (≥ 180 points) and fast. Normal movements never trigger it.
struct ShakeDetector {
    private let minStroke: CGFloat = 180     // points per stroke
    private let minSpeed: CGFloat = 1400     // points per second, on average over the stroke
    private let turnsNeeded = 4
    private let window: TimeInterval = 1.0
    private let jitter: CGFloat = 6

    private var lastX: CGFloat?
    private var direction: CGFloat = 0
    private var strokeStart: (x: CGFloat, t: TimeInterval) = (0, 0)
    private var turns: [TimeInterval] = []
    private var cooldownUntil: TimeInterval = 0

    mutating func reset() {
        lastX = nil
        direction = 0
        turns = []
    }

    /// The pointer is at `x` at time `t`: true when a shake has just been completed.
    mutating func feed(_ x: CGFloat, at t: TimeInterval) -> Bool {
        defer { lastX = x }
        guard let last = lastX else { strokeStart = (x, t); return false }
        let dx = x - last
        guard abs(dx) >= 1 else { return false }
        let dir: CGFloat = dx > 0 ? 1 : -1
        if direction == 0 { direction = dir; strokeStart = (last, t); return false }
        guard dir != direction else { return false }
        // the pointer turned around: was the stroke that just ended long and fast enough?
        let length = abs(last - strokeStart.x), duration = max(0.001, t - strokeStart.t)
        if length >= minStroke, length / duration >= minSpeed {
            turns.append(t)
            turns.removeAll { t - $0 > window }
        } else if length >= jitter {
            turns = [] // a slow or short stroke: not a shake
        }
        direction = dir
        strokeStart = (last, t)
        guard turns.count >= turnsNeeded, t >= cooldownUntil else { return false }
        turns = []
        cooldownUntil = t + 0.8
        return true
    }
}

/// Follows the pointer while the chosen keys (or mouse button) are held, to recognize the shake.
private final class Shake {
    static let shared = Shake()
    private var tap: CFMachPort?
    private var detector = ShakeDetector()

    var following = false {
        didSet {
            guard following != oldValue else { return }
            detector.reset()
            if following { start() } else if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        }
    }

    private func start() {
        if tap == nil {
            let types: [CGEventType] = [.mouseMoved, .otherMouseDragged, .rightMouseDragged]
            let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
            tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly,
                                    eventsOfInterest: mask, callback: { _, _, event, _ in
                                        Shake.shared.moved(event.location.x)
                                        return Unmanaged.passUnretained(event)
                                    }, userInfo: nil)
            if let tap { CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes) }
        }
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    private func moved(_ x: CGFloat) {
        if detector.feed(x, at: ProcessInfo.processInfo.systemUptime) { DispatchQueue.main.async { ShowDesktop.toggle() } }
    }
}
