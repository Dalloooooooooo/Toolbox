import Cocoa

extension String {
    /// Without invisible formatting characters (e.g. the U+200E macOS puts in front of "WhatsApp"):
    /// otherwise looking up the app by name fails (no icon, no color).
    var withoutInvisibles: String {
        String(String.UnicodeScalarView(unicodeScalars.filter { $0.properties.generalCategory != .format }))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
