import Cocoa
import SwiftUI

/// Strip at the top of the settings when a new version is out: noticeable, but not interruptive.
struct UpdateBanner: View {
    let release: Updater.Release
    let open: () -> Void
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: release.important ? "exclamationmark.shield.fill" : "arrow.down.circle.fill")
                .foregroundStyle(release.important ? .orange : .blue)
            Text(release.important ? String(localized: "Important update: Toolbox \(release.version)")
                                   : String(localized: "Toolbox \(release.version) is available"))
            Spacer()
            Button("View", action: open)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }
}

struct UpdatesPage: View {
    @ObservedObject private var updater = Updater.shared
    @AppStorage(Pref.importantUpdateAlerts) private var importantAlerts = true
    @AppStorage(Pref.autoInstallUpdates) private var autoInstall = false

    var body: some View {
        Form {
            Section("Version") {
                LabeledContent("Installed version", value: Updater.currentVersion)
                if let repo = Updater.repo {
                    LabeledContent("Published on") {
                        Link("github.com/\(repo)", destination: URL(string: "https://github.com/\(repo)")!)
                    }
                }
                Toggle("Install updates automatically", isOn: $autoInstall)
                    .disabled(!Updater.configured)
                Toggle("Notify me about important updates", isOn: $importantAlerts)
                    .disabled(!Updater.configured || autoInstall)
                Text(autoInstall
                     ? String(localized: "Toolbox checks once a day and, if there's a new version, installs it and restarts on its own. A notification then tells you what changed.")
                     : String(localized: "Toolbox checks for updates only when you open these settings and never installs anything without asking. The exception is versions marked as important (for example security fixes): for those you get a notification."))
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("Status") {
                status
                HStack {
                    Button("Check now") { updater.check(.user) }
                        .disabled(!Updater.configured || busy)
                    if busy { ProgressView().controlSize(.small) }
                    Spacer()
                    if let last = updater.lastCheck {
                        Text("Last checked: \(last.formatted(date: .abbreviated, time: .shortened))")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
            if case .available(let rel) = updater.state {
                Section("What's new in version \(rel.version)") {
                    if rel.important {
                    Label(rel.importantMessage ?? String(localized: "Important update: installing it is recommended."),
                          systemImage: "exclamationmark.shield.fill")
                        .foregroundStyle(.orange)
                }
                if !rel.notes.isEmpty {
                        Text(rel.notes).font(.callout).textSelection(.enabled)
                    }
                    HStack {
                        Button(rel.zip == nil ? String(localized: "Open the download page") : String(localized: "Download and install")) {
                            updater.install(rel)
                        }
                        .buttonStyle(.borderedProminent)
                        Button("GitHub page") { NSWorkspace.shared.open(rel.page) }
                    }
                    Text("Toolbox quits and reopens on its own. Permissions stay valid because the new version is signed with the same certificate; if the signature doesn't match, the update is canceled.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var busy: Bool {
        switch updater.state {
        case .checking, .installing: true
        default: false
        }
    }

    @ViewBuilder private var status: some View {
        switch updater.state {
        case .idle:
            if !Updater.configured {
                Label("GitHub repository not configured yet", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
            } else {
                Label("Not checked yet", systemImage: "questionmark.circle").foregroundStyle(.secondary)
            }
        case .checking: Label("Checking…", systemImage: "arrow.triangle.2.circlepath")
        case .upToDate: Label("You have the latest version", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .noReleases: Label("No versions published on GitHub yet", systemImage: "tray")
            .foregroundStyle(.secondary)
        case .available(let rel): Label("Version \(rel.version) is available", systemImage: "arrow.down.circle.fill")
            .foregroundStyle(.blue)
        case .installing(let step): Label(step, systemImage: "arrow.down.circle")
        case .failed(let msg): Label(msg, systemImage: "xmark.octagon.fill").foregroundStyle(.red)
        }
    }
}
