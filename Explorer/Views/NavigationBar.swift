import Cocoa
import SwiftUI
import QuickLookThumbnailing

struct NavBar: View {
    @ObservedObject var model: ExplorerModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            navButton("chevron.left", String(localized: "Back (⌥←)"), model.canGoBack) { model.goBack() }
            navButton("chevron.right", String(localized: "Forward (⌥→)"), model.canGoForward) { model.goForward() }
            navButton("arrow.up", String(localized: "Parent Folder (⌥↑)"), model.canGoUp) { model.goUp() }
            navButton("arrow.clockwise", String(localized: "Refresh (F5)"), true) { model.refresh() }
            AddressBar(model: model)
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search \(FileManager.default.displayName(atPath: model.url.path))", text: $model.search)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                if model.searching { ProgressView().controlSize(.small) }
                if !model.search.isEmpty {
                    Button { model.search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8).frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.06)))
            .frame(width: 240)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .onChange(of: model.focusSearch) { _, v in if v { searchFocused = true; model.focusSearch = false } }
    }

    private func navButton(_ icon: String, _ help: String, _ enabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 13, weight: .semibold)).frame(width: 28, height: 28)
        }
        .buttonStyle(.borderless)
        .disabled(!enabled)
        .help(help)
    }
}

/// Address shown as clickable breadcrumbs; clicking the empty space (or ⌘L) lets you type a path.
private struct AddressBar: View {
    @ObservedObject var model: ExplorerModel
    @State private var text = ""
    @FocusState private var focused: Bool

    private var crumbs: [URL] {
        var list: [URL] = []
        var u = model.url.standardizedFileURL
        while true {
            list.insert(u, at: 0)
            let parent = u.deletingLastPathComponent()
            if parent.path == u.path || u.path == "/" { break }
            u = parent
        }
        // start from the Home folder when we are inside it, like Windows does with "This PC"
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        if let i = list.firstIndex(of: home) { list.removeFirst(i) }
        return list
    }

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.06))
            if model.editingAddress {
                TextField("Path", text: $text)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 8)
                    .focused($focused)
                    .onSubmit(submit)
                    .onExitCommand { model.editingAddress = false }
                    .onAppear { text = model.url.path; focused = true }
                    .onChange(of: focused) { _, f in if !f { model.editingAddress = false } }
            } else {
                HStack(spacing: 0) {
                    Image(nsImage: Icons.icon(model.url)).resizable().frame(width: 16, height: 16).padding(.horizontal, 6)
                    // long paths: scroll so the current folder is always visible
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 0) {
                                ForEach(Array(crumbs.enumerated()), id: \.offset) { i, u in
                                    if i > 0 { Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(.tertiary).padding(.horizontal, 2) }
                                    Button(FileManager.default.displayName(atPath: u.path)) { model.go(to: u) }
                                        .buttonStyle(CrumbStyle())
                                        .dropDestination(for: URL.self) { urls, _ in model.transfer(urls, to: u, move: true); return true }
                                        .id(i)
                                }
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .onAppear { proxy.scrollTo(crumbs.count - 1, anchor: .trailing) }
                        .onChange(of: model.url) { _, _ in proxy.scrollTo(crumbs.count - 1, anchor: .trailing) }
                    }
                    Spacer(minLength: 20)
                        .contentShape(Rectangle())
                        .onTapGesture { model.editingAddress = true }
                }
            }
        }
        .frame(height: 28)
        .frame(maxWidth: .infinity)
    }

    private func submit() {
        var path = text.trimmingCharacters(in: .whitespaces)
        if path.hasPrefix("~") { path = (path as NSString).expandingTildeInPath }
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDir) {
            let u = URL(fileURLWithPath: path)
            if isDir.boolValue { model.go(to: u) } else { NSWorkspace.shared.open(u) }
            model.editingAddress = false
        } else {
            model.errorMessage = String(localized: "Can't find \"\(text)\". Check the path and try again.")
        }
    }
}

private struct CrumbStyle: ButtonStyle {
    @State private var hover = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12))
            .lineLimit(1)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(configuration.isPressed ? 0.15 : hover ? 0.08 : 0)))
            .onHover { hover = $0 }
    }
}
