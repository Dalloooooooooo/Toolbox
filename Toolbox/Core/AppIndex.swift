import Cocoa
import CoreServices

/// Index of all installed apps, to find them by the name shown in notifications.
/// Each app is registered under all its names: the localized one ("Calendario"), the file name
/// ("Calendar") and the ones declared by the app. Without the index, apps with a localized name can't be found.
enum AppIndex {
    private static let lock = NSLock()
    private static var paths: [String: String] = [:]   // normalized name → path
    private static var built = Date.distantPast
    private static var building = false

    /// Path of the app with that name, if any.
    static func path(for name: String) -> String? {
        let key = normalize(name)
        lock.lock(); defer { lock.unlock() }
        return paths[key]
    }

    /// Builds (or rebuilds, at most once a minute) the index. Blocking: call it in the background.
    static func build(force: Bool = false) {
        lock.lock()
        if building || (!force && Date().timeIntervalSince(built) < 60) { lock.unlock(); return }
        building = true
        lock.unlock()

        var map: [String: String] = [:]
        for url in allApps() {
            let path = url.path
            var names = [url.deletingPathExtension().lastPathComponent]
            if let item = MDItemCreateWithURL(nil, url as CFURL),
               let shown = MDItemCopyAttribute(item, kMDItemDisplayName) as? String {
                names.append(shown.hasSuffix(".app") ? String(shown.dropLast(4)) : shown)
            }
            if let b = Bundle(url: url) {
                for key in ["CFBundleDisplayName", "CFBundleName"] {
                    if let n = b.localizedInfoDictionary?[key] as? String { names.append(n) }
                    if let n = b.infoDictionary?[key] as? String { names.append(n) }
                }
            }
            for n in names {
                let k = normalize(n)
                // for the same name the first one found wins (the app folders come first)
                if !k.isEmpty, map[k] == nil { map[k] = path }
            }
        }
        lock.lock()
        paths = map
        built = Date()
        building = false
        lock.unlock()
    }

    private static func allApps() -> [URL] {
        let fm = FileManager.default
        let roots = ["/Applications", "/System/Applications", "/System/Library/CoreServices",
                     NSHomeDirectory() + "/Applications", "/System/Volumes/Preboot/Cryptexes/App/System/Applications"]
        var result: [URL] = []
        for root in roots {
            // also one level of subfolders (e.g. /Applications/Utilities, /Applications/Microsoft Office)
            guard let items = try? fm.contentsOfDirectory(at: URL(fileURLWithPath: root), includingPropertiesForKeys: nil) else { continue }
            for u in items {
                if u.pathExtension == "app" { result.append(u) }
                else if let sub = try? fm.contentsOfDirectory(at: u, includingPropertiesForKeys: nil) {
                    result += sub.filter { $0.pathExtension == "app" }
                }
            }
        }
        return result
    }

    /// Lowercase, without accents or invisible characters, and with a "plain" apostrophe (Dov’è = Dov'è).
    static func normalize(_ s: String) -> String {
        String(String.UnicodeScalarView(s.unicodeScalars.filter { $0.properties.generalCategory != .format }))
            .replacingOccurrences(of: "’", with: "'")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
