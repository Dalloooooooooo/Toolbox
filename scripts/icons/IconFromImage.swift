// Turns a "flat" drawing (white background around it) into a macOS icon with transparent corners.
// swift scripts/icons/IconFromImage.swift <source.png> <x> <y> <width> <height> <out.png>
// x/y/width/height: rectangle of the rounded shape in the source (origin at the top left)
import Cocoa

let a = CommandLine.arguments
let src = NSImage(contentsOfFile: a[1])!
let rep = src.representations[0]
let (sx, sy, sw, sh) = (CGFloat(Double(a[2])!), CGFloat(Double(a[3])!), CGFloat(Double(a[4])!), CGFloat(Double(a[5])!))
let fromRect = NSRect(x: sx, y: CGFloat(rep.pixelsHigh) - sy - sh, width: sw, height: sh) // AppKit: origin at the bottom
src.size = NSSize(width: rep.pixelsWide, height: rep.pixelsHigh)

let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
let ctx = NSGraphicsContext.current!.cgContext
ctx.interpolationQuality = .high

let target = NSRect(x: 100, y: 100, width: 824, height: 824) // standard macOS icon grid
let shape = NSBezierPath(roundedRect: target, xRadius: 185, yRadius: 185)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: NSColor.black.withAlphaComponent(0.3).cgColor)
NSColor.white.setFill(); shape.fill()
ctx.restoreGState()
shape.addClip()
src.draw(in: target, from: fromRect, operation: .copy, fraction: 1)
NSGraphicsContext.restoreGraphicsState()
try! out.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: a[6]))
