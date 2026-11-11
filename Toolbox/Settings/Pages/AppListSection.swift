import Cocoa
import SwiftUI
import UniformTypeIdentifiers

/// A list of apps chosen by the user (by bundle identifier), with their icons: add one of the open apps
/// or pick them from Applications, remove them with the red button. Used wherever some apps are exceptions.
struct AppListSection: View {
    let header: LocalizedStringKey
    let footer: LocalizedStringKey
    let empty: LocalizedStringKey
    var neverOffered: Set<String> = []
    let load: () -> [String]
    let save: ([String]) -> Void
    @State private var ids: [String] = []

    private var running: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil
                && !ids.contains($0.bundleIdentifier!) && !neverOffered.contains($0.bundleIdentifier!) }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    var body: some View {
        Section {
            if ids.isEmpty {
                Text(empty).foregroundStyle(.secondary)
            }
            ForEach(ids, id: \.self) { id in
                HStack {
                    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 20, height: 20)
                        Text(FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""))
                    } else {
                        Text(id).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { update(ids.filter { $0 != id }) } label: { Image(systemName: "minus.circle.fill").foregroundStyle(.red) }
                        .buttonStyle(.plain).help(String(localized: "Remove from the list"))
                }
            }
            HStack {
                Menu("Add an open app") {
                    ForEach(running, id: \.processIdentifier) { app in
                        Button(app.localizedName ?? app.bundleIdentifier!) { update(ids + [app.bundleIdentifier!]) }
                    }
                }
                .fixedSize()
                Button("Choose from Applications…") { pick() }
            }
        } header: {
            Text(header)
        } footer: {
            Text(footer).font(.callout).foregroundStyle(.secondary)
        }
        .onAppear { ids = load() }
    }

    private func update(_ list: [String]) {
        ids = list
        save(list)
    }

    private func pick() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        let new = panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }.filter { !ids.contains($0) }
        update(ids + new)
    }
}
