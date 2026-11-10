import Cocoa

/// If Toolbox quit unexpectedly, it says so with a notification on the next launch: one click opens a
/// prefilled problem report (see ProblemReport). The data comes from the reports macOS itself writes
/// to ~/Library/Logs/DiagnosticReports; Toolbox keeps only a summary (error type and functions).
enum CrashReporter {
    struct Crash: Codable {
        let date: Date
        let version: String
        let kind: String
        let frames: [String]
    }

    static var lastCrash: Crash? {
        UserDefaults.standard.data(forKey: Pref.lastCrash).flatMap { try? JSONDecoder().decode(Crash.self, from: $0) }
    }

    static func checkOnLaunch() {
        DispatchQueue.global(qos: .utility).async {
            let d = UserDefaults.standard
            let since = d.object(forKey: Pref.lastCrashCheck) as? Date ?? Date()
            d.set(Date(), forKey: Pref.lastCrashCheck)
            guard let crash = newestCrash(since: since) else { return }
            if let data = try? JSONEncoder().encode(crash) { d.set(data, forKey: Pref.lastCrash) }
            Log.error("unexpected quit on \(crash.date): \(crash.kind) — \(crash.frames.prefix(3).joined(separator: " ← "))")
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { notify() }
        }
    }

    private static func notify() {
        let content = NotificationContent(id: "crash", appName: "Toolbox",
                                          title: String(localized: "Toolbox quit unexpectedly"),
                                          subtitle: "",
                                          body: String(localized: "Click here to report it: a prefilled report opens, you just need to submit it."),
                                          icon: NSApp.applicationIconImage)
        content.action = { ProblemReport.openIssue() }
        NotificationPresenter.shared.show(content, original: nil)
    }

    /// The most recent macOS report about Toolbox, if it is newer than `since`.
    private static func newestCrash(since: Date) -> Crash? {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/DiagnosticReports")
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let newest = files
            .filter { $0.lastPathComponent.hasPrefix("Toolbox") && $0.pathExtension == "ips" }
            .compactMap { url -> (URL, Date)? in
                let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                return date.map { (url, $0) }
            }
            .filter { $0.1 > since }
            .max { $0.1 < $1.1 }
        guard let (url, date) = newest, let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return parse(text, date: date)
    }

    /// .ips format: one JSON header line, then the JSON body.
    static func parse(_ text: String, date: Date) -> Crash? {
        guard let newline = text.firstIndex(of: "\n"),
              let header = try? JSONSerialization.jsonObject(with: Data(text[..<newline].utf8)) as? [String: Any],
              let body = try? JSONSerialization.jsonObject(with: Data(text[text.index(after: newline)...].utf8)) as? [String: Any]
        else { return nil }
        let exception = body["exception"] as? [String: Any]
        let kind = [exception?["type"] as? String, exception?["signal"] as? String].compactMap { $0 }.joined(separator: " / ")
        let images = body["usedImages"] as? [[String: Any]] ?? []
        let threads = body["threads"] as? [[String: Any]] ?? []
        let crashed = threads.first { $0["triggered"] as? Bool == true }
        let frames = (crashed?["frames"] as? [[String: Any]] ?? []).prefix(12).map { frame -> String in
            let image = (frame["imageIndex"] as? Int).flatMap { $0 < images.count ? images[$0]["name"] as? String : nil } ?? "?"
            return "\(image) \(frame["symbol"] as? String ?? "?")"
        }
        return Crash(date: date, version: header["app_version"] as? String ?? "?", kind: kind.isEmpty ? "?" : kind,
                     frames: Array(frames))
    }
}
