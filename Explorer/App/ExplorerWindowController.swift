import Cocoa
import SwiftUI
import Combine
import Quartz

@MainActor
final class ExplorerWindowController: NSWindowController, NSWindowDelegate {
    let model: ExplorerModel
    private var sub: AnyCancellable?

    init(url: URL) {
        model = ExplorerModel(url: url)
        let host = NSHostingController(rootView: ExplorerView(model: model))
        let w = NSWindow(contentViewController: host)
        w.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        w.tabbingMode = .preferred
        w.tabbingIdentifier = "it.saind.toolbox.explorer"
        w.titlebarAppearsTransparent = false
        w.toolbarStyle = .unified
        super.init(window: w)
        w.delegate = self
        if !w.setFrameUsingName("ExplorerWindow") {
            let area = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1400, height: 900)
            let size = NSSize(width: min(1180, area.width * 0.8), height: min(760, area.height * 0.8))
            w.setFrame(NSRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2, width: size.width, height: size.height), display: false)
        }
        w.setFrameAutosaveName("ExplorerWindow")
        sub = model.$url.sink { [weak w] u in
            w?.title = FileManager.default.displayName(atPath: u.path)
            w?.representedURL = u
            w?.tab.title = FileManager.default.displayName(atPath: u.path)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Like Windows: when the window opens, keystrokes go to the file list, not the search field.
    func focusList() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let w = self?.window, let root = w.contentView else { return }
            func find(_ v: NSView) -> NSTableView? {
                if let t = v as? NSTableView { return t }
                for s in v.subviews { if let t = find(s) { return t } }
                return nil
            }
            w.makeFirstResponder(find(root) ?? w)
        }
    }

    /// The "+" button in the tab bar.
    override func newWindowForTab(_ sender: Any?) { ExplorerApp.shared.newWindow(at: model.url, tabOf: window) }

    func windowWillClose(_ notification: Notification) {
        if QLPreviewPanel.sharedPreviewPanelExists(), QLPreviewPanel.shared().isVisible { QLPreviewPanel.shared().orderOut(nil) }
        ExplorerApp.shared.closed(self)
    }

    // MARK: Space-bar preview (Quick Look)

    private var previewURLs: [URL] = []

    func toggleQuickLook() {
        let panel = QLPreviewPanel.shared()!
        if panel.isVisible { panel.orderOut(nil); return }
        previewURLs = model.selectedItems.map(\.url)
        guard !previewURLs.isEmpty else { return }
        panel.makeKeyAndOrderFront(nil)
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }
    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = self
        panel.reloadData()
    }
    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) { panel.dataSource = nil }
}

extension ExplorerWindowController: QLPreviewPanelDataSource {
    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated { previewURLs.count }
    }
    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        MainActor.assumeIsolated { previewURLs[index] as NSURL }
    }
}
