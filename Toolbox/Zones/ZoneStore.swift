import Cocoa

/// The layouts (templates with their settings, and the user's own) and which one each monitor uses.
/// Saved as JSON in Toolbox's preferences, so uninstalling removes them with the rest.
final class ZoneStore: ObservableObject {
    static let shared = ZoneStore()

    @Published private(set) var layouts: [ZoneLayout] = []
    /// Monitor (see `key(for:)`) → layout id.
    @Published private(set) var applied: [String: UUID] = [:]

    private struct Saved: Codable {
        var layouts: [ZoneLayout]
        var applied: [String: UUID]
        var version: Int?
    }
    /// 2: no space between zones by default.
    private static let version = 2

    private init() {
        if let data = UserDefaults.standard.data(forKey: Pref.zonesData),
           let saved = try? JSONDecoder().decode(Saved.self, from: data) {
            layouts = saved.layouts
            applied = saved.applied
            if (saved.version ?? 1) < 2 { // saved before "no space" became the default
                for i in layouts.indices { layouts[i].showSpacing = false }
            }
        }
        // every template is always there, in the same order
        let templates = ZoneLayout.Kind.allCases.filter(\.isTemplate).map { kind in
            layouts.first { $0.id == ZoneLayout.templateIDs[kind] } ?? .template(kind)
        }
        layouts = templates + layouts.filter { !$0.kind.isTemplate }
    }

    var templates: [ZoneLayout] { layouts.filter { $0.kind.isTemplate } }
    var custom: [ZoneLayout] { layouts.filter { !$0.kind.isTemplate } }

    func layout(_ id: UUID) -> ZoneLayout? { layouts.first { $0.id == id } }

    /// The layout of a monitor. Until you choose one, like PowerToys: a Priority Grid with three zones.
    func layout(for screen: NSScreen) -> ZoneLayout {
        applied[Self.key(for: screen)].flatMap(layout) ?? layout(ZoneLayout.templateIDs[.priorityGrid]!)!
    }

    func apply(_ id: UUID, to screen: NSScreen) {
        applied[Self.key(for: screen)] = id
        save()
    }

    /// Adds or replaces.
    func put(_ layout: ZoneLayout) {
        var l = layout
        if let k = l.hotkey { // a number belongs to one layout only
            for i in layouts.indices where layouts[i].hotkey == k && layouts[i].id != l.id { layouts[i].hotkey = nil }
        }
        if !l.kind.isTemplate { l.hotkey = l.hotkey.map { min(9, max(0, $0)) } }
        if let i = layouts.firstIndex(where: { $0.id == l.id }) { layouts[i] = l } else { layouts.append(l) }
        save()
    }

    func delete(_ id: UUID) {
        guard layout(id)?.kind.isTemplate == false else { return }
        layouts.removeAll { $0.id == id }
        applied = applied.filter { $0.value != id }
        save()
    }

    func layout(hotkey: Int) -> ZoneLayout? { layouts.first { $0.hotkey == hotkey } }

    /// A name for a new layout: "Custom layout 1", 2, …
    func newName() -> String {
        var n = custom.count + 1
        while custom.contains(where: { $0.name == String(localized: "Custom layout \(n)") }) { n += 1 }
        return String(localized: "Custom layout \(n)")
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(Saved(layouts: layouts, applied: applied, version: Self.version)) else { return }
        UserDefaults.standard.set(data, forKey: Pref.zonesData)
    }

    /// A stable name for a monitor: the same after restarts and when it's plugged into another port.
    static func key(for screen: NSScreen) -> String {
        guard let n = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(n.uint32Value)?.takeRetainedValue() else {
            return screen.localizedName
        }
        return CFUUIDCreateString(nil, uuid) as String
    }
}
