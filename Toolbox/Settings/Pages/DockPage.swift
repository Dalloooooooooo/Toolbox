import SwiftUI

struct DockPage: View {
    @AppStorage(Pref.dockPreviews) private var dockPreviews = true
    @AppStorage(Pref.dockPreviewWidth) private var dockPreviewWidth = 240.0
    @AppStorage(Pref.toolboxInDock) private var toolboxInDock = true
    @AppStorage(Pref.dockMinimize) private var dockMinimize = true
    @AppStorage(Pref.dockMinimizeScope) private var dockMinimizeScope = DockMinimizeScope.allWindows.rawValue

    var body: some View {
        Form {
            Section("Window previews") {
                Toggle("Show window previews when hovering Dock icons", isOn: $dockPreviews)
                LabeledContent("Preview size") {
                    Slider(value: $dockPreviewWidth, in: 160...400, step: 20).frame(maxWidth: 260)
                }
                .disabled(!dockPreviews)
                Text("Like the Windows taskbar: click a preview to open that window, the X closes it. Minimized windows and windows on other desktops are included too.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("Toolbox in the Dock") {
                Toggle("Keep the Toolbox icon in the Dock", isOn: $toolboxInDock)
                Text("Clicking the icon opens these settings. Toolbox also stays available in the menu bar at the top.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("Clicking a Dock icon") {
                Toggle("Minimize the app in front when you click its icon", isOn: $dockMinimize)
                Picker("What to minimize", selection: $dockMinimizeScope) {
                    ForEach(DockMinimizeScope.allCases) { Text($0.label).tag($0.rawValue) }
                }
                .disabled(!dockMinimize)
                Text("Like the Windows taskbar: if the app is already in front, clicking its Dock icon minimizes it. Another click brings it back. Full-screen windows leave full screen first.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
