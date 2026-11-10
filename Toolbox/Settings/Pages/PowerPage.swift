import Cocoa
import SwiftUI

struct PowerPage: View {
    @AppStorage(Pref.powerButton) private var powerButton = true
    @AppStorage(Pref.powerShowLock) private var showLock = true
    @AppStorage(Pref.powerShowDisplayOff) private var showDisplayOff = false
    @AppStorage(Pref.powerShowSleep) private var showSleep = true
    @AppStorage(Pref.powerShowLogout) private var showLogout = false
    @AppStorage(Pref.powerShowRestart) private var showRestart = true
    @AppStorage(Pref.powerShowShutdown) private var showShutdown = true
    @AppStorage(Pref.powerShowTimer) private var showTimer = true
    @AppStorage(Pref.powerConfirm) private var confirm = false
    @AppStorage(Pref.powerIconColor) private var iconColor = PowerIconVariant.yellow.rawValue
    @State private var pinned = PowerButton.isPinned

    /// previews of the variants, made from the original icon inside Power.app
    private static let variantImages: [PowerIconVariant: NSImage] = {
        let bundle = Bundle(url: Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/Power.app"))
        guard let bundle, let base = PowerIconVariant.baseImage(in: bundle) else { return [:] }
        return Dictionary(uniqueKeysWithValues: PowerIconVariant.allCases.map { ($0, $0.apply(to: base)) })
    }()

    var body: some View {
        Form {
            Section("Power button in the Dock") {
                Toggle("Show the Power button", isOn: $powerButton)
                LabeledContent("Position") {
                    HStack {
                        Text(pinned ? String(localized: "Pinned, right after the Finder") : String(localized: "Not pinned in the Dock")).foregroundStyle(.secondary)
                        if pinned {
                            Button("Remove from Dock") { PowerButton.unpin(); refreshPinned() }
                        } else {
                            Button("Place next to the Finder") { PowerButton.pinNextToFinder(); refreshPinned() }
                        }
                    }
                }
                .disabled(!powerButton)
                Text("Left- or right-click the icon to open the menu. It can't go further left than the Finder: macOS always keeps the Finder first.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            Section("Menu items") {
                Toggle(isOn: $showLock) { Label("Lock Screen", systemImage: "lock.fill") }
                Toggle(isOn: $showDisplayOff) { Label("Turn Off Display", systemImage: "display") }
                Toggle(isOn: $showSleep) { Label("Sleep", systemImage: "moon.fill") }
                Toggle(isOn: $showLogout) { Label("Log Out", systemImage: "person.crop.circle.badge.xmark") }
                Toggle(isOn: $showRestart) { Label("Restart", systemImage: "arrow.clockwise") }
                Toggle(isOn: $showShutdown) { Label("Shut Down", systemImage: "power") }
                Toggle(isOn: $showTimer) { Label("Shut Down In… (15 min, 30 min, 1 hour, 2 hours)", systemImage: "timer") }
                Text("With a scheduled shutdown, the Power icon shows the minutes left; you can cancel it from the menu.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .disabled(!powerButton)

            Section("Safety") {
                Toggle("Ask for confirmation before shutting down, restarting or logging out", isOn: $confirm)
            }
            .disabled(!powerButton)

            Section("Appearance") {
                LabeledContent("Icon color") {
                    HStack(spacing: 6) {
                        ForEach(PowerIconVariant.allCases) { v in
                            Button { iconColor = v.rawValue } label: {
                                Image(nsImage: Self.variantImages[v] ?? NSImage())
                                    .resizable().frame(width: 40, height: 40)
                                    .padding(3)
                                    .overlay(RoundedRectangle(cornerRadius: 12)
                                        .strokeBorder(iconColor == v.rawValue ? Color.accentColor : .clear, lineWidth: 2.5))
                            }
                            .buttonStyle(.plain)
                            .help(v.label)
                        }
                    }
                }
                .onChange(of: iconColor) { _, _ in PowerButton.notifyChanged() }
            }
            .disabled(!powerButton)
        }
        .formStyle(.grouped)
        .onAppear { refreshPinned() }
    }

    private func refreshPinned() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { pinned = PowerButton.isPinned }
    }
}
