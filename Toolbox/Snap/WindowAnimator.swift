import Cocoa

/// Moves windows to their new place gradually instead of in one jump, like Windows does when snapping.
/// Only for movements Toolbox decides (snap, restore, maximize): while you drag, the window follows the mouse.
/// Off with "Reduce motion" (Accessibility) or the setting in Window snapping.
enum WindowAnimator {
    static let duration: TimeInterval = 0.22
    private static var running: [CGWindowID: Timer] = [:]

    /// Brings `w` to `target`; `done` is called once it is there.
    static func move(_ w: WindowRef, to target: CGRect, done: (() -> Void)? = nil) {
        let id = w.id
        if let id { cancel(id) }
        guard let id, SnapSettings.animate, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              let from = w.frame, from.distance(to: target) > 4 else {
            w.setFrame(target)
            done?()
            return
        }
        let start = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { timer in
            // progress by time, not by steps: an app slow to redraw gets fewer steps, not a slower animation
            let k = min(1, (CACurrentMediaTime() - start) / duration)
            guard k < 1 else {
                timer.invalidate()
                running[id] = nil
                w.setFrame(target)
                done?()
                return
            }
            let e = 1 - pow(1 - k, 3) // ease-out: fast at first, gently settling
            w.setFrame(interpolate(from, target, e))
        }
        RunLoop.main.add(timer, forMode: .common)
        running[id] = timer
    }

    static func isAnimating(_ id: CGWindowID) -> Bool { running[id] != nil }

    /// Stops the window where it is (for example because you grabbed it).
    static func cancel(_ id: CGWindowID) {
        running.removeValue(forKey: id)?.invalidate()
    }

    private static func interpolate(_ a: CGRect, _ b: CGRect, _ t: CGFloat) -> CGRect {
        func mix(_ x: CGFloat, _ y: CGFloat) -> CGFloat { (x + (y - x) * t).rounded() }
        return CGRect(x: mix(a.minX, b.minX), y: mix(a.minY, b.minY),
                      width: mix(a.width, b.width), height: mix(a.height, b.height))
    }
}
