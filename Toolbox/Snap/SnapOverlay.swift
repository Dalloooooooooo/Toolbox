import Cocoa

/// Translucent rectangle showing where the window will go, below the dragged window.
final class SnapOverlay {
    private var panel: NSPanel?

    func show(_ r: CGRect, below id: CGWindowID) {
        let p = panel ?? make()
        panel = p
        hiding = false
        let target = ScreenGeo.ns(r)
        let smooth = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if p.isVisible {
            // from one zone to another: glides over
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = smooth ? 0.18 : 0
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                p.animator().setFrame(target, display: true)
                p.animator().alphaValue = 1
            }
        } else {
            // appears by growing out of the mouse pointer, like on Windows
            let m = NSEvent.mouseLocation
            let seed = NSRect(x: m.x - 40, y: m.y - 40, width: 80, height: 80)
            p.setFrame(smooth ? Self.mix(seed, target, 0.3) : target, display: true)
            p.alphaValue = 0
            p.order(.below, relativeTo: Int(id))
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = smooth ? 0.2 : 0.08
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                p.animator().setFrame(target, display: true)
                p.animator().alphaValue = 1
            }
        }
    }

    /// Fades out (while the window glides into the place it showed).
    func hide() {
        guard let p = panel, p.isVisible, !hiding else { return }
        hiding = true
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.16
            p.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            if self?.hiding == true { p.orderOut(nil); self?.hiding = false }
        })
    }

    private var hiding = false

    private static func mix(_ a: NSRect, _ b: NSRect, _ t: CGFloat) -> NSRect {
        NSRect(x: a.minX + (b.minX - a.minX) * t, y: a.minY + (b.minY - a.minY) * t,
               width: a.width + (b.width - a.width) * t, height: a.height + (b.height - a.height) * t)
    }

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
