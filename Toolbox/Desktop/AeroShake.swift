import Cocoa

/// Aero Shake, like Windows: grab a window by its title bar and shake it hard → every other window is
/// minimized; shake it again → they come back. WindowSnap feeds the pointer while a window is being moved.
enum AeroShake {
    private static var detector = ShakeDetector()
    /// The windows we minimized, to bring back with the next shake.
    private static var minimized: [WindowRef] = []

    static func dragStarted() { detector.reset() }

    /// While a window is being moved: the pointer is at `x`.
    static func dragging(_ window: WindowRef, id: CGWindowID, x: CGFloat) {
        guard Settings.aeroShake, detector.feed(x, at: ProcessInfo.processInfo.systemUptime) else { return }
        DispatchQueue.main.async { shaken(keeping: window, id: id) }
    }

    private static func shaken(keeping held: WindowRef, id: CGWindowID) {
        let stillMinimized = minimized.filter(\.isMinimized)
        if !stillMinimized.isEmpty {
            stillMinimized.reversed().forEach { $0.minimize(false) }
            minimized = []
            // the windows coming back go to the front (and may activate their apps): the one in your hand
            // stays in front, also once their animation has finished
            for delay in [0.05, 0.35, 0.7] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { held.raise() }
            }
            return
        }
        let others = WindowManager.visibleWindows().filter { $0.id != id && $0.state == .normal }
        minimized = others.compactMap(WindowRef.of)
        minimized.forEach { $0.minimize() }
        Log.info("Aero Shake: minimized \(minimized.count) windows")
    }
}
