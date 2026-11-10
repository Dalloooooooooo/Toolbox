import Cocoa
import CoreImage

/// Color variants of the Power icon, derived from the original (yellow) icon by shifting its hue:
/// shape, highlights and the white symbol stay the same. Used both by Power and by Toolbox settings.
enum PowerIconVariant: String, CaseIterable, Identifiable {
    case yellow, red, pink, purple, blue, teal, green, graphite
    var id: String { rawValue }

    var label: String {
        switch self {
        case .yellow: String(localized: "Yellow (original)")
        case .red: String(localized: "Red")
        case .pink: String(localized: "Pink")
        case .purple: String(localized: "Purple")
        case .blue: String(localized: "Blue")
        case .teal: String(localized: "Teal")
        case .green: String(localized: "Green")
        case .graphite: String(localized: "Graphite")
        }
    }

    /// hue rotation in degrees, starting from the original's yellow-orange
    private var hueShift: Double? {
        switch self {
        case .yellow, .graphite: nil
        case .red: -38
        case .pink: -72
        case .purple: -125
        case .blue: 172
        case .teal: 140
        case .green: 95
        }
    }

    /// after the hue shift some colors come out "pastel": we make them vivid again
    private var saturation: Double {
        switch self {
        case .red: 1.7
        case .pink: 1.35
        case .purple: 1.45
        case .blue: 1.15
        default: 1
        }
    }

    private var brightness: Double { self == .red ? -0.06 : 0 }

    func apply(to base: NSImage) -> NSImage {
        guard self != .yellow, let tiff = base.tiffRepresentation, var ci = CIImage(data: tiff) else { return base }
        if let shift = hueShift {
            ci = ci.applyingFilter("CIHueAdjust", parameters: [kCIInputAngleKey: shift * .pi / 180])
                .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: saturation,
                                                                kCIInputBrightnessKey: brightness])
        } else {
            // graphite: no color, darkened background, the white symbol stays white
            ci = ci.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
                .applyingFilter("CIToneCurve", parameters: [
                    "inputPoint0": CIVector(x: 0, y: 0), "inputPoint1": CIVector(x: 0.25, y: 0.12),
                    "inputPoint2": CIVector(x: 0.5, y: 0.22), "inputPoint3": CIVector(x: 0.75, y: 0.38),
                    "inputPoint4": CIVector(x: 1, y: 1)])
        }
        let rep = NSCIImageRep(ciImage: ci)
        let out = NSImage(size: base.size)
        out.addRepresentation(rep)
        return out
    }

    /// The original icon, inside Power.app (Resources/PowerBase.png).
    static func baseImage(in powerBundle: Bundle) -> NSImage? {
        powerBundle.url(forResource: "PowerBase", withExtension: "png").flatMap(NSImage.init(contentsOf:))
    }
}
