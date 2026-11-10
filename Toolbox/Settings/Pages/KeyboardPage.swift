import Cocoa
import SwiftUI
import Carbon

struct KeyboardPage: View {
    @AppStorage(Pref.ctrlShortcuts) private var ctrlShortcuts = true
    @AppStorage(Pref.textKeys) private var textKeys = true
    @AppStorage(Pref.rightCommandAltGr) private var rightCommandAltGr = true
    @AppStorage(Pref.screenSnip) private var screenSnip = true
    @State private var current = KeyboardLayout.current
    @State private var enabled = KeyboardLayout.enabled

    private var proActive: Bool { current.id == KeyboardLayout.italianPro }
    private var others: [KeyboardLayout.Info] { enabled.filter { $0.id != KeyboardLayout.italianPro } }

    var body: some View {
        Form {
            Section("Keyboard layout") {
                LabeledContent("Current layout") {
                    Label(current.name, systemImage: proActive ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(proActive ? .green : .orange)
                }
                if !proActive {
                    Button("Use Italian – Pro") { KeyboardLayout.useItalianPro(); refresh() }
                }
                Text("Italian – Pro has the symbols in the same places as a PC keyboard. In recent versions of macOS it is simply called \"Italian\".")
                    .font(.callout).foregroundStyle(.secondary)
                ForEach(others) { layout in
                    LabeledContent("Also enabled: \(layout.name)") {
                        Button("Remove") { KeyboardLayout.disable(layout.id); refresh() }
                            .disabled(layout.id == current.id)
                    }
                }
                if !others.isEmpty {
                    Text("With more than one layout enabled, the 🌐 key or Ctrl+Space switches keyboards and the symbols move around. If you don't need it, remove it.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }

            Section("Ctrl shortcuts like on Windows") {
                Toggle("Use Ctrl instead of ⌘ for the main shortcuts", isOn: $ctrlShortcuts)
                ForEach(CtrlShortcuts.mappings, id: \.key) { m in
                    Text(m.label).foregroundStyle(ctrlShortcuts ? .primary : .secondary)
                }
                Text("⌘ keeps working too. In terminals (Terminal, iTerm, Warp…) Ctrl stays Ctrl, because there Ctrl+C interrupts the command.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            Section("Screen snipping") {
                Toggle("⌥ + Shift + S captures part of the screen (like Win + Shift + S)", isOn: $screenSnip)
                Text("Drag to choose the area; press Space to capture a whole window, Esc to cancel. The screenshot goes to the clipboard (paste it with Ctrl+V) and is saved in Pictures → Screenshots. Click the notification to open it and draw on it.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Open the Screenshots folder") { ScreenSnip.openFolder() }
            }

            Section("Right ⌘ as AltGr") {
                Toggle("Use right ⌘ as the Windows AltGr key", isOn: $rightCommandAltGr)
                ForEach(AltGr.rows, id: \.0) { keys, result in
                    LabeledContent { Text(result).monospaced() } label: { Text(keys).monospaced() }
                        .foregroundStyle(rightCommandAltGr ? .primary : .secondary)
                }
                Text("On a Mac keyboard, right ⌘ sits where AltGr is on Windows. ⌥ (Option), both left and right, types the same characters too. Left ⌘ stays ⌘ for shortcuts.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            Section("Typing like on Windows") {
                Toggle("Move through, select and delete text like on Windows", isOn: $textKeys)
                ForEach(TextKeys.rows) { r in
                    LabeledContent {
                        Text(r.action)
                    } label: {
                        Text(r.windows).monospaced()
                    }
                    .foregroundStyle(textKeys ? .primary : .secondary)
                }
                Text("On a Mac keyboard, Home and End are fn + ← and fn + →, Delete is fn + ⌫. Outside text fields, Home and End scroll the page, like on Windows. In terminals the keys stay the Mac ones.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: refresh)
        .onReceive(DistributedNotificationCenter.default().publisher(
            for: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String))) { _ in refresh() }
    }

    private func refresh() {
        current = KeyboardLayout.current
        enabled = KeyboardLayout.enabled
    }
}
