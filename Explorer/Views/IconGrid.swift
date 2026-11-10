import Cocoa
import SwiftUI
import QuickLookThumbnailing

struct IconGrid: View {
    @ObservedObject var model: ExplorerModel
    @State private var anchor: URL?

    var body: some View {
        let rows = model.displayed
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 116, maximum: 140), spacing: 6)], spacing: 6) {
                ForEach(rows) { item in
                    IconCell(item: item, selected: model.selection.contains(item.url), cut: model.cutItems.contains(item.url))
                        .onTapGesture(count: 2) { model.open([item.url]) }
                        .simultaneousGesture(TapGesture().onEnded { click(item, in: rows) })
                        .contextMenu { ItemMenu(model: model, urls: model.selection.contains(item.url) ? model.selection : [item.url]) }
                        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
                        .dropDestination(for: URL.self) { urls, _ in
                            guard item.isFolder else { return false }
                            model.transfer(urls, to: item.url, move: !NSEvent.modifierFlags.contains(.option)); return true
                        }
                }
            }
            .padding(10)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .contentShape(Rectangle())
        .onTapGesture { model.selection = [] }
        .contextMenu { BackgroundMenu(model: model) }
        .dropDestination(for: URL.self) { urls, _ in
            model.transfer(urls, to: model.url, move: !NSEvent.modifierFlags.contains(.option)); return true
        }
    }

    /// Click, ⌘-click (add/remove), ⇧-click (range): like Ctrl and Shift on Windows.
    private func click(_ item: FileItem, in rows: [FileItem]) {
        let mods = NSEvent.modifierFlags
        if mods.contains(.command) || mods.contains(.control) {
            if model.selection.contains(item.url) { model.selection.remove(item.url) } else { model.selection.insert(item.url) }
            anchor = item.url
        } else if mods.contains(.shift), let a = anchor, let i = rows.firstIndex(where: { $0.url == a }),
                  let j = rows.firstIndex(where: { $0.url == item.url }) {
            model.selection = Set(rows[min(i, j)...max(i, j)].map(\.url))
        } else {
            model.selection = [item.url]
            anchor = item.url
        }
    }
}

private struct IconCell: View {
    let item: FileItem
    let selected: Bool
    let cut: Bool

    var body: some View {
        VStack(spacing: 4) {
            Thumbnail(url: item.url, size: 84)
                .frame(width: 88, height: 88)
            Text(item.name)
                .font(.system(size: 11))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .truncationMode(.middle)
                .frame(maxWidth: 112)
        }
        .padding(6)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Color.accentColor.opacity(0.25) : .clear))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(selected ? Color.accentColor.opacity(0.6) : .clear))
        .opacity(cut || item.isHidden ? 0.5 : 1)
        .contentShape(Rectangle())
    }
}

/// Content thumbnail (images, PDFs, videos…), showing the icon until it is ready.
struct Thumbnail: View {
    let url: URL
    let size: CGFloat
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().aspectRatio(contentMode: .fit) }
            else { Image(nsImage: Icons.icon(url)).resizable().aspectRatio(contentMode: .fit) }
        }
        .task(id: url) { image = await ThumbnailCache.image(for: url, size: size) }
    }
}

enum ThumbnailCache {
    private static let cache = NSCache<NSString, NSImage>()

    static func image(for url: URL, size: CGFloat) async -> NSImage? {
        let key = "\(url.path)#\(Int(size))" as NSString
        if let i = cache.object(forKey: key) { return i }
        let scale = await MainActor.run { NSScreen.main?.backingScaleFactor ?? 2 }
        let req = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: size, height: size), scale: scale,
                                               representationTypes: .thumbnail)
        guard let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: req) else { return nil }
        let img = rep.nsImage
        cache.setObject(img, forKey: key)
        return img
    }
}
