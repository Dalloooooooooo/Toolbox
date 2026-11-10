import Cocoa
import SwiftUI
import QuickLookThumbnailing

struct DetailsPane: View {
    @ObservedObject var model: ExplorerModel

    var body: some View {
        let sel = model.selectedItems
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if sel.count == 1, let item = sel.first {
                    Thumbnail(url: item.url, size: 240)
                        .frame(maxWidth: .infinity).frame(height: 200)
                    Text(item.name).font(.headline).textSelection(.enabled).lineLimit(4)
                    ItemInfo(item: item)
                } else if sel.count > 1 {
                    Image(systemName: "doc.on.doc").font(.system(size: 54, weight: .light)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity).frame(height: 120)
                    Text("\(sel.count) items selected").font(.headline)
                    let total = sel.map { max(0, $0.size) }.reduce(0, +)
                    InfoRow(String(localized: "Total Size"), Fmt.size(total) + (sel.contains { $0.size < 0 } ? " (\(String(localized: "calculating…")))" : ""))
                } else {
                    Thumbnail(url: model.url, size: 128).frame(maxWidth: .infinity).frame(height: 110)
                    Text(FileManager.default.displayName(atPath: model.url.path)).font(.headline)
                    InfoRow(String(localized: "Items"), "\(model.displayed.count)")
                    InfoRow(String(localized: "Path"), model.url.path)
                    Text("Select a file to see its preview and details. Press Space for a full-screen preview.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            .padding(14)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct ItemInfo: View {
    let item: FileItem
    @State private var pixels: String?
    @State private var duration: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            InfoRow(String(localized: "Type"), item.kind + (item.ext.isEmpty ? "" : " (.\(item.ext))"))
            if item.size >= 0 {
                InfoRow(String(localized: "Size"), "\(Fmt.size(item.size)) — \(Fmt.exactBytes(item.size))")
            } else {
                InfoRow(String(localized: "Size"), String(localized: "calculating…"))
            }
            if item.isFolder, item.count >= 0 { InfoRow(String(localized: "Contains"), String(localized: "\(item.count) items")) }
            if let pixels { InfoRow(String(localized: "Resolution"), pixels) }
            InfoRow(String(localized: "Date Modified"), Fmt.date(item.modified))
            InfoRow(String(localized: "Date Created"), Fmt.date(item.created))
            InfoRow(String(localized: "Path"), item.parent)
            HStack {
                Button("Open") { NSWorkspace.shared.open(item.url) }
                Button("Copy Path") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(item.url.path, forType: .string)
                }
            }
            .controlSize(.small)
        }
        .task(id: item.url) { pixels = Self.imageSize(item.url) }
    }

    private static func imageSize(_ url: URL) -> String? {
        guard FileOps.isImage(url), let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = p[kCGImagePropertyPixelWidth] as? Int, let h = p[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return String(localized: "\(w) × \(h) pixels")
    }
}

private struct InfoRow: View {
    let label: String, value: String
    init(_ label: String, _ value: String) { self.label = label; self.value = value }
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.callout).textSelection(.enabled)
        }
    }
}
