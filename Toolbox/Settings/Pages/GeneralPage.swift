import SwiftUI
import ServiceManagement

/// Startup, language, permissions, problem reporting and uninstalling.
struct GeneralPage: View {
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled
    @State private var language = AppLanguage.current
    @State private var languageChanged = false
    @State private var accessibility = AXIsProcessTrusted()
    @State private var screenRecording = CGPreflightScreenCaptureAccess()
    @State private var copied = false
    private let refresh = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Open at login", isOn: $openAtLogin)
                    .onChange(of: openAtLogin) { _, on in
                        try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                        openAtLogin = SMAppService.mainApp.status == .enabled
                    }
            }

            Section("Language") {
                Picker("Toolbox language", selection: $language) {
                    ForEach(AppLanguage.allCases) { Text($0.label).tag($0) }
                }
                .onChange(of: language) { _, new in
                    AppLanguage.apply(new)
                    languageChanged = true
                }
                if languageChanged {
                    HStack {
                        Text("The new language takes effect after Toolbox restarts.")
                            .font(.callout).foregroundStyle(.secondary)
                        Spacer()
                        Button("Restart now") { Relauncher.relaunch() }
                    }
                }
            }

            Section("Permissions") {
                PermissionRow(title: "Accessibility", detail: "Keys, windows and Dock", granted: accessibility,
                              open: Permissions.openAccessibility)
                PermissionRow(title: "Screen Recording", detail: "Only for window previews",
                              granted: screenRecording, open: Permissions.openScreenRecording)
            }

            Section("Problems") {
                if let crash = CrashReporter.lastCrash {
                    Label("Last unexpected quit: \(crash.date.formatted(date: .abbreviated, time: .shortened))",
                          systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
                Text("Something wrong? “Report a problem” opens a pre-filled report with the version, the system and the Toolbox log: add a couple of lines about what happened and send it. The log contains no personal data.")
                    .font(.callout).foregroundStyle(.secondary)
                HStack {
                    Button("Report a problem…") { ProblemReport.openIssue() }
                    Button(copied ? String(localized: "Copied") : String(localized: "Copy info")) {
                        ProblemReport.copyToClipboard()
                        copied = true
                    }
                    Button("Show log") { ProblemReport.revealLog() }
                }
            }

            Section("Uninstall") {
                Text("Restores everything Toolbox changed (Finder, macOS window tiling, ⌘Tab, Dock) and deletes its settings, permissions and logs. The app goes to the Trash.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Uninstall Toolbox…", role: .destructive) { Uninstaller.confirmAndUninstall() }
            }
        }
        .formStyle(.grouped)
        .onReceive(refresh) { _ in
            accessibility = AXIsProcessTrusted()
            screenRecording = CGPreflightScreenCaptureAccess()
        }
    }
}

private struct PermissionRow: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let granted: Bool
    let open: () -> Void

    var body: some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(granted ? .green : .orange)
            VStack(alignment: .leading) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(granted ? String(localized: "Open") : String(localized: "Grant…"), action: open)
        }
    }
}
