import Cocoa
import SwiftUI
import QuickLookThumbnailing

struct ItemMenu: View {
    @ObservedObject var model: ExplorerModel
    let urls: Set<URL>

    var body: some View {
        let list = Array(urls)
        let single = list.count == 1 ? list[0] : nil
        let item = single.flatMap { u in model.displayed.first { $0.url == u } }
        if list.isEmpty {
            BackgroundMenu(model: model)
        } else {
            Button("Open") { model.open(list) }
            if let single, item?.isFolder != true {
                Menu("Open With") {
                    ForEach(NSWorkspace.shared.urlsForApplications(toOpen: single), id: \.self) { app in
                        Button {
                            NSWorkspace.shared.open([single], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
                        } label: {
                            Label { Text(FileManager.default.displayName(atPath: app.path).replacingOccurrences(of: ".app", with: "")) }
                                  icon: { Image(nsImage: Icons.icon(app)) }
                        }
                    }
                }
            }
            if let single, item?.isFolder == true {
                Button("Open in New Window") { ExplorerApp.shared.newWindow(at: single) }
                Button("Open in Terminal") { FileOps.openInTerminal(single) }
            }
            Divider()
            Button("Cut") { model.selection = urls; model.cutSelection() }
            Button("Copy") { model.selection = urls; model.copySelection() }
            if let single, item?.isFolder == true, !FileClipboard.files.isEmpty {
                Button("Paste Into Folder") { model.paste(into: single) }
            }
            Button("Duplicate") { model.selection = urls; model.duplicateSelection() }
            Divider()
            if let item { Button("Rename") { model.renaming = item } }
            Button("Compress to ZIP File") { model.selection = urls; model.compressSelection() }
            if let single, single.pathExtension.lowercased() == "zip" {
                Button("Extract Here") { model.extract(single) }
            }
            if let single, FileOps.isImage(single) {
                Button("Set as Wallpaper") { FileOps.setWallpaper(single) }
            }
            Button("Copy Path") { model.selection = urls; model.copyPaths() }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(list) }
            Button("Share…") {
                if let v = NSApp.keyWindow?.contentView {
                    let loc = NSApp.keyWindow!.convertPoint(fromScreen: NSEvent.mouseLocation)
                    NSSharingServicePicker(items: list).show(relativeTo: NSRect(origin: loc, size: .init(width: 1, height: 1)), of: v, preferredEdge: .minY)
                }
            }
            Divider()
            Button("Move to Trash") { model.selection = urls; model.trashSelection() }
            Divider()
            Button("Properties") { model.selection = urls; model.showPreview = true }
        }
    }
}

struct BackgroundMenu: View {
    @ObservedObject var model: ExplorerModel
    var body: some View {
        Menu("New") {
            Button("Folder") { model.newFolder() }
            Button("Text Document") { model.newTextFile() }
        }
        Button("Paste") { model.paste() }.disabled(FileClipboard.files.isEmpty)
        Divider()
        Button("Refresh") { model.refresh() }
        Toggle("Show Hidden Items", isOn: $model.showHidden)
        Divider()
        Button("Open in Terminal") { FileOps.openInTerminal(model.url) }
        Button("Copy Path") { model.selection = []; model.copyPaths() }
        Button("Show in Finder") { NSWorkspace.shared.open(model.url) }
    }
}
