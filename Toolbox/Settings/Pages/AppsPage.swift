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

/// The apps that stay open when their last window is closed.
struct QuitExclusionsSection: View {
    var body: some View {
        AppListSection(
            header: "Don't quit these apps",
            footer: "For these apps the red button closes only the window and the app stays open, as it normally does on a Mac. Useful for messaging apps (WhatsApp, Telegram, Mail…): if they quit completely, you stop getting their notifications.",
            empty: "No exceptions: every app quits with its last window.",
            neverOffered: ["com.apple.finder"],
            load: { Settings.quitExclusions },
            save: { Settings.quitExclusions = $0 })
    }
}
