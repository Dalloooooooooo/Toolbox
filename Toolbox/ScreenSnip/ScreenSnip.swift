import Cocoa

/// Screen snipping like Win+Shift+S: ⌥⇧S freezes the screen → rectangle, freeform, window or full screen.
/// The snip goes to the clipboard and to Pictures/Screenshots; a notification lets you open it to mark it up.
@MainActor
enum ScreenSnip {
    private static var swallowUp = false
    private static var running = false

    static var folder: URL {
        FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask)[0].appendingPathComponent(String(localized: "Screenshots"))
    }

    /// From the event tap: true if the key should be swallowed.
    nonisolated static func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        let key = event.getIntegerValueField(.keyboardEventKeycode)
        let shortcut = Shortcut.screenSnip
        guard key == Int64(shortcut.keyCode ?? -1) else { return false }
        return MainActor.assumeIsolated {
            if type == .keyUp {
                defer { swallowUp = false }
                return swallowUp
            }
            guard Settings.screenSnip, shortcut.matches(key: key, flags: event.flags) else { return false }
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
        // like Windows: the screen freezes, so what's on it (menus, animations…) stays still while you select
        SnipOverlay.show(done: { image in
            running = false
            guard let image, save(image, to: file) else { return } // Esc: no snip
            finished(file)
        }, failed: { systemSelection(file) })
    }

    /// Without the Screen Recording permission: macOS's own selection (the screen doesn't freeze).
    private static func systemSelection(_ file: URL) {
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

    private static func save(_ image: CGImage, to file: URL) -> Bool {
        guard let dest = CGImageDestinationCreateWithURL(file as CFURL, "public.png" as CFString, 1, nil)
        else { return false }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest)
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
