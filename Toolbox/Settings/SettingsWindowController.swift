import Cocoa
import SwiftUI

/// The settings window. While it is open Toolbox is a "regular" app: it shows up in the Dock and has
/// its own menu bar; when it closes, Toolbox goes back to living only in the menu bar.
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var policyTimer: Timer?

    func show() {
        if window == nil {
            let host = NSHostingController(rootView: SettingsView())
            host.sizingOptions = [.minSize] // the window can be resized freely
            let w = NSWindow(contentViewController: host)
            w.title = String(localized: "Toolbox Settings")
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            w.toolbarStyle = .unified
            w.isReleasedWhenClosed = false
            w.delegate = self
            // initial size fitted to the screen; after that Toolbox remembers the size the user picked
            if !w.setFrameUsingName(Self.autosaveName) { w.setFrame(Self.idealFrame(on: NSScreen.main), display: false) }
            w.setFrameAutosaveName(Self.autosaveName)
            window = w
            // safety check: if for any reason Toolbox went back to "menu bar only" while the window is open,
            // it would disappear from the Dock and Alt+Tab and could no longer be closed
            let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.syncPolicy() }
            RunLoop.main.add(t, forMode: .common)
            policyTimer = t
        }
        if let w = window { fit(w) }
        if let w = window, w.isMiniaturized { w.deminiaturize(nil) }
        window?.makeKeyAndOrderFront(nil)
        syncPolicy()
        NSApp.activate()
        Updater.shared.settingsOpened() // updates are only checked for here
    }

    /// Window open (even minimized to the Dock) → regular app with a Dock icon and menus;
    /// window closed → menu bar only.
    private func syncPolicy(closing: Bool = false) {
        let open = !closing && (window?.isVisible == true || window?.isMiniaturized == true)
        if open, NSApp.activationPolicy() != .regular {
            NSApp.mainMenu = Self.makeMainMenu()
            NSApp.setActivationPolicy(.regular)
        } else if !open, NSApp.activationPolicy() == .regular {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private static let autosaveName = "ToolboxSettings"

    /// 80% of the screen's usable width and 85% of its usable height, without going overboard on large monitors.
    private static func idealFrame(on screen: NSScreen?) -> NSRect {
        let area = (screen ?? NSScreen.screens[0]).visibleFrame
        let size = NSSize(width: min(960, area.width * 0.8), height: min(820, area.height * 0.85))
        return NSRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2, width: size.width, height: size.height)
    }

    /// If the window doesn't fit on its current screen (e.g. a size saved on a larger monitor),
    /// shrinks it and moves it back inside.
    private func fit(_ w: NSWindow) {
        guard let area = (w.screen ?? NSScreen.main)?.visibleFrame else { return }
        var f = w.frame
        f.size.width = min(f.width, area.width)
        f.size.height = min(f.height, area.height)
        f.origin.x = min(max(f.minX, area.minX), area.maxX - f.width)
        f.origin.y = min(max(f.minY, area.minY), area.maxY - f.height)
        if f != w.frame { w.setFrame(f, display: true) }
    }

    /// Closing the window frees it entirely (views, previews, timers): it is rebuilt the next time.
    func windowWillClose(_ notification: Notification) {
        syncPolicy(closing: true)
        policyTimer?.invalidate()
        policyTimer = nil
        DispatchQueue.main.async { [weak self] in
            self?.window?.contentViewController = nil
            self?.window = nil
        }
    }

    /// The app's menus (Toolbox / Edit): also needed for ⌘C / ⌘V to work in text fields.
    private static func makeMainMenu() -> NSMenu {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu(title: "Toolbox")
        appMenu.addItem(withTitle: String(localized: "About Toolbox"), action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: String(localized: "Close Window"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        appMenu.addItem(withTitle: String(localized: "Quit Toolbox"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: String(localized: "Edit"))
        edit.addItem(withTitle: String(localized: "Undo"), action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: String(localized: "Redo"), action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: String(localized: "Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: String(localized: "Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: String(localized: "Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: String(localized: "Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        return main
    }
}
