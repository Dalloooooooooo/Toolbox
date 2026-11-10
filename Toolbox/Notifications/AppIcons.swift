import Cocoa
import SwiftUI

enum AppIcons {
    private static var cache: [String: NSImage] = [:]

    static func cached(_ name: String) -> NSImage? {
        if let img = cache[name] { return img }
        let key = AppIndex.normalize(name)
        if let app = NSWorkspace.shared.runningApplications.first(where: { AppIndex.normalize($0.localizedName ?? "") == key }),
           let icon = app.icon {
            cache[name] = icon
            return icon
        }
        if let path = AppIndex.path(for: name) {
            let icon = NSWorkspace.shared.icon(forFile: path)
            cache[name] = icon
            return icon
        }
        return nil
    }

    /// If we didn't find it right away: rebuild the index (recently installed app) and try again.
    static func lookup(_ name: String, completion: @escaping (NSImage) -> Void) {
        guard !name.isEmpty else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            AppIndex.build()
            guard let path = AppIndex.path(for: name) else { return }
            DispatchQueue.main.async {
                let icon = NSWorkspace.shared.icon(forFile: path)
                cache[name] = icon
                completion(icon)
            }
        }
    }

    private static var colorCache: [ObjectIdentifier: Color?] = [:]

    /// Main color of an icon: scaled down to 24×24, colored pixels are grouped by hue
    /// and the "heaviest" group wins (gray, white, black or transparent pixels don't count).
    static func dominantColor(of image: NSImage) -> Color? {
        if let cached = colorCache[ObjectIdentifier(image)] { return cached }
        let n = 24
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: n, pixelsHigh: n, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: n, height: n))
        NSGraphicsContext.restoreGraphicsState()

        var weight = [Double](repeating: 0, count: 12)
        var sums = [(h: Double, s: Double, b: Double)](repeating: (0, 0, 0), count: 12)
        for x in 0..<n { for y in 0..<n {
            guard let c = rep.colorAt(x: x, y: y), c.alphaComponent > 0.5 else { continue }
            var h: CGFloat = 0, sat: CGFloat = 0, br: CGFloat = 0, a: CGFloat = 0
            c.getHue(&h, saturation: &sat, brightness: &br, alpha: &a)
            guard sat > 0.25, br > 0.25 else { continue }
            let bucket = min(11, Int(h * 12)), w = Double(sat * br)
            weight[bucket] += w
            sums[bucket].h += Double(h) * w; sums[bucket].s += Double(sat) * w; sums[bucket].b += Double(br) * w
        }}
        var result: Color? = nil
        if let best = weight.indices.max(by: { weight[$0] < weight[$1] }), weight[best] > 4 {
            let w = weight[best]
            result = Color(hue: sums[best].h / w, saturation: min(1, sums[best].s / w * 1.1), brightness: sums[best].b / w)
        }
        colorCache[ObjectIdentifier(image)] = result
        return result
    }

    static func open(appNamed name: String) {
        let key = AppIndex.normalize(name)
        if let app = NSWorkspace.shared.runningApplications.first(where: { AppIndex.normalize($0.localizedName ?? "") == key }) {
            app.activate(options: [])
        } else if let path = AppIndex.path(for: name) {
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        }
    }
}
