import Cocoa
import ApplicationServices

/// Minimal log of intercepted notifications (only app, time and outcome, never the text), to tell
/// whether a notification reaches the Mac. In ~/Library/Logs/Toolbox/notifiche.log, at most 500 lines.
enum NotificationLog {
    /// Window structure (only roles and identifiers, never text), to tell the panel apart from
    /// a banner. In notifiche-struttura.log, only the last 6 windows.
    static func structure(_ window: AXUIElement, label: String) {
        func attr(_ e: AXUIElement, _ n: String) -> CFTypeRef? {
            var v: CFTypeRef?; return AXUIElementCopyAttributeValue(e, n as CFString, &v) == .success ? v : nil
        }
        var lines: [String] = ["### \(label) \(Date().formatted(date: .omitted, time: .standard))"]
        func walk(_ e: AXUIElement, _ d: Int) {
            guard d < 10, lines.count < 80 else { return }
            let r = attr(e, kAXRoleAttribute) as? String ?? "", s = attr(e, kAXSubroleAttribute) as? String ?? ""
            let id = (attr(e, kAXIdentifierAttribute) as? String).map { String($0.prefix(40)) } ?? ""
            let kids = attr(e, kAXChildrenAttribute) as? [AXUIElement] ?? []
            lines.append(String(repeating: "  ", count: d) + "\(r) \(s) \(id) [\(kids.count)]")
            kids.prefix(5).forEach { walk($0, d + 1) }
        }
        walk(window, 0)
        let file = url.deletingLastPathComponent().appendingPathComponent("notifiche-struttura.log")
        let old = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        let blocks = old.components(separatedBy: "### ").filter { !$0.isEmpty }.suffix(5).map { "### " + $0 }
        try? (blocks.joined() + lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
    }

    static var url: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Toolbox/notifiche.log")
    }

    static func add(app: String, outcome: String) {
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var lines = ((try? String(contentsOf: url, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
        lines.append("\(Date().formatted(date: .numeric, time: .standard))  \(app) — \(outcome)")
        try? lines.suffix(500).joined(separator: "\n").appending("\n").write(to: url, atomically: true, encoding: .utf8)
    }
}
