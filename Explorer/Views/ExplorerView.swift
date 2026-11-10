import Cocoa
import SwiftUI
import QuickLookThumbnailing

// MARK: - Main window

struct ExplorerView: View {
    @ObservedObject var model: ExplorerModel

    var body: some View {
        NavigationSplitView {
            Sidebar(model: model)
                .navigationSplitViewColumnWidth(min: 170, ideal: 210, max: 320)
        } detail: {
            VStack(spacing: 0) {
                NavBar(model: model)
                CommandBar(model: model)
                Divider()
                HSplitView {
                    content
                        .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
                    if model.showPreview {
                        DetailsPane(model: model)
                            .frame(minWidth: 220, idealWidth: 260, maxWidth: 300, maxHeight: .infinity)
                    }
                }
                Divider()
                StatusBar(model: model)
            }
        }
        .sheet(item: $model.renaming) { item in RenameSheet(model: model, item: item) }
        .alert("Operation failed", isPresented: Binding(get: { model.errorMessage != nil },
                                                             set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }

    @ViewBuilder private var content: some View {
        if let err = model.loadError {
            VStack(spacing: 10) {
                Image(systemName: "lock.fill").font(.system(size: 36)).foregroundStyle(.secondary)
                Text(err).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.viewMode == .details {
            DetailsTable(model: model)
        } else {
            IconGrid(model: model)
        }
    }
}
