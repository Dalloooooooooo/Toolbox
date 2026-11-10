import Cocoa
import SwiftUI
import UniformTypeIdentifiers

struct AppsPage: View {
    @AppStorage(Pref.quitOnLastWindow) private var quitOnLastWindow = true

    var body: some View {
        Form {
            Section("Quitting apps") {
                Toggle("Quit an app when you close its last window", isOn: $quitOnLastWindow)
                Text("Like on Windows: closing the last window (red button or ⌘W) really quits the app and its dot in the Dock disappears. If there are unsaved documents, the app asks you first. The Finder always stays open.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            QuitExclusionsSection()
            Section("Normally on a Mac") {
                Label("Red button / ⌘W: closes only the window", systemImage: "xmark.circle")
                Label("⌘Q: quits the app", systemImage: "power")
            }
        }
        .formStyle(.grouped)
    }
}

struct QuitExclusionsSection: View {
    @State private var ids = Settings.quitExclusions

    private var running: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil
                && !ids.contains($0.bundleIdentifier!) && $0.bundleIdentifier != "com.apple.finder" }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    var body: some View {
        Section {
            if ids.isEmpty {
                Text("No exceptions: every app quits with its last window.").foregroundStyle(.secondary)
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
                    Button { save(ids.filter { $0 != id }) } label: { Image(systemName: "minus.circle.fill").foregroundStyle(.red) }
                        .buttonStyle(.plain).help("Remove from the list")
                }
            }
            HStack {
                Menu("Add an open app") {
                    ForEach(running, id: \.processIdentifier) { app in
                        Button(app.localizedName ?? app.bundleIdentifier!) { save(ids + [app.bundleIdentifier!]) }
                    }
                }
                .fixedSize()
                Button("Choose from Applications…") { pick() }
            }
        } header: {
            Text("Don't quit these apps")
        } footer: {
            Text("For these apps the red button closes only the window and the app stays open, as it normally does on a Mac. Useful for messaging apps (WhatsApp, Telegram, Mail…): if they quit completely, you stop getting their notifications.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private func save(_ list: [String]) {
        ids = list
        Settings.quitExclusions = list
    }

    private func pick() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        let new = panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }.filter { !ids.contains($0) }
        save(ids + new)
    }
}
