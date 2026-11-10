import Foundation

/// Interface language: the system one, or one chosen in settings.
/// Applies to Toolbox and its helper apps (Power, File Explorer); takes effect after a restart.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, english = "en", italian = "it"
    var id: String { rawValue }

    /// Each language name is written in that language, as macOS does.
    var label: String {
        switch self {
        case .system: String(localized: "System Language")
        case .english: "English"
        case .italian: "Italiano"
        }
    }

    private static let domains = [Bundle.main.bundleIdentifier ?? "it.saind.switchtab",
                                  "it.saind.toolbox.power", "it.saind.toolbox.explorer"]

    /// The current choice (read only from Toolbox's preferences, not from the global system ones).
    static var current: AppLanguage {
        // persistentDomain: only Toolbox's own value (CFPreferencesCopyAppValue would fall back to the system's)
        let value = UserDefaults.standard.persistentDomain(forName: domains[0])?["AppleLanguages"] as? [String]
        return value?.first.flatMap { code in allCases.first { $0 != .system && code.hasPrefix($0.rawValue) } } ?? .system
    }

    static func apply(_ language: AppLanguage) {
        let value: CFPropertyList? = language == .system ? nil : [language.rawValue] as CFArray
        for domain in domains {
            CFPreferencesSetAppValue("AppleLanguages" as CFString, value, domain as CFString)
            CFPreferencesAppSynchronize(domain as CFString)
        }
        Log.info("interface language: \(language.rawValue)")
    }
}
