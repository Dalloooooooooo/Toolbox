import Cocoa
import Combine
import Quartz

/// "File Explorer": a Windows-style file manager (part of Toolbox, like Power).
@MainActor
final class ExplorerApp: NSObject, NSApplicationDelegate {
    static let shared = ExplorerApp()
    private var controllers: [ExplorerWindowController] = []
    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = makeMenu()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in self?.handleKey(e) ?? e }
        if controllers.isEmpty { newWindow(at: FileManager.default.homeDirectoryForCurrentUser) }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { newWindow(at: FileManager.default.homeDirectoryForCurrentUser) }
        return true
    }

    /// Folders opened with "Open With → File Explorer" or dropped onto the icon.
    func application(_ application: NSApplication, open urls: [URL]) {
        for u in urls {
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: u.path, isDirectory: &isDir)
            if isDir.boolValue { newWindow(at: u) }
            else {
                let c = newWindow(at: u.deletingLastPathComponent())
                c.model.selection = [u]
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true } // like Windows

    @discardableResult
    func newWindow(at url: URL, tabOf parent: NSWindow? = nil) -> ExplorerWindowController {
        let c = ExplorerWindowController(url: url)
        controllers.append(c)
        if let parent, let w = c.window {
            parent.addTabbedWindow(w, ordered: .above)
            w.makeKeyAndOrderFront(nil)
        } else {
            c.showWindow(nil)
        }
        NSApp.activate()
        c.focusList()
        return c
    }

    func closed(_ c: ExplorerWindowController) { controllers.removeAll { $0 === c } }

    var current: ExplorerWindowController? {
        controllers.first { $0.window == NSApp.keyWindow } ?? controllers.first { $0.window == NSApp.mainWindow }
    }

    // MARK: keyboard (like Windows)

    private func handleKey(_ e: NSEvent) -> NSEvent? {
        guard let c = current, e.window == c.window else { return e }
        // while typing (address, search, rename) keys belong to the text field
        if c.window?.firstResponder is NSText || c.window?.attachedSheet != nil { return e }
        let m = c.model
        let flags = e.modifierFlags.intersection([.command, .option, .shift, .control])
        switch (e.keyCode, flags) {
        case (36, []), (76, []): m.openSelection()                       // Return
        case (125, [.command]): m.openSelection()                        // ⌘↓
        case (120, []): if let i = m.selectedItems.first, m.selection.count == 1 { m.renaming = i } // F2
        case (117, []), (51, [.command]): m.trashSelection()             // ⌦ (forward delete), ⌘⌫
        case (117, [.shift]): m.deletePermanently()                      // Shift+⌦
        case (51, []), (123, [.option]): m.goBack()                      // ⌫, ⌥←
        case (124, [.option]): m.goForward()                             // ⌥→
        case (126, [.option]), (126, [.command]): m.goUp()               // ⌥↑, ⌘↑
        case (96, []), (15, [.command]): m.refresh()                     // F5, ⌘R
        case (49, []): c.toggleQuickLook()                               // Space: preview (like PowerToys Peek)
        case (8, [.command]): m.copySelection()                          // ⌘C
        case (7, [.command]): m.cutSelection()                           // ⌘X
        case (9, [.command]): m.paste()                                  // ⌘V
        case (0, [.command]): m.selection = Set(m.displayed.map(\.url))  // ⌘A
        case (2, [.command]): m.duplicateSelection()                     // ⌘D
        case (37, [.command]), (2, [.option]): m.editingAddress = true   // ⌘L, ⌥D
        case (3, [.command]): m.focusSearch = true                       // ⌘F
        case (53, []): if !m.search.isEmpty { m.search = "" } else { m.selection = [] } // Esc
        default: return e
        }
        return nil
    }

    // MARK: menu

    @objc func newWindowAction() { newWindow(at: current?.model.url ?? FileManager.default.homeDirectoryForCurrentUser) }
    @objc func newTabAction() {
        newWindow(at: current?.model.url ?? FileManager.default.homeDirectoryForCurrentUser, tabOf: current?.window)
    }
    @objc func newFolderAction() { current?.model.newFolder() }
    @objc func newTextAction() { current?.model.newTextFile() }
    @objc func detailsAction() { current?.model.viewMode = .details }
    @objc func iconsAction() { current?.model.viewMode = .icons }
    @objc func hiddenAction() { current?.model.showHidden.toggle(); prefsChanged() }
    @objc func previewAction() { current?.model.showPreview.toggle(); prefsChanged() }
    @objc func backAction() { current?.model.goBack() }
    @objc func forwardAction() { current?.model.goForward() }
    @objc func upAction() { current?.model.goUp() }
    @objc func goPlace(_ sender: NSMenuItem) {
        guard let u = sender.representedObject as? URL else { return }
        if let c = current { c.model.go(to: u) } else { newWindow(at: u) }
    }

    private func prefsChanged() { NotificationCenter.default.post(name: .explorerPrefsChanged, object: nil) }

    private func makeMenu() -> NSMenu {
        let main = NSMenu()
        func sub(_ title: String, _ items: [NSMenuItem]) {
            let item = NSMenuItem()
            let m = NSMenu(title: title)
            items.forEach(m.addItem)
            item.submenu = m
            main.addItem(item)
        }
        func it(_ t: String, _ a: Selector?, _ k: String = "", _ mods: NSEvent.ModifierFlags = .command) -> NSMenuItem {
            let i = NSMenuItem(title: t, action: a, keyEquivalent: k)
            i.keyEquivalentModifierMask = mods
            if let a, responds(to: a) { i.target = self }
            return i
        }
        sub(String(localized: "File Explorer"), [
            it(String(localized: "About File Explorer"), #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
            .separator(),
            it(String(localized: "Hide File Explorer"), #selector(NSApplication.hide(_:)), "h"),
            .separator(),
            it(String(localized: "Quit File Explorer"), #selector(NSApplication.terminate(_:)), "q"),
        ])
        sub(String(localized: "File"), [
            it(String(localized: "New Window"), #selector(newWindowAction), "n"),
            it(String(localized: "New Tab"), #selector(newTabAction), "t"),
            it(String(localized: "New Folder"), #selector(newFolderAction), "n", [.command, .shift]),
            it(String(localized: "New Text Document"), #selector(newTextAction)),
            .separator(),
            it(String(localized: "Close"), #selector(NSWindow.performClose(_:)), "w"),
        ])
        sub(String(localized: "Edit"), [
            it(String(localized: "Undo"), Selector(("undo:")), "z"),
            it(String(localized: "Redo"), Selector(("redo:")), "z", [.command, .shift]),
            .separator(),
            it(String(localized: "Cut"), #selector(NSText.cut(_:)), "x"),
            it(String(localized: "Copy"), #selector(NSText.copy(_:)), "c"),
            it(String(localized: "Paste"), #selector(NSText.paste(_:)), "v"),
            it(String(localized: "Select All"), #selector(NSText.selectAll(_:)), "a"),
        ])
        sub(String(localized: "View"), [
            it(String(localized: "Details"), #selector(detailsAction), "1"),
            it(String(localized: "Large Icons"), #selector(iconsAction), "2"),
            .separator(),
            it(String(localized: "Details Pane"), #selector(previewAction), "p", [.command, .option]),
            it(String(localized: "Hidden Items"), #selector(hiddenAction), ".", [.command, .shift]),
        ])
        let fm = FileManager.default
        var places: [NSMenuItem] = [
            it(String(localized: "Back"), #selector(backAction), "["),
            it(String(localized: "Forward"), #selector(forwardAction), "]"),
            it(String(localized: "Parent Folder"), #selector(upAction)),
            .separator(),
        ]
        let dirs: [(FileManager.SearchPathDirectory, String, NSEvent.ModifierFlags)] = [
            (.desktopDirectory, "d", [.command, .shift]), (.downloadsDirectory, "l", [.command, .option]),
            (.documentDirectory, "o", [.command, .shift]), (.applicationDirectory, "a", [.command, .shift]),
        ]
        let home = it(String(localized: "Home"), #selector(goPlace(_:)), "h", [.command, .shift])
        home.representedObject = fm.homeDirectoryForCurrentUser
        places.append(home)
        for (d, k, mods) in dirs {
            guard let u = fm.urls(for: d, in: d == .applicationDirectory ? .localDomainMask : .userDomainMask).first else { continue }
            let i = it(fm.displayName(atPath: u.path), #selector(goPlace(_:)), k, mods)
            i.representedObject = u
            places.append(i)
        }
        sub(String(localized: "Go"), places)
        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: String(localized: "Window"))
        windowMenu.addItem(it(String(localized: "Minimize"), #selector(NSWindow.performMiniaturize(_:)), "m"))
        windowMenu.addItem(it(String(localized: "Zoom"), #selector(NSWindow.performZoom(_:))))
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        NSApp.windowsMenu = windowMenu
        return main
    }
}
