import Cocoa

/// Minimizes every window into the Dock; the next time, brings back the ones it minimized, in the order
/// they were (the window that was in front ends up in front again). Used to show the desktop.
enum MinimizeAll {
    /// Front to back, as they were on screen.
    private static var minimized: [WindowRef] = []

    static func toggle() {
        let waiting = minimized.filter(\.isMinimized)
        if !waiting.isEmpty {
            waiting.reversed().forEach { $0.minimize(false) } // from the back: the front one comes back last, on top
            minimized = []
            if let front = waiting.first {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { front.raise() }
            }
            return
        }
        minimized = WindowManager.visibleWindows().filter { $0.state == .normal }.compactMap(WindowRef.of)
        minimized.forEach { $0.minimize() }
        Log.info("Show desktop: minimized \(minimized.count) windows")
    }
}
