import Cocoa

enum Fmt {
    static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
    static func date(_ d: Date) -> String {
        d == .distantPast ? "" : d.formatted(date: .numeric, time: .shortened)
    }
    static func exactBytes(_ b: Int64) -> String { String(localized: "\(b.formatted(.number)) bytes") }
}

// MARK: - Icons and thumbnails

@MainActor
enum Icons {
    private static var cache: [String: NSImage] = [:]
    static func icon(_ url: URL) -> NSImage {
        if let i = cache[url.path] { return i }
        let i = NSWorkspace.shared.icon(forFile: url.path)
        if cache.count > 3000 { cache.removeAll() }
        cache[url.path] = i
        return i
    }
}
