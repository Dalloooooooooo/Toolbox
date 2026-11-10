import Cocoa
import SwiftUI

@MainActor
final class ExplorerModel: ObservableObject {
    @Published private(set) var url: URL
    @Published private(set) var items: [FileItem] = []
    @Published var selection: Set<URL> = []
    @Published var sortOrder: [KeyPathComparator<FileItem>] = [KeyPathComparator(\FileItem.name, comparator: .localizedStandard)]
    @Published var search = "" { didSet { if searchEverywhere { runDeepSearch() } } }
    @Published var searchEverywhere = false { didSet { runDeepSearch() } }
    @Published private(set) var deepResults: [FileItem]?
    @Published private(set) var searching = false
    @Published var editingAddress = false
    @Published var renaming: FileItem?
    @Published var errorMessage: String?
    @Published var loadError: String?
    @Published private(set) var cutItems: Set<URL> = []
    @Published var focusSearch = false

    // settings shared by all windows
    @AppStorage("viewMode") var viewModeRaw = ViewMode.details.rawValue
    @AppStorage("showHidden") var showHidden = false
    @AppStorage("showPreview") var showPreview = true
    @AppStorage("folderSizes") var folderSizes = true
    var viewMode: ViewMode {
        get { ViewMode(rawValue: viewModeRaw) ?? .details }
        set { viewModeRaw = newValue.rawValue; objectWillChange.send() }
    }

    private(set) var back: [URL] = []
    private(set) var forward: [URL] = []
    private var watcher: DispatchSourceFileSystemObject?
    private var reloadPending = false
    private var generation = 0
    private var query: NSMetadataQuery?

