import Cocoa

/// Problem reporting designed for anyone: one click opens a prefilled GitHub issue with the
/// version, system, last unexpected quit and the latest log lines.
/// No personal data: the log contains no text, file names or window names.
enum ProblemReport {
    static var text: String {
        let info = ProcessInfo.processInfo
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        var lines = [
            "**Toolbox** \(Updater.currentVersion) (\(build))",
            "**macOS** \(info.operatingSystemVersionString)",
            "**Mac** \(machine)",
            "",
        ]
        if let crash = CrashReporter.lastCrash {
            lines += ["### Last unexpected quit",
                      "\(crash.date.formatted(date: .abbreviated, time: .standard)) · Toolbox \(crash.version) · \(crash.kind)",
                      "```", crash.frames.joined(separator: "\n"), "```", ""]
        }
        lines += ["### Log", "```", Log.tail(40), "```"]
        return lines.joined(separator: "\n")
    }

    /// New GitHub issue, to be completed with a couple of lines and submitted.
    static func openIssue() {
        guard let repo = Updater.repo else { copyToClipboard(); return }
        let body = "**What happened?**\n\n\n**What were you doing?**\n\n\n---\n" + text
        var c = URLComponents(string: "https://github.com/\(repo)/issues/new")!
        c.queryItems = [URLQueryItem(name: "title", value: CrashReporter.lastCrash == nil ? "" : "Unexpected quit"),
                        URLQueryItem(name: "body", value: String(body.prefix(6000)))] // URL length limit
        if let url = c.url { NSWorkspace.shared.open(url) }
    }

    static func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    static func revealLog() {
        if FileManager.default.fileExists(atPath: Log.file.path) {
            NSWorkspace.shared.activateFileViewerSelecting([Log.file])
        } else {
            NSWorkspace.shared.open(Log.folder.deletingLastPathComponent())
        }
    }

    private static var machine: String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.model", &model, &size, nil, 0)
        #if arch(arm64)
        let arch = "Apple Silicon"
        #else
        let arch = "Intel"
        #endif
        return "\(String(cString: model)), \(arch)"
    }
}
