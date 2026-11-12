import Cocoa

/// Zone shortcuts, from the event tap (left ⌥ = Windows key, as for snapping):
/// - ⌥⇧ + the key above Tab: layout editor (Win+Shift+` in FancyZones);
/// - ⌥⌃⌘ + number: switches the monitor to the layout with that number (Win+Ctrl+Alt+number);
/// - ⌥ + arrows, if chosen in the settings: from zone to zone instead of halves and quarters.
enum ZoneKeys {
    private static var swallowUp: Int64?
    private static let digits: [Int64: Int] = [29: 0, 18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9]

    static func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        let key = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .keyUp {
            if swallowUp == key { swallowUp = nil; return true }
            return false
        }
        guard type == .keyDown, ZoneSettings.enabled else { return false }
        let flags = event.flags
        let option = flags.contains(.maskAlternate), leftOption = flags.rawValue & 0x20 != 0
        let shift = flags.contains(.maskShift), control = flags.contains(.maskControl), command = flags.contains(.maskCommand)
        let repeated = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        var action: (() -> Void)?

        if Shortcut.zoneEditor.matches(key: key, flags: flags) {
            action = { ZoneEditor.shared.show() }
        } else if option, control, command, !shift, ZoneSettings.quickSwitch, let n = digits[key],
                  let layout = ZoneStore.shared.layout(hotkey: n) {
            action = { switchLayout(to: layout) }
        } else if leftOption, !shift, !control, !command, ZoneSettings.overrideKeys,
                  let arrow = arrow(key), ZoneStore.shared.layouts.contains(where: { !$0.zones.isEmpty }) {
            action = { move(arrow) }
        }
        guard let action else { return false }
        swallowUp = key
        if !repeated { DispatchQueue.main.async(execute: action) }
        return true
    }

    private static func arrow(_ key: Int64) -> WindowSnap.Arrow? {
        switch key {
        case 123: .left
        case 124: .right
        case 126: .up
        case 125: .down
        default: nil
        }
    }

    /// The monitor with the active window (or the pointer) switches layout.
    private static func switchLayout(to layout: ZoneLayout) {
        let screen = WindowRef.focused()?.frame.flatMap(ScreenGeo.screen(for:)) ?? ScreenGeo.screen(at: ScreenGeo.mouse)
        guard let screen else { return }
        ZoneStore.shared.apply(layout.id, to: screen)
        ZoneOverlay.shared.flash(screen)
    }

    /// ⌥ + arrows between zones. By number: ← and → go to the previous and next zone (↑ ↓ keep working as
    /// Windows' keys). By position: each arrow goes to the nearest zone in that direction.
    private static func move(_ a: WindowSnap.Arrow) {
        guard let w = WindowRef.focused(), let id = w.id, let f = w.frame, let screen = ScreenGeo.screen(for: f) else {
            NSSound.beep(); return
        }
        let area = ScreenGeo.area(screen)
        let frames = SmartZones.layout(for: screen, window: id).frames(in: area)
        let byPosition = ZoneSettings.keysByPosition
        guard !frames.isEmpty, !ZoneSettings.isExcluded(pid: w.pid), byPosition || a == .left || a == .right else {
            if SnapSettings.enabled && SnapSettings.keys { WindowSnap.shared.arrow(a, shift: false) }
            return
        }
        let current = frames.indices.min { frames[$0].distance(to: f) < frames[$1].distance(to: f) }
            .flatMap { frames[$0].distance(to: f) < 12 ? $0 : nil }
        let next: Int?
        if byPosition {
            let c = CGPoint(x: f.midX, y: f.midY)
            let candidates = frames.indices.filter { i in
                guard i != current else { return false }
                let z = frames[i]
                switch a {
                case .left: return z.midX < c.x - 4
                case .right: return z.midX > c.x + 4
                case .up: return z.midY < c.y - 4
                case .down: return z.midY > c.y + 4
                }
            }
            // nearest in the direction, preferring zones in line with the window
            next = candidates.min { cost(frames[$0], from: c, a) < cost(frames[$1], from: c, a) }
        } else {
            let n = frames.count
            if let current { next = (current + (a == .right ? 1 : -1) + n) % n } else { next = a == .right ? 0 : n - 1 }
        }
        guard let next else { NSSound.beep(); return }
        let z = frames[next]
        let unit = CGRect(x: (z.minX - area.minX) / area.width, y: (z.minY - area.minY) / area.height,
                          width: z.width / area.width, height: z.height / area.height)
        WindowSnap.shared.place(z, zone: SnapZone(unit: unit), to: w, id: id, area: area,
                                restore: WindowSnap.shared.inPlace(id) == nil ? f : nil)
    }

    private static func cost(_ z: CGRect, from c: CGPoint, _ a: WindowSnap.Arrow) -> CGFloat {
        let along = a == .left || a == .right ? abs(z.midX - c.x) : abs(z.midY - c.y)
        let across = a == .left || a == .right ? abs(z.midY - c.y) : abs(z.midX - c.x)
        return along + across * 2
    }
}
