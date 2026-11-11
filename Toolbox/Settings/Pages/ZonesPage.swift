import SwiftUI

/// Zones like PowerToys FancyZones: your own layouts to drop windows into.
struct ZonesPage: View {
    @AppStorage(Pref.zonesEnabled) private var enabled = true
    @AppStorage(Pref.zonesHoldShift) private var holdShift = true
    @AppStorage(Pref.zonesAllMonitors) private var allMonitors = false
    @AppStorage(Pref.zonesShowNumbers) private var showNumbers = true
    @AppStorage(Pref.zonesOpacity) private var opacity = 0.5
    @AppStorage(Pref.zonesHighlightColor) private var colorHex = ""
    @AppStorage(Pref.zonesOverrideKeys) private var overrideKeys = false
    @AppStorage(Pref.zonesKeysByPosition) private var byPosition = false
    @AppStorage(Pref.zonesQuickSwitch) private var quickSwitch = true
    @AppStorage(Pref.zonesFlash) private var flash = true
    @AppStorage(Pref.zonesAssist) private var assist = true

    private var color: Binding<Color> {
        Binding(get: { Color(hex: colorHex) ?? .accentColor }, set: { colorHex = $0.hex })
    }

    var body: some View {
        Form {
            Section {
                Toggle("Zones", isOn: $enabled)
                Text("Like FancyZones in Windows PowerToys: choose or draw a layout of zones for each monitor, then drag a window while holding ⇧ and drop it on a zone. Near the border between two zones, the window takes both.")
                    .font(.callout).foregroundStyle(.secondary)
                HStack {
                    Button("Open layout editor…") { ZoneEditor.shared.show() }
                    Spacer()
                    ShortcutField(pref: Pref.zonesEditorShortcut, default: .defaultZoneEditor)
                }
            }
            Group {
                Section("Dragging") {
                    Toggle("Hold ⇧ while dragging a window to show the zones", isOn: $holdShift)
                    Text(holdShift ? "Hold ⌃ as well to span the window across several zones."
                                   : "Zones appear whenever you drag a window; hold ⇧ to drag it freely or to snap it to the screen edges. Hold ⌃ to span several zones.")
                        .font(.callout).foregroundStyle(.secondary)
                    Toggle("Show zones on all monitors while dragging", isOn: $allMonitors)
                    Toggle("When I drop a window on a zone, suggest what to put in the other zones", isOn: $assist)
                }
                Section("Appearance") {
                    Toggle("Show zone numbers", isOn: $showNumbers)
                    HStack {
                        Text("Opacity")
                        Slider(value: $opacity, in: 0.1...1)
                        Text("\(Int(opacity * 100))%").monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                    HStack {
                        ColorPicker("Highlight color", selection: color, supportsOpacity: false)
                        if !colorHex.isEmpty { Button("Use accent color") { colorHex = "" } }
                    }
                    Toggle("Flash zones when the layout changes", isOn: $flash)
                }
                Section("Keyboard") {
                    Toggle("⌥ + arrows move windows between zones instead of halves and quarters", isOn: $overrideKeys)
                    Picker("Move windows based on", selection: $byPosition) {
                        Text("Zone number (← →)").tag(false)
                        Text("Position (← → ↑ ↓)").tag(true)
                    }
                    .disabled(!overrideKeys)
                    Toggle("Switch layout with ⌥⌃⌘ + number", isOn: $quickSwitch)
                    Text("Give a custom layout a number in the editor; the shortcut applies it to the monitor of the active window.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                AppListSection(
                    header: "Don't use zones for these apps",
                    footer: "Windows of these apps never snap to zones, even while holding ⇧.",
                    empty: "No exceptions: zones work with every app.",
                    load: { ZoneSettings.excludedApps },
                    save: { ZoneSettings.excludedApps = $0 })
            }
            .disabled(!enabled)
        }
        .formStyle(.grouped)
        .onChange(of: enabled) { _, on in if !on { ZoneOverlay.shared.hide() } }
    }
}
