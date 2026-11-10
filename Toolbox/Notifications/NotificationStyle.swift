import Cocoa
import SwiftUI

// MARK: - Model and style

final class NotificationContent: ObservableObject, Identifiable {
    let id: String
    let appName: String
    let title: String
    let subtitle: String
    let body: String
    @Published var icon: NSImage? { didSet { appColor = icon.flatMap(AppIcons.dominantColor) } }
    /// main color of the app icon (nil if the icon is gray or missing)
    @Published var appColor: Color?
    /// For Toolbox's own notifications (e.g. the screenshot): what to do on click.
    var action: (() -> Void)?

    init(id: String, appName: String, title: String, subtitle: String, body: String, icon: NSImage? = nil) {
        self.id = id
        self.appName = appName
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.icon = icon ?? AppIcons.cached(appName)
        self.appColor = icon.flatMap(AppIcons.dominantColor)
        if icon == nil { AppIcons.lookup(appName) { [weak self] in self?.icon = $0 } }
    }
}

enum NotificationStyleKind: String, CaseIterable, Identifiable {
    case toolbox, system
    var id: String { rawValue }
}

enum NotificationColorMode: String, CaseIterable, Identifiable {
    case none, app, custom
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: String(localized: "None")
        case .app: String(localized: "App Color")
        case .custom: String(localized: "Custom")
        }
    }
}

enum NotificationTheme: String, CaseIterable, Identifiable {
    case auto, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .auto: String(localized: "Automatic")
        case .light: String(localized: "Light")
        case .dark: String(localized: "Dark")
        }
    }
}

enum NotificationBackground: String, CaseIterable, Identifiable {
    case liquid, liquidClear, blur, solid
    var id: String { rawValue }
    var label: String {
        switch self {
        case .liquid: String(localized: "Liquid Glass")
        case .liquidClear: String(localized: "Clear Liquid Glass")
        case .blur: String(localized: "Frosted Glass")
        case .solid: String(localized: "Solid")
        }
    }
    /// Liquid Glass is available since macOS 26
    static var liquidAvailable: Bool {
        if #available(macOS 26.0, *) { true } else { false }
    }
    static var available: [NotificationBackground] { liquidAvailable ? allCases : [.blur, .solid] }
    static var defaultValue: NotificationBackground { liquidAvailable ? .liquid : .blur }
}

extension Color {
    /// "#RRGGBB" ↔ Color, to store the custom color in settings
    init?(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
        self.init(red: Double((v >> 16) & 0xff) / 255, green: Double((v >> 8) & 0xff) / 255, blue: Double(v & 0xff) / 255)
    }
    var hex: String {
        let c = NSColor(self).usingColorSpace(.sRGB) ?? .systemBlue
        return String(format: "#%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
    }
}

/// Appearance of Toolbox notifications, read from settings.
struct NotificationLook: Equatable {
    var width: Double
    var textScale: Double
    var radius: Double
    var duration: Double
    var theme: NotificationTheme
    var background: NotificationBackground
    var showIcon: Bool
    var showTimer: Bool
    var colorMode: NotificationColorMode
    var customColor: Color
    var colorIntensity: Double

    static var current: NotificationLook {
        let d = UserDefaults.standard
        return NotificationLook(
            width: d.object(forKey: Pref.notifWidth) as? Double ?? 460,
            textScale: d.object(forKey: Pref.notifTextScale) as? Double ?? 1.15,
            radius: d.object(forKey: Pref.notifRadius) as? Double ?? 26,
            duration: d.object(forKey: Pref.notifDuration) as? Double ?? 6,
            theme: NotificationTheme(rawValue: d.string(forKey: Pref.notifTheme) ?? "") ?? .auto,
            background: NotificationBackground(rawValue: d.string(forKey: Pref.notifBackground) ?? "")
                .flatMap { NotificationBackground.available.contains($0) ? $0 : nil } ?? .defaultValue,
            showIcon: d.object(forKey: Pref.notifShowIcon) as? Bool ?? true,
            showTimer: d.object(forKey: Pref.notifShowTimer) as? Bool ?? true,
            colorMode: NotificationColorMode(rawValue: d.string(forKey: Pref.notifColorMode) ?? "") ?? .app,
            customColor: Color(hex: d.string(forKey: Pref.notifCustomColor) ?? "") ?? .blue,
            colorIntensity: d.object(forKey: Pref.notifColorIntensity) as? Double ?? 0.35)
    }
}
