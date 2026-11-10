import Cocoa
import SwiftUI
import QuickLookThumbnailing

private struct Place: Identifiable, Hashable {
    let url: URL
    let title: String
    let icon: String
    var id: URL { url }
}

struct Sidebar: View {
    @ObservedObject var model: ExplorerModel
    @State private var volumes: [URL] = []

    private var places: [Place] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        var list = [Place(url: home, title: fm.displayName(atPath: home.path), icon: "house.fill")]
        let dirs: [(FileManager.SearchPathDirectory, String)] = [
            (.desktopDirectory, "menubar.dock.rectangle"), (.downloadsDirectory, "arrow.down.circle.fill"),
            (.documentDirectory, "doc.fill"), (.picturesDirectory, "photo.fill"),
            (.musicDirectory, "music.note"), (.moviesDirectory, "film.fill"),
        ]
        for (d, icon) in dirs {
            if let u = fm.urls(for: d, in: .userDomainMask).first {
                list.append(Place(url: u, title: fm.displayName(atPath: u.path), icon: icon))
            }
        }
        let icloud = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        if fm.fileExists(atPath: icloud.path) { list.append(Place(url: icloud, title: "iCloud Drive", icon: "icloud.fill")) }
        list.append(Place(url: URL(fileURLWithPath: "/Applications"), title: fm.displayName(atPath: "/Applications"), icon: "square.grid.3x3.fill"))
        return list
    }

    var body: some View {
        List {
            Section("Quick Access") {
                ForEach(places) { p in
                    row(p.title, p.icon, p.url)
                }
            }
            Section("This Mac") {
                ForEach(volumes, id: \.self) { v in VolumeRow(url: v, model: model) }
            }
        }
        .listStyle(.sidebar)
        .onAppear(perform: loadVolumes)
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { _ in loadVolumes() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { _ in loadVolumes() }
    }

    private func row(_ title: String, _ icon: String, _ url: URL) -> some View {
        let active = model.url.standardizedFileURL == url.standardizedFileURL
        return Button { model.go(to: url) } label: {
            Label(title, systemImage: icon)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(active ? RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.25)) : nil)
        .dropDestination(for: URL.self) { urls, _ in
            model.transfer(urls, to: url, move: NSEvent.modifierFlags.contains(.option) ? false : true); return true
        }
    }

    private func loadVolumes() {
        volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeNameKey],
                                                        options: [.skipHiddenVolumes]) ?? []
    }
}

/// Disk with a used-space bar, like "This PC" on Windows.
private struct VolumeRow: View {
    let url: URL
    @ObservedObject var model: ExplorerModel

    var body: some View {
        let v = try? url.resourceValues(forKeys: [.volumeNameKey, .volumeTotalCapacityKey,
                                                   .volumeAvailableCapacityForImportantUsageKey, .volumeIsRemovableKey])
        let total = Int64(v?.volumeTotalCapacity ?? 0)
        let free = v?.volumeAvailableCapacityForImportantUsage ?? 0
        let used = total > 0 ? Double(total - free) / Double(total) : 0
        Button { model.go(to: url) } label: {
            VStack(alignment: .leading, spacing: 3) {
                Label(v?.volumeName ?? url.lastPathComponent, systemImage: v?.volumeIsRemovable == true ? "externaldrive.fill" : "internaldrive.fill")
                if total > 0 {
                    ProgressView(value: used).tint(used > 0.9 ? .red : .accentColor).controlSize(.small)
                    Text("\(Fmt.size(free)) free of \(Fmt.size(total))").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
