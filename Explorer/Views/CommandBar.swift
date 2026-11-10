import Cocoa
import SwiftUI
import QuickLookThumbnailing

struct CommandBar: View {
    @ObservedObject var model: ExplorerModel

    var body: some View {
        let sel = !model.selection.isEmpty
        HStack(spacing: 2) {
            Menu {
                Button("Folder", systemImage: "folder.badge.plus") { model.newFolder() }
                Button("Text Document", systemImage: "doc.text") { model.newTextFile() }
            } label: { Label("New", systemImage: "plus.circle.fill") }
                .menuStyle(.borderlessButton).fixedSize().padding(.horizontal, 6)
            Divider().frame(height: 18)
            cmd("scissors", String(localized: "Cut (⌘X)"), sel) { model.cutSelection() }
            cmd("doc.on.doc", String(localized: "Copy (⌘C)"), sel) { model.copySelection() }
            cmd("doc.on.clipboard", String(localized: "Paste (⌘V)"), true) { model.paste() }
            cmd("character.cursor.ibeam", String(localized: "Rename (F2)"), model.selection.count == 1) {
                model.renaming = model.selectedItems.first
            }
            cmd("square.and.arrow.up", String(localized: "Share"), sel) { share() }
            cmd("trash", String(localized: "Move to Trash (⌦)"), sel) { model.trashSelection() }
            Divider().frame(height: 18)
            Menu {
                Picker("Sort By", selection: sortBinding) {
                    Text("Name").tag("name"); Text("Date Modified").tag("modified")
                    Text("Type").tag("kind"); Text("Size").tag("size"); Text("Date Created").tag("created")
                }
                .pickerStyle(.inline)
                Toggle("Descending", isOn: descendingBinding)
            } label: { Label("Sort", systemImage: "arrow.up.arrow.down") }
                .menuStyle(.borderlessButton).fixedSize().padding(.horizontal, 6)
            Menu {
                Picker("View", selection: Binding(get: { model.viewMode }, set: { model.viewMode = $0 })) {
                    Label("Details", systemImage: "list.bullet").tag(ViewMode.details)
                    Label("Large Icons", systemImage: "square.grid.2x2").tag(ViewMode.icons)
                }
                .pickerStyle(.inline)
                Divider()
                Toggle("Details Pane", isOn: $model.showPreview)
                Toggle("Hidden Items", isOn: $model.showHidden)
                Toggle("Calculate Folder Sizes", isOn: $model.folderSizes)
            } label: { Label("View", systemImage: "eye") }
                .menuStyle(.borderlessButton).fixedSize().padding(.horizontal, 6)
            Spacer()
            if !model.search.isEmpty {
                Toggle("Search subfolders too", isOn: $model.searchEverywhere)
                    .toggleStyle(.checkbox).font(.callout)
            }
        }
        .padding(.horizontal, 8).padding(.bottom, 6)
    }

    private func cmd(_ icon: String, _ help: String, _ enabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).frame(width: 30, height: 26) }
            .buttonStyle(.borderless).disabled(!enabled).help(help)
    }

    private func share() {
        let urls = model.selectedItems.map(\.url)
        guard let window = NSApp.keyWindow, let view = window.contentView else { return }
        let picker = NSSharingServicePicker(items: urls)
        let p = view.convert(NSEvent.mouseLocation, from: nil)
        _ = p
        let loc = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        picker.show(relativeTo: NSRect(x: loc.x, y: loc.y, width: 1, height: 1), of: view, preferredEdge: .minY)
    }

    private var sortKey: String {
        guard let c = model.sortOrder.first else { return "name" }
        switch c.keyPath {
        case \FileItem.modified: return "modified"
        case \FileItem.kind: return "kind"
        case \FileItem.size: return "size"
        case \FileItem.created: return "created"
        default: return "name"
        }
    }

    private var sortBinding: Binding<String> {
        Binding(get: { sortKey }, set: { key in
            let order: SortOrder = model.sortOrder.first?.order ?? .forward
            model.sortOrder = [Sorting.comparator(key, order)]
        })
    }

    private var descendingBinding: Binding<Bool> {
        Binding(get: { model.sortOrder.first?.order == .reverse }, set: { desc in
            model.sortOrder = [Sorting.comparator(sortKey, desc ? .reverse : .forward)]
        })
    }
}
