import Cocoa

enum FolderSizes {
    private static let lock = NSLock()
    private static var cache: [URL: (size: Int64, count: Int)] = [:]

    static func cached(_ url: URL) -> (size: Int64, count: Int)? {
        lock.lock(); defer { lock.unlock() }
        return cache[url]
    }

    static func forget(under url: URL) {
        lock.lock(); defer { lock.unlock() }
        let prefix = url.path
        // something changed in here: the folders containing it change size too
        cache = cache.filter { !($0.key.path.hasPrefix(prefix) || prefix.hasPrefix($0.key.path)) }
    }

    static func compute(_ url: URL) -> (size: Int64, count: Int) {
        if let c = cached(url) { return c }
        let fm = FileManager.default
        let count = (try? fm.contentsOfDirectory(atPath: url.path).count) ?? 0
        var total: Int64 = 0
        if let e = fm.enumerator(at: url, includingPropertiesForKeys: [.totalFileSizeKey, .fileSizeKey, .isRegularFileKey],
                                 options: [], errorHandler: { _, _ in true }) {
            for case let f as URL in e {
                let v = try? f.resourceValues(forKeys: [.totalFileSizeKey, .fileSizeKey, .isRegularFileKey])
                if v?.isRegularFile == true { total += Int64(v?.totalFileSize ?? v?.fileSize ?? 0) }
            }
        }
        lock.lock(); cache[url] = (total, count); lock.unlock()
        return (total, count)
    }
}

// MARK: - Miscellaneous operations

enum FileOps {
    /// "name.txt" → "name - Copy.txt", "name - Copy (2).txt"…, or "New Folder (2)".
    static func uniqueURL(for name: String, in folder: URL, copySuffix: Bool) -> URL {
        let fm = FileManager.default
        let first = folder.appendingPathComponent(name)
        guard fm.fileExists(atPath: first.path) else { return first }
        let ext = (name as NSString).pathExtension
        let isDir = (try? first.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        let base = ext.isEmpty || (isDir && !name.hasSuffix(".app")) ? name : (name as NSString).deletingPathExtension
        let suffix = ext.isEmpty || (isDir && !name.hasSuffix(".app")) ? "" : ".\(ext)"
        var n = 1
        while true {
            let label = copySuffix ? (n == 1 ? String(localized: "\(base) - Copy") : String(localized: "\(base) - Copy (\(n))")) : "\(base) (\(n + 1))"
            let candidate = folder.appendingPathComponent(label + suffix)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            n += 1
        }
    }

    static func zip(_ urls: [URL], in folder: URL) -> String? {
        let name = urls.count == 1 ? urls[0].deletingPathExtension().lastPathComponent : String(localized: "Archive")
        let dest = uniqueURL(for: name + ".zip", in: folder, copySuffix: false)
        let p = Process()
        if urls.count == 1 {
            p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            p.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", urls[0].path, dest.path]
        } else {
            p.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            p.currentDirectoryURL = folder
            p.arguments = ["-r", "-q", "-y", dest.path] + urls.map(\.lastPathComponent)
        }
        return run(p, String(localized: "Compression failed"))
    }

    static func unzip(_ zip: URL) -> String? {
        let folder = uniqueURL(for: zip.deletingPathExtension().lastPathComponent, in: zip.deletingLastPathComponent(), copySuffix: false)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-x", "-k", zip.path, folder.path]
        return run(p, String(localized: "Extraction failed"))
    }

    private static func run(_ p: Process, _ failure: String) -> String? {
        do { try p.run(); p.waitUntilExit() } catch { return "\(failure): \(error.localizedDescription)" }
        return p.terminationStatus == 0 ? nil : failure
    }

    static func setWallpaper(_ url: URL) {
        for screen in NSScreen.screens {
            try? NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: NSWorkspace.shared.desktopImageOptions(for: screen) ?? [:])
        }
    }

    static func openInTerminal(_ folder: URL) {
        let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        NSWorkspace.shared.open([folder], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
    }

    static let isImage: (URL) -> Bool = { url in
        guard let t = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType else { return false }
        return t.conforms(to: .image)
    }
}
