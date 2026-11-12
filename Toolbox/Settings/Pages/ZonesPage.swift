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
    @AppStorage(Pref.zonesSmart) private var smart = false
    @AppStorage(Pref.zonesAssistMode) private var assist = AssistMode.read(Pref.zonesAssistMode, old: Pref.zonesAssist).rawValue

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
                    Picker("After dropping a window on a zone, suggest windows", selection: $assist) {
                        ForEach(AssistMode.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                }
                SmartLayoutsSection(smart: $smart)
                if smart {
                    AppListSection(
                        header: "Don't count these apps",
                        footer: "Their windows can still go into zones, they just don't count when choosing the layout. Useful for small windows, like the Calculator or System Settings.",
                        empty: "Every app counts.",
                        load: { SmartZones.ignoredApps },
                        save: { SmartZones.ignoredApps = $0 })
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

/// Smart layouts: one layout for each number of open windows.
private struct SmartLayoutsSection: View {
    @Binding var smart: Bool
    @ObservedObject private var store = ZoneStore.shared
    @State private var chosen = SmartZones.layouts

    var body: some View {
        Section("Smart layouts") {
            Toggle("Choose the layout based on the open windows", isOn: $smart)
            if smart {
                ForEach(SmartZones.counts, id: \.self) { n in
                    Picker(label(n), selection: binding(n)) {
                        Text("The monitor's layout").tag(UUID?.none)
                        Divider()
                        ForEach(store.layouts) { Text($0.displayName).tag(UUID?.some($0.id)) }
                    }
                }
            }
            Text("When you start dragging, Toolbox counts the windows open on that monitor (the one you drag included; not minimized ones) and uses the layout chosen for that number. Columns, rows, grids and the other templates get one zone per window.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private func label(_ n: Int) -> String {
        switch n {
        case 1: String(localized: "1 window")
        case SmartZones.counts.last!: String(localized: "\(n) or more windows")
        default: String(localized: "\(n) windows")
        }
    }

    private func binding(_ n: Int) -> Binding<UUID?> {
        Binding(get: { chosen[n] }, set: { id in
            chosen[n] = id
            SmartZones.layouts = chosen
        })
    }
}

