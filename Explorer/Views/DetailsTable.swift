import Cocoa
import SwiftUI
import QuickLookThumbnailing

enum Sorting {
    static func comparator(_ key: String, _ order: SortOrder) -> KeyPathComparator<FileItem> {
        switch key {
        case "modified": KeyPathComparator(\FileItem.modified, order: order)
        case "kind": KeyPathComparator(\FileItem.kind, comparator: .localizedStandard, order: order)
        case "size": KeyPathComparator(\FileItem.size, order: order)
        case "created": KeyPathComparator(\FileItem.created, order: order)
        default: KeyPathComparator(\FileItem.name, comparator: .localizedStandard, order: order)
        }
    }
}

// MARK: - Details view (table)

struct DetailsTable: View {
    @ObservedObject var model: ExplorerModel
    @SceneStorage("columns") private var columnsData: Data?
    @State private var columns = TableColumnCustomization<FileItem>()

    var body: some View {
        let rows = model.displayed
        Table(of: FileItem.self, selection: $model.selection, sortOrder: $model.sortOrder, columnCustomization: $columns) {
            TableColumn("Name", value: \.name, comparator: .localizedStandard) { item in
                HStack(spacing: 6) {
                    Image(nsImage: Icons.icon(item.url)).resizable().frame(width: 18, height: 18)
                    Text(item.name).lineLimit(1).truncationMode(.middle)
                }
                .opacity(model.cutItems.contains(item.url) || item.isHidden ? 0.5 : 1)
            }
            .width(min: 160, ideal: 260)
            .customizationID("name")
            .disabledCustomizationBehavior(.visibility)

            TableColumn("Date Modified", value: \.modified) { Text(Fmt.date($0.modified)).foregroundStyle(.secondary) }
                .width(min: 100, ideal: 130).customizationID("modified")

            TableColumn("Type", value: \.kind, comparator: .localizedStandard) { Text($0.kind).foregroundStyle(.secondary).lineLimit(1) }
                .width(min: 70, ideal: 110).customizationID("kind")

            TableColumn("Size", value: \.size) { item in
                Group {
                    if item.size >= 0 { Text(Fmt.size(item.size)) }
                    else if model.folderSizes { Text("…").foregroundStyle(.tertiary) }
                }
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 64, ideal: 80).customizationID("size")

            TableColumn("Items", value: \.count) { item in
                Text(item.isFolder && item.count >= 0 ? "\(item.count)" : "").monospacedDigit().foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 50, ideal: 64).customizationID("count")

            TableColumn("Extension", value: \.ext) { Text($0.ext.uppercased()).foregroundStyle(.secondary) }
                .width(min: 50, ideal: 70).customizationID("ext").defaultVisibility(.hidden)

            TableColumn("Date Created", value: \.created) { Text(Fmt.date($0.created)).foregroundStyle(.secondary) }
                .width(min: 110, ideal: 140).customizationID("created").defaultVisibility(.hidden)

            TableColumn("Path", value: \.parent) { Text($0.parent).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head) }
                .width(min: 120, ideal: 260).customizationID("parent").defaultVisibility(.hidden)
        } rows: {
            ForEach(rows) { item in
                TableRow(item)
                    .itemProvider { NSItemProvider(contentsOf: item.url) }
                    .dropDestination(for: URL.self) { urls in
                        guard item.isFolder else { return }
                        model.transfer(urls, to: item.url, move: !NSEvent.modifierFlags.contains(.option))
                    }
            }
        }
        .contextMenu(forSelectionType: URL.self) { sel in
            ItemMenu(model: model, urls: sel)
        } primaryAction: { sel in
            model.open(Array(sel))
        }
        .dropDestination(for: URL.self) { urls, _ in
            model.transfer(urls, to: model.url, move: !NSEvent.modifierFlags.contains(.option)); return true
        }
        .onAppear {
            if let d = columnsData, let c = try? JSONDecoder().decode(TableColumnCustomization<FileItem>.self, from: d) { columns = c }
            syncPathColumn()
        }
        .onChange(of: columns) { _, c in columnsData = try? JSONEncoder().encode(c) }
        .onChange(of: model.searchEverywhere) { _, _ in syncPathColumn() }
    }

    /// When searching all subfolders you need to know where each result is.
    private func syncPathColumn() { columns[visibility: "parent"] = model.searchEverywhere ? .visible : .hidden }
}
