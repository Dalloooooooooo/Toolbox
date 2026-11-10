import Cocoa

/// System service (see NSServices in Info.plist): appears in the Finder's right-click menu.
final class WallpaperService: NSObject {
    @objc func setWallpaper(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        let urls = pboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard let url = urls.first else { error.pointee = String(localized: "No image selected") as NSString; return }
        for screen in NSScreen.screens {
            let options = NSWorkspace.shared.desktopImageOptions(for: screen) ?? [:]
            do { try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: options) }
            catch { NSLog("Toolbox: wallpaper not set: \(error)") }
        }
    }
}
