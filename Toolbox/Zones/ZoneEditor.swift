import Cocoa
import SwiftUI

/// The layout editor (⌥⇧ + the key above Tab): choose each monitor's layout, change templates
/// (number of zones, spacing, highlight distance) and create your own.
final class ZoneEditor: NSObject, NSWindowDelegate {
    static let shared = ZoneEditor()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let host = NSHostingController(rootView: ZoneEditorView())
            let w = NSWindow(contentViewController: host)
            w.title = String(localized: "Zone Layouts")
            w.styleMask = [.titled, .closable, .resizable]
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.setContentSize(NSSize(width: 780, height: 640))
            window = w
        }
        let screen = ScreenGeo.screen(at: ScreenGeo.mouse) ?? NSScreen.main
        if let w = window, let area = screen?.visibleFrame, !w.isVisible {
            w.setFrameOrigin(NSPoint(x: area.midX - w.frame.width / 2, y: area.midY - w.frame.height / 2))
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    /// While a layout is being drawn on screen, the editor steps aside.
    func stepAside() { window?.orderOut(nil) }
    func comeBack() { window?.makeKeyAndOrderFront(nil); NSApp.activate() }

    /// Closing frees everything; it's rebuilt next time.
    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.window?.contentViewController = nil
            self?.window = nil
        }
    }
}

// MARK: - The editor window

private struct ZoneEditorView: View {
    @ObservedObject private var store = ZoneStore.shared
    @State private var screenKey = ZoneStore.key(for: ScreenGeo.screen(at: ScreenGeo.mouse) ?? NSScreen.screens[0])
    @State private var editing: ZoneLayout?
    @State private var creating = false

    private var screen: NSScreen {
        NSScreen.screens.first { ZoneStore.key(for: $0) == screenKey } ?? NSScreen.screens[0]
    }
    private var areaSize: CGSize { ScreenGeo.area(screen).size }
    private let columns = [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 16)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if NSScreen.screens.count > 1 {
                    Picker("Monitor", selection: $screenKey) {
                        ForEach(NSScreen.screens, id: \.self) { s in Text(s.localizedName).tag(ZoneStore.key(for: s)) }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: screenKey) { _, _ in ZoneOverlay.shared.flash(screen) }
                }
                Text("Click a layout to use it on this monitor. Then drag a window while holding ⇧ and drop it on a zone.")
                    .font(.callout).foregroundStyle(.secondary)

                Text("Templates").font(.headline)
                LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                    ForEach(store.templates) { card($0) }
                }

                Text("Custom").font(.headline).padding(.top, 6)
                LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                    ForEach(store.custom) { card($0) }
                    Button { creating = true } label: {
                        VStack(spacing: 8) {
                            Image(systemName: "plus").font(.system(size: 26, weight: .light))
                            Text("Create new layout")
                        }
                        .frame(maxWidth: .infinity, minHeight: 150)
                        .background(RoundedRectangle(cornerRadius: 10).strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5])).foregroundStyle(.secondary))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(22)
        }
        .frame(minWidth: 560, minHeight: 420)
        .sheet(item: $editing) { layout in
            LayoutSettingsSheet(layout: layout, screen: screen) { editing = nil }
        }
        .sheet(isPresented: $creating) {
            NewLayoutSheet(screen: screen) { creating = false }
        }
    }

    private func card(_ layout: ZoneLayout) -> some View {
        let applied = store.layout(for: screen).id == layout.id
        return VStack(alignment: .leading, spacing: 8) {
            LayoutThumbnail(layout: layout, areaSize: areaSize)
                .aspectRatio(areaSize.width / max(1, areaSize.height), contentMode: .fit)
            HStack(spacing: 4) {
                Text(layout.displayName).lineLimit(1)
                if let k = layout.hotkey { Text("⌥⌃⌘\(k)").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                if layout.kind != .blank {
                    Button { editing = layout } label: { Image(systemName: "pencil") }
                        .buttonStyle(.borderless)
                        .help(String(localized: "Edit"))
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(applied ? Color.accentColor : .clear, lineWidth: 2))
        .contentShape(Rectangle())
        .onTapGesture {
            store.apply(layout.id, to: screen)
            ZoneOverlay.shared.flash(screen)
        }
    }
}

/// A layout drawn small, with its real proportions and spacing.
struct LayoutThumbnail: View {
    let layout: ZoneLayout
    let areaSize: CGSize

    var body: some View {
        GeometryReader { g in
            let scale = g.size.width / max(1, areaSize.width)
            let frames = layout.frames(in: CGRect(origin: .zero, size: areaSize))
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.08))
                if frames.isEmpty {
                    Text("No zones").font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                ForEach(frames.indices, id: \.self) { i in
                    let f = frames[i]
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.accentColor.opacity(0.35))
                        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color.accentColor.opacity(0.8), lineWidth: 1))
                        .frame(width: max(2, f.width * scale), height: max(2, f.height * scale))
                        .offset(x: f.minX * scale, y: f.minY * scale)
                }
            }
        }
    }
}

