import Cocoa
import Security

/// Updates from GitHub: reads the latest release of the repository set in Info.plist
/// (key ToolboxGitHubRepo, e.g. "username/Toolbox"), downloads the attached zip, checks that it is
/// signed with the same certificate as this copy, replaces the app and relaunches it.
/// No personal data is sent: just a public request to the GitHub API.
final class Updater: ObservableObject {
    static let shared = Updater()

    struct Release: Equatable {
        let version: String
        let notes: String
        let page: URL
        let zip: URL?
        var important = false
        var importantMessage: String?
    }

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case noReleases
        case available(Release)
        case installing(String)
        case failed(String)
    }

    @Published private(set) var state: State = .idle {
        didSet { if case .failed(let message) = state { Log.error("updates: \(message)") } }
    }

    var isUpdateAvailable: Bool {
        if case .available = state { return true }
        return false
    }
    @Published private(set) var lastCheck: Date? = UserDefaults.standard.object(forKey: Pref.lastUpdateCheck) as? Date

    static var repo: String? {
        guard let r = Bundle.main.object(forInfoDictionaryKey: "ToolboxGitHubRepo") as? String,
              r.split(separator: "/").count == 2, !r.contains("NOMEUTENTE") else { return nil }
        return r
    }
    /// Ready to check: repository set (or a local test URL).
    static var configured: Bool { repo != nil || UserDefaults.standard.string(forKey: Pref.updateFeedOverride) != nil }
    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }
    /// The user can also turn off alerts for important versions.
    /// When on, Toolbox checks once a day and installs updates by itself (off by default).
    static var autoInstall: Bool { UserDefaults.standard.bool(forKey: Pref.autoInstallUpdates) }

    static var importantAlerts: Bool {
        UserDefaults.standard.object(forKey: Pref.importantUpdateAlerts) as? Bool ?? true
    }

    /// Who requested the check.
    enum Trigger { case user, settingsOpened, background }

    private var timer: Timer?

    /// Normally no update is offered in the background: regular versions only show up when opening
    /// settings, and the background check only looks for versions marked as important
    /// (see release.sh --importante) to notify about them. With "Install automatically", everything is installed.
    func start() {
        announceCompletedUpdate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in self?.backgroundCheckIfDue() }
        let t = Timer(timeInterval: 3 * 3600, repeats: true) { [weak self] _ in self?.backgroundCheckIfDue() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func backgroundCheckIfDue() {
        guard Self.importantAlerts || Self.autoInstall, Self.configured else { return }
        let last = UserDefaults.standard.object(forKey: Pref.lastBackgroundUpdateCheck) as? Date
        if let last, Date().timeIntervalSince(last) < 12 * 3600 { return }
        UserDefaults.standard.set(Date(), forKey: Pref.lastBackgroundUpdateCheck)
        check(.background)
    }

    /// When settings open: checks, but no more than once every 15 minutes.
    func settingsOpened() {
        guard Self.configured else { return }
        switch state {
        case .idle, .failed: break
        default: if let last = lastCheck, Date().timeIntervalSince(last) < 15 * 60 { return }
        }
        check(.settingsOpened)
    }

    // MARK: Checking

    func check(_ trigger: Trigger) {
        // for local testing only: an alternative URL (the signature is still verified)
        let override = UserDefaults.standard.string(forKey: Pref.updateFeedOverride).flatMap(URL.init(string:))
        guard let url = override ?? Self.repo.flatMap({ URL(string: "https://api.github.com/repos/\($0)/releases/latest") }) else {
            if trigger == .user { state = .failed(String(localized: "The GitHub repository isn't configured yet.")) }
            return
        }
        if case .checking = state { return }
        if case .installing = state { return }
        let previous = state
        if trigger != .background { state = .checking }
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("Toolbox-Updater", forHTTPHeaderField: "User-Agent")
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.timeoutInterval = 20
        URLSession.shared.dataTask(with: req) { data, response, error in
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let result: State
            if let error {
                result = .failed(String(localized: "Can't connect to GitHub (\(error.localizedDescription))."))
            } else if code == 404 {
                result = .noReleases
            } else if code != 200 {
                result = .failed(String(localized: "GitHub responded with error \(code). Try again later."))
            } else if let data, let rel = Self.parse(data) {
                result = Self.isNewer(rel.version, than: Self.currentVersion) ? .available(rel) : .upToDate
            } else {
                result = .failed(String(localized: "Couldn't read the response from GitHub."))
            }
            DispatchQueue.main.async { self.finishCheck(result, trigger: trigger, previous: previous) }
        }.resume()
    }

    private func finishCheck(_ result: State, trigger: Trigger, previous: State) {
        if case .failed = result {
            // a background error must not show up in settings
            state = trigger == .background ? previous : result
            return
        }
        state = result
        let now = Date()
        lastCheck = now
        UserDefaults.standard.set(now, forKey: Pref.lastUpdateCheck)

        if trigger == .background, Self.autoInstall, case .available(let rel) = result, rel.zip != nil {
            install(rel) // silently: after the relaunch a notification says what changed
            return
        }
        // notify only for important versions, once per version
        guard Self.importantAlerts, case .available(let rel) = result, rel.important else { return }
        let d = UserDefaults.standard
        guard d.string(forKey: Pref.notifiedUpdateVersion) != rel.version else { return }
        d.set(rel.version, forKey: Pref.notifiedUpdateVersion)
        let content = NotificationContent(id: "update-\(rel.version)", appName: "Toolbox",
                                          title: String(localized: "Important update: Toolbox \(rel.version)"),
                                          subtitle: "",
                                          body: (rel.importantMessage ?? String(localized: "Updating is recommended."))
                                              + " " + String(localized: "Click here to update."),
                                          icon: NSApp.applicationIconImage)
        content.action = { (NSApp.delegate as? AppDelegate)?.openSettings(section: .updates) }
        NotificationPresenter.shared.show(content, original: nil)
    }

    /// A version is important if its notes contain the hidden marker (not visible on GitHub)
    /// <!-- toolbox:importante: message for the notification -->
    private static let importantMark = try! NSRegularExpression(
        pattern: "<!--\\s*toolbox:importante\\s*(?::\\s*([\\s\\S]*?))?\\s*-->", options: [.caseInsensitive])

    static func parse(_ data: Data) -> Release? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let page = (json["html_url"] as? String).flatMap(URL.init(string:)) else { return nil }
        let assets = json["assets"] as? [[String: Any]] ?? []
        let zip = assets.first { ($0["name"] as? String ?? "").lowercased().hasSuffix(".zip") }
            .flatMap { $0["browser_download_url"] as? String }
            .flatMap(URL.init(string:))
        let version = tag.hasPrefix("v") || tag.hasPrefix("V") ? String(tag.dropFirst()) : tag
        var notes = json["body"] as? String ?? ""
        var important = false
        var message: String?
        let ns = notes as NSString
        if let m = importantMark.firstMatch(in: notes, range: NSRange(location: 0, length: ns.length)) {
            important = true
            if m.range(at: 1).location != NSNotFound {
                let text = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { message = text }
            }
            notes = ns.replacingCharacters(in: m.range, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return Release(version: version, notes: notes, page: page, zip: zip,
                       important: important, importantMessage: message)
    }

    /// "1.10" is newer than "1.9"; "1.2" and "1.2.0" are equal.
    static func isNewer(_ a: String, than b: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            s.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        }
        let x = parts(a), y = parts(b)
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    // MARK: Installation

    func install(_ rel: Release) {
        guard let zip = rel.zip else { NSWorkspace.shared.open(rel.page); return }
        state = .installing(String(localized: "Downloading…"))
        URLSession.shared.downloadTask(with: zip) { tmp, response, error in
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard let tmp, error == nil, code == 200 else {
                DispatchQueue.main.async {
                    let detail = error.map { " (\($0.localizedDescription))" } ?? ""
                    self.state = .failed(String(localized: "Download failed\(detail)."))
                }
                return
            }
            // the temporary file disappears on return: move it right away
            let work = FileManager.default.temporaryDirectory
                .appendingPathComponent("toolbox-update-\(UUID().uuidString)", isDirectory: true)
            let file = work.appendingPathComponent("Toolbox.zip")
            do {
                try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: tmp, to: file)
            } catch {
                DispatchQueue.main.async { self.state = .failed(String(localized: "Can't save the download.")) }
                return
            }
            let outcome = Self.prepareAndReplace(zip: file, in: work, expected: rel.version)
            DispatchQueue.main.async {
                switch outcome {
                case .success(let app): self.relaunch(app)
                case .failure(let msg): self.state = .failed(msg.text)
                }
            }
        }.resume()
    }

    private struct Message: Error { let text: String }

    /// Extracts the zip, verifies the signature and replaces the installed app. Runs off the main thread.
    private static func prepareAndReplace(zip: URL, in work: URL, expected: String) -> Result<URL, Message> {
        let fm = FileManager.default
        let out = work.appendingPathComponent("estratto", isDirectory: true)
        guard run("/usr/bin/ditto", ["-x", "-k", zip.path, out.path]) == 0 else {
            return .failure(Message(text: String(localized: "The downloaded zip is damaged.")))
        }
        let found = (try? fm.contentsOfDirectory(at: out, includingPropertiesForKeys: nil))?
            .first { $0.pathExtension == "app" }
        guard let newApp = found, let bundle = Bundle(url: newApp) else {
            return .failure(Message(text: String(localized: "The zip doesn't contain Toolbox.app.")))
        }
        guard bundle.bundleIdentifier == Bundle.main.bundleIdentifier else {
            return .failure(Message(text: String(localized: "The zip contains an app other than Toolbox.")))
        }
        let newVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        guard isNewer(newVersion, than: currentVersion) else {
            return .failure(Message(text: String(localized: "The zip contains version \(newVersion), which isn't newer than this one.")))
        }
        if let problem = signatureProblem(newApp) { return .failure(Message(text: problem)) }

        _ = run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", newApp.path])
        let installed = Bundle.main.bundleURL
        do {
            _ = try fm.replaceItemAt(installed, withItemAt: newApp, backupItemName: "Toolbox-precedente.app",
                                     options: [])
        } catch {
            return .failure(Message(text: String(localized: "Can't replace the app: \(error.localizedDescription)")))
        }
        try? fm.removeItem(at: work)
        return .success(installed)
    }

    /// The new version must satisfy this copy's "designated requirement": same identifier and
    /// same certificate. This way a tampered file isn't installed, and the Accessibility and
    /// Screen Recording permissions stay valid after the update.
    private static func signatureProblem(_ app: URL) -> String? {
        var me: SecCode?
        var meStatic: SecStaticCode?
        var requirement: SecRequirement?
        guard SecCodeCopySelf([], &me) == errSecSuccess, let me,
              SecCodeCopyStaticCode(me, [], &meStatic) == errSecSuccess, let meStatic,
              SecCodeCopyDesignatedRequirement(meStatic, [], &requirement) == errSecSuccess, let requirement else {
            return String(localized: "Can't read the signature of this copy of Toolbox.")
        }
        var info: CFDictionary?
        if SecCodeCopySigningInformation(meStatic, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
           let dict = info as? [String: Any], (dict[kSecCodeInfoCertificates as String] as? [Any] ?? []).isEmpty {
            return String(localized: "This copy of Toolbox has no certificate (ad-hoc signature): download the new version from the GitHub page.")
        }
        var newCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &newCode) == errSecSuccess, let newCode else {
            return String(localized: "The new version isn't signed.")
        }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)
        guard SecStaticCodeCheckValidity(newCode, flags, requirement) == errSecSuccess else {
            return String(localized: "The new version's signature doesn't match Toolbox's: update canceled for safety.")
        }
        return nil
    }

    /// On the first launch after an update: a notification with the new version.
    private func announceCompletedUpdate() {
        let d = UserDefaults.standard
        guard let from = d.string(forKey: Pref.updatedFromVersion) else { return }
        d.removeObject(forKey: Pref.updatedFromVersion)
        guard Self.isNewer(Self.currentVersion, than: from) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            let content = NotificationContent(id: "updated-\(Self.currentVersion)", appName: "Toolbox",
                                              title: String(localized: "Toolbox has been updated to version \(Self.currentVersion)"),
                                              subtitle: "", body: String(localized: "Click here to see what's new."),
                                              icon: NSApp.applicationIconImage)
            content.action = { (NSApp.delegate as? AppDelegate)?.openSettings(section: .updates) }
            NotificationPresenter.shared.show(content, original: nil)
        }
    }

    /// Quits Power (it runs from the old bundle) and reopens Toolbox as soon as this copy has exited.
    private func relaunch(_ app: URL) {
        state = .installing(String(localized: "Restarting…"))
        Log.info("update installed: \(Self.currentVersion) → new version, relaunching")
        NSRunningApplication.runningApplications(withBundleIdentifier: "it.saind.toolbox.power").forEach { $0.terminate() }
        let d = UserDefaults.standard
        d.removeObject(forKey: Pref.notifiedUpdateVersion)
        d.set(Self.currentVersion, forKey: Pref.updatedFromVersion)
        Relauncher.relaunch(app, background: true)
    }

    @discardableResult
    private static func run(_ tool: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }
}
