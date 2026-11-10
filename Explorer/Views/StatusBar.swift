import Cocoa
import SwiftUI
import QuickLookThumbnailing

struct StatusBar: View {
    @ObservedObject var model: ExplorerModel

    var body: some View {
        let all = model.displayed
        let sel = model.selectedItems
        HStack(spacing: 14) {
            Text("\(all.count) items")
            if !sel.isEmpty {
                let size = sel.map { max(0, $0.size) }.reduce(0, +)
                Text(String(localized: "\(sel.count) selected") + (size > 0 ? " · \(Fmt.size(size))" : ""))
            }
            Spacer()
            if let free = try? model.url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage {
                Text("\(Fmt.size(free)) free")
            }
            Picker("", selection: Binding(get: { model.viewMode }, set: { model.viewMode = $0 })) {
                Image(systemName: "list.bullet").tag(ViewMode.details)
                Image(systemName: "square.grid.2x2").tag(ViewMode.icons)
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 70).controlSize(.small)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12).padding(.vertical, 5)
    }
}
