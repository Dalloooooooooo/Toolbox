import Cocoa

// MARK: - Item (file or folder)

struct FileItem: Identifiable, Hashable {
    let url: URL
    var id: URL { url }
    let name: String
    let isFolder: Bool          // a real folder (apps and packages count as files)
    let isHidden: Bool
    let modified: Date
    let created: Date
    let kind: String
    /// Size in bytes: for folders it is computed later, in the background (-1 = not ready yet)
    var size: Int64
    /// Number of contained items (folders only, -1 = not ready yet)
    var count: Int
    var ext: String { isFolder ? "" : url.pathExtension.lowercased() }
    var parent: String { url.deletingLastPathComponent().path }

    static let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .isHiddenKey, .fileSizeKey,
                                         .contentModificationDateKey, .creationDateKey, .localizedTypeDescriptionKey]

    init?(url: URL) {
        guard let v = try? url.resourceValues(forKeys: Set(Self.keys)) else { return nil }
        self.url = url
        isFolder = (v.isDirectory ?? false) && !(v.isPackage ?? false)
        // system folders get their localized name (e.g. Desktop → Scrivania in Italian); files always show their real name and extension
        name = isFolder ? FileManager.default.displayName(atPath: url.path) : url.lastPathComponent
        isHidden = v.isHidden ?? name.hasPrefix(".")
        modified = v.contentModificationDate ?? .distantPast
        created = v.creationDate ?? .distantPast
        kind = v.localizedTypeDescription ?? (isFolder ? String(localized: "Folder") : String(localized: "File"))
        size = isFolder ? -1 : Int64(v.fileSize ?? 0)
        count = isFolder ? -1 : 0
    }
}

enum ViewMode: String, CaseIterable { case details, icons }
