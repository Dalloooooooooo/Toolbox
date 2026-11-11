import Cocoa
import SwiftUI

/// The settings pages, in the order they appear in the sidebar.
/// To add a page: a new case here, its label, its icon (SF Symbols) and its view in `page`.
enum SettingsSection: String, CaseIterable, Identifiable, Hashable {
    case switcher, snap, zones, desktop, dock, power, apps, finder, keyboard, notifications, general, updates
    var id: String { rawValue }

    /// The pages at the top of the sidebar.
    static var main: [SettingsSection] { allCases.filter { !footer.contains($0) } }
    /// The pages at the bottom of the sidebar, above the version number.
    static let footer: [SettingsSection] = [.general, .updates]

    var label: String {
        switch self {
        case .switcher: String(localized: "Switcher")
        case .snap: String(localized: "Window Snapping")
        case .zones: String(localized: "Zones")
        case .desktop: String(localized: "Desktop")
        case .dock: String(localized: "Dock")
        case .power: "Power"
        case .apps: String(localized: "Quitting Apps")
        case .finder: String(localized: "Finder")
        case .keyboard: String(localized: "Keyboard")
        case .notifications: String(localized: "Notifications")
        case .general: String(localized: "General")
        case .updates: String(localized: "Updates")
        }
    }

    var icon: String {
        switch self {
        case .switcher: "rectangle.on.rectangle"
        case .snap: "rectangle.split.2x1"
        case .zones: "" // drawn: see `image`
        case .desktop: "hand.wave"
        case .dock: "dock.rectangle"
        case .power: "power"
        case .apps: "xmark.app"
        case .finder: "folder"
        case .keyboard: "keyboard"
        case .notifications: "bell.badge"
        case .general: "gearshape"
        case .updates: "arrow.down.circle"
        }
    }

    /// The sidebar icon: an SF Symbol, or a drawing for pages that don't have a fitting one.
    var image: Image {
        switch self {
        case .zones: Image(nsImage: ZonesIcon.image).renderingMode(.template)
        default: Image(systemName: icon)
        }
    }

    @ViewBuilder var page: some View {
        switch self {
        case .switcher: SwitcherPage()
        case .snap: SnapPage()
        case .zones: ZonesPage()
        case .desktop: DesktopPage()
        case .dock: DockPage()
        case .power: PowerPage()
        case .apps: AppsPage()
        case .finder: FinderPage()
        case .keyboard: KeyboardPage()
        case .notifications: NotificationsPage()
        case .general: GeneralPage()
        case .updates: UpdatesPage()
        }
    }
}

struct SettingsView: View {
    @AppStorage(Pref.settingsSection) private var selection = SettingsSection.switcher.rawValue
    @ObservedObject private var updater = Updater.shared

    private var section: SettingsSection { SettingsSection(rawValue: selection) ?? .switcher }

    var body: some View {
        NavigationSplitView {
            Sidebar(selection: $selection, updateAvailable: updater.isUpdateAvailable)
                .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 290)
        } detail: {
            section.page // each page is a Form that scrolls by itself if it doesn't fit vertically
                .navigationTitle(section.label)
                .safeAreaInset(edge: .top, spacing: 0) {
                    if case .available(let release) = updater.state, section != .updates {
                        UpdateBanner(release: release) { selection = SettingsSection.updates.rawValue }
                    }
                }
        }
        .frame(minWidth: 680, minHeight: 420)
    }
}

/// Sidebar: logo and name at the top, the feature pages, and at the bottom General and Updates
/// (same look as the others: they are a second list sharing the same selection) above the version.
private struct Sidebar: View {
    @Binding var selection: String
    let updateAvailable: Bool

    private var binding: Binding<SettingsSection?> {
        Binding(get: { SettingsSection(rawValue: selection) }, set: { if let s = $0 { selection = s.rawValue } })
    }

    var body: some View {
        VStack(spacing: 0) {
            AppHeader()
            List(SettingsSection.main, selection: binding) { row($0) }
            List(SettingsSection.footer, selection: binding) { row($0) }
                .frame(height: CGFloat(SettingsSection.footer.count) * 28 + 20)
                .scrollDisabled(true)
            Text("Version \(Updater.currentVersion)")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
        }
    }

    private func row(_ item: SettingsSection) -> some View {
        HStack {
            Label { Text(item.label) } icon: { item.image }
            Spacer()
            if item == .updates && updateAvailable { Circle().fill(.blue).frame(width: 8, height: 8) }
        }
        .tag(item)
    }
}

private struct AppHeader: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 40, height: 40)
            Text("Toolbox").font(.title3.weight(.semibold))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }
}
