import Cocoa
import ImageIO
import UniformTypeIdentifiers

/// Latest captured window previews. macOS doesn't render minimized windows, so we capture them while
/// they are still open: the frontmost app every few seconds (only while you're using the Mac), and each
/// app when you leave it. Previews live in memory only, JPEG-compressed (10–20× smaller than a bitmap),
/// and are dropped as soon as their window closes.
enum PreviewStore {
    private struct Entry { let jpeg: Data; let size: NSSize } // size in points, for Retina sharpness
    private static var store: [CGWindowID: Entry] = [:]
    private static var timer: Timer?
    private static let interval: TimeInterval = 5
    /// No input for this long → nothing on screen is changing because of the user: skip the capture.
    private static let idleAfter: TimeInterval = 60

    static func image(for id: CGWindowID) -> NSImage? {
        guard let entry = store[id], let image = NSImage(data: entry.jpeg) else { return nil }
        image.size = entry.size
        return image
    }

    static func set(_ image: NSImage, for id: CGWindowID) {
        guard let data = jpeg(image) else { return }
        store[id] = Entry(jpeg: data, size: image.size)
    }

    static func startBackgroundRefresh() {
        let t = Timer(timeInterval: interval, repeats: true) { _ in
            pruneClosedWindows()
            guard !userIsIdle, let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return }
            refresh(pid: pid)
        }
        t.tolerance = 1 // lets macOS group our wake-ups with others
        RunLoop.main.add(t, forMode: .common)
        timer = t
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didDeactivateApplicationNotification,
                                                          object: nil, queue: .main) { note in
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                refresh(pid: app.processIdentifier)
            }
        }
    }

    static func refresh(pid: pid_t) {
        guard Settings.backgroundPreviews, CGPreflightScreenCaptureAccess() else { return }
        let ids = WindowManager.visibleWindows().filter { $0.pid == pid }.map(\.id)
        guard !ids.isEmpty else { return }
        WindowManager.capturePreviews(ids: ids, maxSize: TileMetrics.current.preview) { id, img in set(img, for: id) }
    }

    /// Drops the previews of windows that have been closed, so memory doesn't grow over time.
    static func pruneClosedWindows() {
        guard !store.isEmpty,
              let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return }
        prune(keeping: Set(list.compactMap { $0[kCGWindowNumber as String] as? CGWindowID }))
    }

    /// Forgets windows that are not in `ids`.
    static func prune(keeping ids: Set<CGWindowID>) {
        store = store.filter { ids.contains($0.key) }
    }

    private static var userIsIdle: Bool {
        let kinds: [CGEventType] = [.keyDown, .mouseMoved, .leftMouseDown, .rightMouseDown, .scrollWheel]
        let since = kinds.map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }.min() ?? 0
        return since > idleAfter
    }

    private static func jpeg(_ image: NSImage) -> Data? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, cg, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }
}
