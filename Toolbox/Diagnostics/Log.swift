import Foundation

/// Toolbox log in ~/Library/Logs/Toolbox/toolbox.log: launch, permissions, errors, updates.
/// Never any user content (text, file names or window names). Past ~500 KB it starts over
/// and the previous one is kept in toolbox.1.log.
enum Log {
    static let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Toolbox")
    static let file = folder.appendingPathComponent("toolbox.log")
    private static let previous = folder.appendingPathComponent("toolbox.1.log")
    private static let maxSize = 500_000
    private static let queue = DispatchQueue(label: "Toolbox.Log", qos: .utility)
    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    static func info(_ message: String) { write("INFO ", message) }
    static func error(_ message: String) { write("ERROR", message) }

    private static func write(_ level: String, _ message: String) {
        let line = "\(stamp.string(from: Date())) \(level) \(message)\n"
        queue.async {
            let fm = FileManager.default
            try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
            if let size = (try? fm.attributesOfItem(atPath: file.path))?[.size] as? Int, size > maxSize {
                try? fm.removeItem(at: previous)
                try? fm.moveItem(at: file, to: previous)
            }
            if let handle = try? FileHandle(forWritingTo: file) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                try? line.write(to: file, atomically: true, encoding: .utf8)
            }
        }
    }

    /// The last lines of the log (for problem reports).
    static func tail(_ count: Int) -> String {
        queue.sync {} // waits for pending writes
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return "" }
        return text.split(separator: "\n").suffix(count).joined(separator: "\n")
    }
}
