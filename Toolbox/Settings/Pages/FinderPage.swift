import Cocoa
import SwiftUI

struct FinderPage: View {
    @AppStorage(Pref.finderKeys) private var finderKeys = true
    @State private var values: [String: Bool] = Dictionary(uniqueKeysWithValues: FinderPrefs.all.map { ($0.id, $0.enabled) })
    @State private var pending: DispatchWorkItem?
    @State private var applied = FinderPrefs.applied

    var body: some View {
        Form {
            if !applied {
                Section {
                    Label("The Finder hasn't been set up like File Explorer yet", systemImage: "folder.badge.gearshape")
                        .font(.headline)
                    Text("Visible extensions, folders before files, path bar, folder sizes and the other settings below. The Finder restarts for a moment; you can always go back to how it was.")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("Apply recommended settings") {
                        FinderPrefs.applyAll()
                        applied = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            Section("Windows keys in the Finder") {
                Toggle("Use File Explorer keys in the Finder", isOn: $finderKeys)
                Group {
                    LabeledContent("Return") { Text("opens the file or folder") }
                    LabeledContent("F2") { Text("renames") }
                    LabeledContent("Delete (fn ⌫)") { Text("moves to the Trash · with Shift, deletes immediately") }
                    LabeledContent("⌫") { Text("goes back") }
                    LabeledContent("Ctrl+X, then Ctrl+V") { Text("moves the files (also with ⌘)") }
                }
                .foregroundStyle(finderKeys ? .primary : .secondary)
                Text("The Finder itself carries out every operation (with its own progress bar, the prompt to replace files, and Undo). While you rename or type in a field, the keys work as usual.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("Appearance and behavior") {
                ForEach(FinderPrefs.all) { p in
                    VStack(alignment: .leading, spacing: 2) {
                        Toggle(p.label, isOn: Binding(get: { values[p.id] ?? p.enabled }, set: { set(p, $0) }))
                        if !p.help.isEmpty { Text(p.help).font(.caption).foregroundStyle(.secondary) }
                    }
                }
                Text("These are Finder settings provided by Apple. After each change the Finder restarts for a moment (open windows reopen).")
                    .font(.callout).foregroundStyle(.secondary)
                if FinderPrefs.hasBackup {
                    Button("Restore the Finder as it was before Toolbox") {
                        FinderPrefs.restoreOriginal()
                        values = Dictionary(uniqueKeysWithValues: FinderPrefs.all.map { ($0.id, false) })
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func set(_ p: FinderPref, _ on: Bool) {
        values[p.id] = on
        applied = true
        UserDefaults.standard.set(on, forKey: "finder.\(p.id)")
        // several toggles in a row: only one Finder restart
        pending?.cancel()
        let work = DispatchWorkItem { FinderPrefs.applyAll() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }
}