    init(url: URL) {
        self.url = url
        load()
        NotificationCenter.default.addObserver(forName: .clipboardChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.cutItems = FileClipboard.isCut ? FileClipboard.cut : [] }
        }
        NotificationCenter.default.addObserver(forName: .explorerPrefsChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.objectWillChange.send() }
        }
    }

    /// Items to show: filtered, sorted, folders first (like Windows).
    var displayed: [FileItem] {
        var list = deepResults ?? items
        if !showHidden { list = list.filter { !$0.isHidden } }
        if deepResults == nil, !search.isEmpty {
            list = list.filter { $0.name.range(of: search, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
        let folders = list.filter(\.isFolder).sorted(using: sortOrder)
        let files = list.filter { !$0.isFolder }.sorted(using: sortOrder)
        return folders + files
    }

    var selectedItems: [FileItem] { displayed.filter { selection.contains($0.url) } }

    // MARK: navigation

    func go(to target: URL, recordHistory: Bool = true) {
        let target = target.standardizedFileURL
        guard target != url else { load(); return }
        if recordHistory { back.append(url); forward.removeAll() }
        url = target
        selection = []
        search = ""
        searchEverywhere = false
        load()
    }

    func goBack() { guard let prev = back.popLast() else { return }; forward.append(url); go(to: prev, recordHistory: false) }
    func goForward() { guard let next = forward.popLast() else { return }; back.append(url); go(to: next, recordHistory: false) }
    func goUp() {
        let parent = url.deletingLastPathComponent()
        guard parent.path != url.path else { return }
        let from = url
        go(to: parent)
        selection = [from] // like Windows: the folder you came from stays selected
    }
    var canGoBack: Bool { !back.isEmpty }
    var canGoForward: Bool { !forward.isEmpty }
    var canGoUp: Bool { url.path != "/" }

    /// Double-click / Return.
    func open(_ urls: [URL]) {
        let list = urls.compactMap { u in (deepResults ?? items).first { $0.url == u } ?? FileItem(url: u) }
        if list.count == 1, let f = list.first, f.isFolder { go(to: f.url); return }
        for f in list where !f.isFolder { NSWorkspace.shared.open(f.url) }
        if let folder = list.first(where: \.isFolder), list.allSatisfy(\.isFolder) { go(to: folder.url) }
    }

    func openSelection() { open(Array(selection)) }

    // MARK: loading

    func load() {
        generation += 1
        let gen = generation
        let dir = url
        loadError = nil
        watch(dir)
        Task.detached(priority: .userInitiated) {
            var problem: String?
            var list: [FileItem] = []
            do {
                let urls = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: FileItem.keys, options: [])
                list = urls.compactMap(FileItem.init(url:))
            } catch {
                problem = (error as NSError).code == NSFileReadNoPermissionError
                    ? String(localized: "You don't have permission to open this folder.")
                    : error.localizedDescription
            }
            let error = problem
            let found = list
            await MainActor.run {
                guard gen == self.generation else { return }
                // keep folder sizes already computed (they are refreshed afterwards)
                let old = Dictionary(self.items.map { ($0.url, $0) }, uniquingKeysWith: { a, _ in a })
                self.items = found.map { item in
                    var i = item
                    if i.isFolder, let o = old[i.url].map({ ($0.size, $0.count) }) ?? FolderSizes.cached(i.url).map({ ($0.size, $0.count) }), o.0 >= 0 {
                        i.size = o.0; i.count = o.1
                    }
                    return i
                }
                self.loadError = error
                self.selection = self.selection.filter { u in found.contains { $0.url == u } }
                self.computeFolderSizes(gen)
            }
        }
    }

    func refresh() { FolderSizes.forget(under: url); load() }

    /// Notices on its own when something changes in the folder (files added, renamed, deleted).
    private func watch(_ dir: URL) {
        watcher?.cancel()
        let fd = Darwin.open(dir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete, .extend], queue: .main)
        src.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.reloadPending else { return }
                self.reloadPending = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    self.reloadPending = false
                    FolderSizes.forget(under: dir)
                    self.load()
                }
            }
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        watcher = src
    }

    /// Size and item count of each folder, one at a time in the background.
    private func computeFolderSizes(_ gen: Int) {
        guard folderSizes else { return }
        let folders = items.filter { $0.isFolder && $0.size < 0 }.map(\.url)
        guard !folders.isEmpty else { return }
        Task.detached(priority: .utility) {
            for folder in folders {
                let stillCurrent = await MainActor.run { gen == self.generation }
                guard stillCurrent else { return }
                let result = FolderSizes.compute(folder)
                await MainActor.run {
                    guard gen == self.generation, let i = self.items.firstIndex(where: { $0.url == folder }) else { return }
                    self.items[i].size = result.size
                    self.items[i].count = result.count
                }
            }
        }
    }

    // MARK: search in all subfolders (Spotlight)

    private func runDeepSearch() {
        query?.stop()
        query = nil
        guard searchEverywhere, search.count >= 2 else { deepResults = nil; searching = false; return }
        let q = NSMetadataQuery()
        q.predicate = NSPredicate(format: "%K LIKE[cd] %@", NSMetadataItemFSNameKey, "*\(search)*")
        q.searchScopes = [url]
        NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: q, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.query === q else { return }
                q.disableUpdates()
                let urls = (0..<min(q.resultCount, 2000)).compactMap {
                    (q.result(at: $0) as? NSMetadataItem)?.value(forAttribute: NSMetadataItemURLKey) as? URL
                }
                self.searching = false
                Task.detached {
                    let found = urls.compactMap(FileItem.init(url:))
                    await MainActor.run { if self.query === q { self.deepResults = found } }
                }
            }
        }
        query = q
        searching = true
        q.start()
    }

    // MARK: file operations

    func copySelection() { guard !selection.isEmpty else { return }; FileClipboard.put(Array(selection), cut: false) }
    func cutSelection() { guard !selection.isEmpty else { return }; FileClipboard.put(Array(selection), cut: true) }

    func paste(into folder: URL? = nil) {
        let sources = FileClipboard.files
        guard !sources.isEmpty else { return }
        let move = FileClipboard.isCut
        transfer(sources, to: folder ?? url, move: move)
        if move { FileClipboard.clearCut() }
    }

    /// Copies or moves (also used for drag and drop). If a file with the same name already exists, it appends
    /// " - Copy", like Windows.
    func transfer(_ sources: [URL], to dest: URL, move: Bool) {
        Task.detached {
            var failures: [String] = []
            for src in sources {
                if move, src.deletingLastPathComponent().standardizedFileURL == dest.standardizedFileURL { continue }
                if dest.path.hasPrefix(src.path + "/") || dest.path == src.path {
                    failures.append(String(localized: "\(src.lastPathComponent): can't put a folder inside itself")); continue
                }
                let target = FileOps.uniqueURL(for: src.lastPathComponent, in: dest, copySuffix: !move)
                do {
                    if move { try FileManager.default.moveItem(at: src, to: target) }
                    else { try FileManager.default.copyItem(at: src, to: target) }
                } catch { failures.append("\(src.lastPathComponent): \(error.localizedDescription)") }
            }
            let problems = failures
            await MainActor.run {
                if !problems.isEmpty { self.errorMessage = problems.joined(separator: "\n") }
                self.load()
            }
        }
    }

    func trashSelection() {
        let urls = Array(selection)
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.recycle(urls) { _, error in
            Task { @MainActor in
                if let error { self.errorMessage = error.localizedDescription }
                self.load()
            }
        }
    }

    func deletePermanently() {
        let urls = Array(selection)
        guard !urls.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = urls.count == 1 ? String(localized: "Permanently delete \"\(urls[0].lastPathComponent)\"?")
                                            : String(localized: "Permanently delete \(urls.count) items?")
        alert.informativeText = String(localized: "They won't be moved to the Trash and can't be recovered.")
        alert.alertStyle = .critical
        alert.addButton(withTitle: String(localized: "Delete"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        for u in urls {
            do { try FileManager.default.removeItem(at: u) } catch { errorMessage = error.localizedDescription }
        }
        load()
    }

    func rename(_ item: FileItem, to newName: String) {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, name != item.url.lastPathComponent else { return }
        guard !name.contains("/") else { errorMessage = String(localized: "The name can't contain \"/\"."); return }
        let target = item.url.deletingLastPathComponent().appendingPathComponent(name)
        do {
            try FileManager.default.moveItem(at: item.url, to: target)
            selection = [target]
            load()
        } catch {
            errorMessage = FileManager.default.fileExists(atPath: target.path)
                ? String(localized: "An item named \"\(name)\" already exists.") : error.localizedDescription
        }
    }

    func newFolder() {
        let target = FileOps.uniqueURL(for: String(localized: "New Folder"), in: url, copySuffix: false)
        do {
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
            afterCreate(target)
        } catch { errorMessage = error.localizedDescription }
    }

    func newTextFile() {
        let target = FileOps.uniqueURL(for: String(localized: "New Text Document.txt"), in: url, copySuffix: false)
        if FileManager.default.createFile(atPath: target.path, contents: Data()) { afterCreate(target) }
        else { errorMessage = String(localized: "Couldn't create the file here.") }
    }

    /// After creating something: selects it and starts renaming right away (like Windows).
    private func afterCreate(_ target: URL) {
        selection = [target]
        if let item = FileItem(url: target) {
            items.append(item)
            renaming = item
        }
    }

    func duplicateSelection() { transfer(Array(selection), to: url, move: false) }

    func compressSelection() {
        let urls = Array(selection)
        guard !urls.isEmpty else { return }
        Task.detached {
            let error = FileOps.zip(urls, in: await self.url)
            await MainActor.run { if let error { self.errorMessage = error }; self.load() }
        }
    }

    func extract(_ zip: URL) {
        Task.detached {
            let error = FileOps.unzip(zip)
            await MainActor.run { if let error { self.errorMessage = error }; self.load() }
        }
    }

    func copyPaths() {
        let paths = selectedItems.map(\.url.path)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(paths.isEmpty ? url.path : paths.joined(separator: "\n"), forType: .string)
    }
}
