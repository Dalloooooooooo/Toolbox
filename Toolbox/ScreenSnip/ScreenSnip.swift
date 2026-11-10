import Cocoa

/// Screen snipping like Win+Shift+S: ⌥⇧S → select an area (or a window with Space).
/// The snip goes to the clipboard and to Pictures/Screenshots; a notification lets you open it to mark it up.
@MainActor
enum ScreenSnip {
    private static let sKey: Int64 = 1
    private static var swallowUp = false
    private static var running = false

    static var folder: URL {
        FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0].appendingPathComponent(String(localized: "Screenshots"))
    }

    /// From the event tap: true if the key should be swallowed.
    nonisolated static func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        let key = event.getIntegerValueField(.keyboardEventKeycode)
        guard key == sKey else { return false }
        return MainActor.assumeIsolated {
            if type == .keyUp {
                defer { swallowUp = false }
                return swallowUp
            }
            let f = event.flags
            guard Settings.screenSnip, f.contains(.maskAlternate), f.contains(.maskShift),
                  !f.contains(.maskCommand), !f.contains(.maskControl) else { return false }
            swallowUp = true
            if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 { DispatchQueue.main.async { start() } }
            return true
        }
    }

    static func start() {
        guard !running else { return }
        running = true
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let df = DateFormatter()
        // local time; the word between date and time follows the language ("at" / "alle")
        df.dateFormat = String(localized: "yyyy-MM-dd 'at' HH.mm.ss")
        let file = folder.appendingPathComponent("\(String(localized: "Screenshot")) \(df.string(from: Date())).png")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        p.arguments = ["-i", "-x", "-o", file.path] // -i selection, -x no sound, -o windows without shadow
        p.terminationHandler = { _ in
            DispatchQueue.main.async {
                running = false
                finished(file)
            }
        }
        do { try p.run() } catch { running = false }
    }

    private static func finished(_ file: URL) {
        // Esc: no file, no snip
        guard FileManager.default.fileExists(atPath: file.path), let image = NSImage(contentsOf: file) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([image])

        let content = NotificationContent(id: "snip-\(file.lastPathComponent)", appName: "Toolbox",
                                          title: String(localized: "Screenshot copied to clipboard"),
                                          subtitle: "",
                                          body: String(localized: "Paste it with Ctrl+V. Click here to open it and draw on it."),
                                          icon: image)
        content.action = { NSWorkspace.shared.open(file) }
        NotificationPresenter.shared.show(content, original: nil)
    }

    static func openFolder() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }
}
