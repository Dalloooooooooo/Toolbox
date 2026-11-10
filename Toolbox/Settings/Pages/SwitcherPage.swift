import Cocoa
import SwiftUI

struct SwitcherPage: View {
    @AppStorage(Pref.previewWidth) private var previewWidth = Settings.defaultPreviewWidth
    @AppStorage(Pref.switcherModifier) private var modifier = HotkeyModifier.command.rawValue
    @AppStorage(Pref.switcherKey) private var key = HotkeyKey.tab.rawValue
    @AppStorage(Pref.titleOnTop) private var titleOnTop = true
    @AppStorage(Pref.showMinimized) private var showMinimized = true
    @AppStorage(Pref.showOtherDesktops) private var showOtherDesktops = true
    @AppStorage(Pref.closeButtonQuitsApp) private var closeButtonQuitsApp = false
    @AppStorage(Pref.backgroundPreviews) private var backgroundPreviews = true

    private var mod: HotkeyModifier { HotkeyModifier(rawValue: modifier) ?? .command }
    private var hk: HotkeyKey { HotkeyKey(rawValue: key) ?? .tab }

    var body: some View {
        Form {
            Section("Shortcut") {
                Picker("Hold down", selection: $modifier) {
                    ForEach(HotkeyModifier.allCases) { Text($0.label).tag($0.rawValue) }
                }
                Picker("and press", selection: $key) {
                    ForEach(HotkeyKey.allCases) { Text($0.label).tag($0.rawValue) }
                }
                Text("Current shortcut: \(mod.symbol) \(hk.short)  ·  add ⇧ to go backward")
                    .font(.callout).foregroundStyle(.secondary)
                if mod == .command && hk == .tab {
                    Label("Replaces the system ⌘ Tab switcher while Toolbox is running.",
                          systemImage: "info.circle")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }

            Section("Previews") {
                HStack {
                    Image(systemName: "rectangle").imageScale(.small)
                    Slider(value: $previewWidth, in: 120...480, step: 10)
                    Image(systemName: "rectangle").imageScale(.large)
                }
                HStack {
                    Text("Width: \(Int(previewWidth)) pt")
                    Spacer()
                    Button("Reset") { previewWidth = Settings.defaultPreviewWidth }
                }
                Picker("App name", selection: $titleOnTop) {
                    Text("Above the preview").tag(true)
                    Text("Below the preview").tag(false)
                }
                .pickerStyle(.segmented)
                HStack {
                    Spacer()
                    PreviewMock(width: previewWidth, titleOnTop: titleOnTop)
                    Spacer()
                }
            }

            Section("X button") {
                Picker("The X closes", selection: $closeButtonQuitsApp) {
                    Text("Only that window").tag(false)
                    Text("The whole app").tag(true)
                }
                .pickerStyle(.segmented)
                Text("From the keyboard, with the switcher open: W closes the selected window, Q quits the app.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            Section("Windows") {
                Toggle("Show windows on other desktops and full-screen apps", isOn: $showOtherDesktops)
                Text("They have a green icon (full screen) or a blue one (another desktop). Selecting one switches the Mac to that desktop.")
                    .font(.callout).foregroundStyle(.secondary)
                Toggle("Show minimized windows and hidden apps", isOn: $showMinimized)
                Text("Like on Windows: they appear at the end of the list with a yellow icon (minimized) or a gray one (hidden with ⌘H). Selecting one reopens it.")
                    .font(.callout).foregroundStyle(.secondary)
                Toggle("Remember previews of minimized windows", isOn: $backgroundPreviews)
                    .disabled(!showMinimized)
                Text("macOS doesn't draw minimized windows, so Toolbox takes a snapshot of them every few seconds while they are open. The images stay in memory only and are never saved.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

/// Life-size replica of a switcher tile.
struct PreviewMock: View {
    let width: Double
    let titleOnTop: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if titleOnTop { titleRow }
            RoundedRectangle(cornerRadius: 6)
                .fill(LinearGradient(colors: [.blue.opacity(0.5), .purple.opacity(0.5)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: width, height: width * 0.64)
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.red).padding(4)
                }
            if !titleOnTop { titleRow }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.15)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.accentColor, lineWidth: 2))
    }

    private var titleRow: some View {
        HStack(spacing: 6) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 20, height: 20)
            Text("App Name").font(.system(size: 12, weight: .medium)).lineLimit(1)
        }
    }
}