// MARK: - Layout settings

private struct LayoutSettingsSheet: View {
    @State var layout: ZoneLayout
    let screen: NSScreen
    let close: () -> Void
    @State private var confirmDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(layout.kind.isTemplate ? layout.displayName : String(localized: "Edit layout")).font(.title3.bold())
            Form {
                if !layout.kind.isTemplate {
                    TextField("Name", text: $layout.name)
                }
                if layout.kind.isTemplate {
                    Stepper(value: $layout.zoneCount, in: 1...(layout.kind == .focus ? 10 : ZoneLayout.maxZones)) {
                        Text("Number of zones: \(layout.zoneCount)")
                    }
                }
                Toggle("Show space around zones", isOn: $layout.showSpacing)
                Stepper(value: $layout.spacing, in: 0...100, step: 2) { Text("Space around zones: \(layout.spacing) pt") }
                    .disabled(!layout.showSpacing)
                Stepper(value: $layout.sensitivity, in: 0...100, step: 5) { Text("Highlight distance: \(layout.sensitivity) pt") }
                Text("Near the border between two zones (within this distance), the window spans both.")
                    .font(.caption).foregroundStyle(.secondary)
                if !layout.kind.isTemplate {
                    Picker("Layout shortcut", selection: $layout.hotkey) {
                        Text("None").tag(Int?.none)
                        ForEach(0..<10) { n in Text("⌥⌃⌘ \(n)").tag(Int?.some(n)) }
                    }
                }
            }
            .formStyle(.grouped)
            LayoutThumbnail(layout: layout, areaSize: ScreenGeo.area(screen).size)
                .aspectRatio(ScreenGeo.area(screen).width / max(1, ScreenGeo.area(screen).height), contentMode: .fit)
                .frame(height: 130)
                .frame(maxWidth: .infinity)
            HStack {
                if !layout.kind.isTemplate {
                    Button("Edit zones…") {
                        ZoneStore.shared.put(layout)
                        close()
                        ZoneEditingSession.start(layout, on: screen)
                    }
                    Button("Delete", role: .destructive) { confirmDelete = true }
                }
                Spacer()
                Button("Cancel", action: close).keyboardShortcut(.cancelAction)
                Button("Save") {
                    ZoneStore.shared.put(layout)
                    if ZoneStore.shared.layout(for: screen).id == layout.id { ZoneOverlay.shared.flash(screen) }
                    close()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
        .confirmationDialog("Delete “\(layout.name)”?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { ZoneStore.shared.delete(layout.id); close() }
        }
    }
}

private struct NewLayoutSheet: View {
    let screen: NSScreen
    let close: () -> Void
    @State private var name = ZoneStore.shared.newName()
    @State private var kind = ZoneLayout.Kind.customGrid

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Create new layout").font(.title3.bold())
            Form {
                TextField("Name", text: $name)
                Picker("Type", selection: $kind) {
                    Text("Grid").tag(ZoneLayout.Kind.customGrid)
                    Text("Canvas").tag(ZoneLayout.Kind.canvas)
                }
                .pickerStyle(.radioGroup)
                Text(kind == .customGrid
                     ? "Zones that fill the screen: click to split a zone, drag the borders, drag across zones to merge them."
                     : "Free zones you place where you want, even overlapping.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel", action: close).keyboardShortcut(.cancelAction)
                Button("Create") {
                    let zones: [CGRect] = kind == .customGrid
                        ? [CGRect(x: 0, y: 0, width: 1.0 / 3, height: 1), CGRect(x: 1.0 / 3, y: 0, width: 1.0 / 3, height: 1),
                           CGRect(x: 2.0 / 3, y: 0, width: 1.0 / 3, height: 1)]
                        : [CGRect(x: 0.2, y: 0.15, width: 0.45, height: 0.6)]
                    let layout = ZoneLayout(id: UUID(), name: name.isEmpty ? ZoneStore.shared.newName() : name,
                                            kind: kind, customZones: zones)
                    close()
                    ZoneEditingSession.start(layout, on: screen)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}
