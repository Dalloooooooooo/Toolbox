import Cocoa
import SwiftUI
import QuickLookThumbnailing

struct RenameSheet: View {
    @ObservedObject var model: ExplorerModel
    let item: FileItem
    @State private var name = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rename").font(.headline)
            RenameField(text: $name, selectUpTo: item.isFolder ? nil : (item.url.lastPathComponent as NSString).deletingPathExtension.count) {
                commit()
            }
            .frame(width: 380)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Rename") { commit() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .onAppear { name = item.url.lastPathComponent }
    }

    private func commit() {
        model.rename(item, to: name)
        dismiss()
    }
}

private struct RenameField: NSViewRepresentable {
    @Binding var text: String
    let selectUpTo: Int?
    let onSubmit: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let f = NSTextField()
        f.delegate = context.coordinator
        f.stringValue = text
        DispatchQueue.main.async {
            f.stringValue = text
            f.window?.makeFirstResponder(f)
            if let editor = f.currentEditor() {
                let len = (text as NSString).length
                editor.selectedRange = NSRange(location: 0, length: min(selectUpTo.map { ($0 > 0 ? (text as NSString).deletingPathExtension as NSString : text as NSString).length } ?? len, len))
            }
        }
        return f
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        let parent: RenameField
        init(_ p: RenameField) { parent = p }
        func controlTextDidChange(_ obj: Notification) {
            if let f = obj.object as? NSTextField { parent.text = f.stringValue }
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
            if sel == #selector(NSResponder.insertNewline(_:)) { parent.onSubmit(); return true }
            return false
        }
    }
}
