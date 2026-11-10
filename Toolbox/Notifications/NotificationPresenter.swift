import Cocoa
import SwiftUI

final class NotificationPresenter {
    static let shared = NotificationPresenter()

    private final class Card {
        let content: NotificationContent
        let original: AXUIElement?
        let panel: NSPanel
        let countdown = Countdown()
        var duration: Double = 6
        var remaining: Double = 6
        var paused = false
        var height: CGFloat = 0
        init(content: NotificationContent, original: AXUIElement?, panel: NSPanel) {
            self.content = content
            self.original = original
            self.panel = panel
        }
    }

    private var cards: [Card] = [] // most recent first
    private var ticker: Timer?
    private var lastTick = Date()
    private let margin: CGFloat = 30 // space around the notification for the shadow
    private let spacing: CGFloat = 10
    private let maxCards = 4

    func show(_ content: NotificationContent, original: AXUIElement?) {
        let look = NotificationLook.current
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let card = Card(content: content, original: original, panel: panel)
        card.duration = look.duration
        card.remaining = look.duration
        let view = NotificationCard(content: content, look: look, countdown: card.countdown,
                                    onClose: { [weak self, weak card] in if let card { self?.dismiss(card, closeOriginal: true) } },
                                    onHover: { [weak self, weak card] h in if let card { self?.hover(card, h) } })
            .padding(margin)
            .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
            .contentShape(Rectangle())
            .onTapGesture { [weak self, weak card] in if let card { self?.activate(card) } }
        let host = NSHostingView(rootView: view)
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        panel.contentView = host
        card.height = size.height - 2 * margin

        // starts above the screen and slides down
        let screen = Self.screen
        panel.setFrame(NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY, width: size.width, height: size.height),
                       display: false)
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        cards.insert(card, at: 0)
        while cards.count > maxCards, let last = cards.last { dismiss(last, closeOriginal: false) }
        layout()
        startTicker()
    }

    private static var screen: NSScreen { NSScreen.screens.first ?? NSScreen.main! }

    /// Stacks the notifications one below the other, under the menu bar, with a small bounce.
    private func layout() {
        let screen = Self.screen
        var top = screen.visibleFrame.maxY + margin - 8
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.45
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 1.25, 0.35, 1)
            for card in cards {
                let size = card.panel.frame.size
                let frame = NSRect(x: screen.frame.midX - size.width / 2, y: top - size.height, width: size.width, height: size.height)
                card.panel.animator().setFrame(frame, display: true)
                top -= card.height + spacing
            }
        }
    }

    /// A single timer for all notifications: counts down the remaining time and updates the bars.
    private func startTicker() {
        guard ticker == nil else { return }
        lastTick = Date()
        let t = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    private func tick() {
        let now = Date(), dt = now.timeIntervalSince(lastTick)
        lastTick = now
        for card in cards where !card.paused {
            card.remaining -= dt
            card.countdown.progress = max(0, card.remaining / card.duration)
            if card.remaining <= 0 { dismiss(card, closeOriginal: false) }
        }
        if cards.isEmpty { ticker?.invalidate(); ticker = nil }
    }

    /// With the mouse over it, time stops; when the mouse leaves it resumes where it was (at least one second).
    private func hover(_ card: Card, _ inside: Bool) {
        card.paused = inside
        if !inside { card.remaining = max(card.remaining, 1) }
    }

    private func activate(_ card: Card) {
        if let action = card.content.action {
            action()
        } else if let original = card.original, NotificationMover.press(original) {
        } else {
            AppIcons.open(appNamed: card.content.appName) // the real notification is already gone: at least open the app
        }
        dismiss(card, closeOriginal: false)
    }

    private func dismiss(_ card: Card, closeOriginal: Bool) {
        guard let i = cards.firstIndex(where: { $0 === card }) else { return }
        cards.remove(at: i)
        if closeOriginal, let original = card.original { NotificationMover.close(original) }
        let panel = card.panel
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            var f = panel.frame
            f.origin.y += 60
            panel.animator().setFrame(f, display: true)
            panel.animator().alphaValue = 0
        }, completionHandler: { panel.orderOut(nil) })
        layout()
    }
}
