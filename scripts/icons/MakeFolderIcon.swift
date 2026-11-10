import Cocoa
// Placeholder icon for File Explorer: the system folder icon with a magnifying glass.
let size = NSSize(width: 1024, height: 1024)
let img = NSImage(size: size)
img.lockFocus()
NSWorkspace.shared.icon(for: .folder).draw(in: NSRect(origin: .zero, size: size))
if let lens = NSImage(systemSymbolName: "magnifyingglass.circle.fill", accessibilityDescription: nil)?
    .withSymbolConfiguration(.init(pointSize: 360, weight: .bold).applying(.init(paletteColors: [.white, .systemBlue]))) {
    lens.draw(in: NSRect(x: 560, y: 120, width: 380, height: 380))
}
img.unlockFocus()
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
