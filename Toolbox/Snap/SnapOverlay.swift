import Cocoa

/// Translucent rectangle showing where the window will go, below the dragged window.
final class SnapOverlay {
    private var panel: NSPanel?

    func show(_ r: CGRect, below id: CGWindowID) {
        let p = panel ?? make()
        panel = p
        let target = ScreenGeo.ns(r)
        if p.isVisible {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.12
                p.animator().setFrame(target, display: true)
            }
        } else {
            p.setFrame(target, display: true)
            p.alphaValue = 0
            p.order(.below, relativeTo: Int(id))
            NSAnimationContext.runAnimationGroup { $0.duration = 0.12; p.animator().alphaValue = 1 }
        }
    }

    func hide() { panel?.orderOut(nil) }

    private func make() -> NSPanel {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.level = .normal
        p.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        p.hidesOnDeactivate = false
        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 12
        blur.layer?.masksToBounds = true
        blur.layer?.borderWidth = 2
        blur.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.8).cgColor
        blur.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
        p.contentView = blur
        return p
    }
}
