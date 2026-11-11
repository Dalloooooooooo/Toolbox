import SwiftUI

/// Clearing the desktop like on Windows: show it (shake the mouse hard, or Win+D) and Aero Shake.
struct DesktopPage: View {
    @AppStorage(Pref.showDesktopShake) private var shake = true
    @AppStorage(Pref.showDesktopKey) private var desktopKey = true
    @AppStorage(Pref.aeroShake) private var aeroShake = true
    @AppStorage(Pref.showDesktopMinimizes) private var minimizes = true

    var body: some View {
        Form {
            Section("Show the desktop") {
                HStack {
                    Toggle("Shake the mouse hard while holding", isOn: $shake)
                    Spacer()
                    ShortcutField(pref: Pref.showDesktopShakeHold, default: .defaultShakeHold, mode: .hold).disabled(!shake)
                }
                HStack {
                    Toggle("Shortcut (like Win + D)", isOn: $desktopKey)
                    Spacer()
                    ShortcutField(pref: Pref.showDesktopShortcut, default: .defaultShowDesktop).disabled(!desktopKey)
                }
                Picker("Windows", selection: $minimizes) {
                    Text("Minimize them all into the Dock").tag(true)
                    Text("Move them aside (macOS Show Desktop)").tag(false)
                }
                Text("Do it again and the windows come back as they were, the one in front back in front. Shake it hard, left and right: normal movements do nothing. To change a key, click it and press the new one (keys, modifiers or a mouse button).")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("Aero Shake") {
                Toggle("Shake a window by its title bar to minimize all the others", isOn: $aeroShake)
                Text("Like on Windows: grab a window by its title bar and shake it hard; shake it again and the other windows come back.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
