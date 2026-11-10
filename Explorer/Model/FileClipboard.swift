import Cocoa

@MainActor
enum FileClipboard {
    /// "Cut" files: pasting them moves them. Valid until someone else writes to the pasteboard.
    static var cut: Set<URL> = []
    private static var cutChange = -1

    static func put(_ urls: [URL], cut isCut: Bool) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(urls as [NSURL])
        cut = isCut ? Set(urls) : []
        cutChange = pb.changeCount
        NotificationCenter.default.post(name: .clipboardChanged, object: nil)
    }

    static var files: [URL] {
        NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }

    static var isCut: Bool { NSPasteboard.general.changeCount == cutChange && !cut.isEmpty }

    static func clearCut() { cut = []; NotificationCenter.default.post(name: .clipboardChanged, object: nil) }
}

extension Notification.Name {
    static let clipboardChanged = Notification.Name("ExplorerClipboardChanged")
    static let explorerPrefsChanged = Notification.Name("ExplorerPrefsChanged")
}
