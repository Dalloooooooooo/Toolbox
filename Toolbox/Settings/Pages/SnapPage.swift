import Cocoa
import SwiftUI

struct SnapPage: View {
    @AppStorage(Pref.snapEnabled) private var enabled = true
    @AppStorage(Pref.snapLayoutBar) private var layoutBar = true
    @AppStorage(Pref.snapAssistMode) private var assist = AssistMode.read(Pref.snapAssistMode, old: Pref.snapAssist).rawValue
    @AppStorage(Pref.snapLinkedResize) private var linked = true
    @AppStorage(Pref.snapNearEdge) private var nearEdge = true
    @AppStorage(Pref.snapKeys) private var keys = true
    @AppStorage(Pref.greenButtonMaximizes) private var greenButton = true
    @AppStorage(Pref.snapAnimate) private var animate = true
    @State private var macOSTiling = MacOSTiling.isActive
    private let refresh = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            if enabled && macOSTiling {
                Section {
                    Label("macOS window tiling has been turned back on and overlaps with this.",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Button("Turn off macOS tiling") { MacOSTiling.sync(); macOSTiling = MacOSTiling.isActive }
                }
            }
            Section {
                Toggle("Window snapping", isOn: $enabled)
                Text("Like on Windows: drag a window to the left or right edge to fill half the screen, to a corner for a quarter, to the top edge to fill the screen. Drag it away and it returns to its previous size.")
                    .font(.callout).foregroundStyle(.secondary)
                if MacOSTiling.isSupported {
                    Text("While this is on, macOS window tiling stays off so the two don't overlap. Turning this off restores macOS tiling as it was.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            Section("Like on Windows 11") {
                Toggle("Show layouts when I drag a window to the top of the screen", isOn: $layoutBar)
                Picker("After snapping a window, suggest what to snap next to it", selection: $assist) {
                    ForEach(AssistMode.allCases) { Text($0.label).tag($0.rawValue) }
                }
                Toggle("When I resize a snapped window, also resize adjacent snapped windows", isOn: $linked)
                Toggle("Snap without dragging all the way to the screen edge", isOn: $nearEdge)
                Toggle("Animate windows when they snap, maximize or restore", isOn: $animate)
            }
            .disabled(!enabled)
            Section("Green button") {
                Toggle("The green button maximizes the window instead of opening it in full screen", isOn: $greenButton)
                Text("Like Windows' maximize button: the window fills the screen and stays on the same desktop, with the Dock and the menu bar visible. Click again to restore it. Full screen is still available with ⌃⌘F or from the menu that appears when you hover over the green button.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("Keyboard (left ⌥ acts as the Windows key)") {
                Toggle("Win + arrow keys and Win + Z shortcuts", isOn: $keys)
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    GridRow { Text("⌥ ← / ⌥ →").monospaced(); Text("left / right half; again for the next monitor or to restore") }
                    GridRow { Text("⌥ ↑").monospaced(); Text("maximize; from a half, the top quarter") }
                    GridRow { Text("⌥ ↓").monospaced(); Text("restore; from a half, the bottom quarter; then minimize") }
                    GridRow { Text("⌥ ⇧ ← / →").monospaced(); Text("move to the next monitor") }
                    GridRow { Text("⌥ ⇧ ↑ / ↓").monospaced(); Text("stretch vertically / restore") }
                    GridRow { Text("⌥ Z").monospaced(); Text("layouts for the active window (numbers, arrows, Return)") }
                }
                .font(.callout)
                .disabled(!keys)
                Text("Dragging a window's top or bottom edge to the edge of the screen also stretches the window vertically. Right ⌥ stays AltGr.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .disabled(!enabled)
            Section("Snap Assist") {
                Text("The other open windows appear in the remaining space: click the one to snap (hovering over it shows the X to close it), or click elsewhere, press Esc or switch to another app to leave the space empty. Arrow keys, Tab and Return work too.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onReceive(refresh) { _ in macOSTiling = MacOSTiling.isActive }
    }
}
