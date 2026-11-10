import Cocoa
import SwiftUI

/// Time left before the notification disappears (1 → 0), for the bar.
final class Countdown: ObservableObject {
    @Published var progress: Double
    init(_ progress: Double = 1) { self.progress = progress }
}

struct NotificationCard: View {
    @ObservedObject var content: NotificationContent
    let look: NotificationLook
    var countdown: Countdown? = nil
    var onClose: (() -> Void)? = nil
    var onHover: ((Bool) -> Void)? = nil
    @State private var hovering = false

    private var s: Double { look.textScale }

    var body: some View {
        VStack(spacing: 12 * s) {
            content_
            if look.showTimer, let countdown { TimerBar(countdown: countdown, scale: s, color: tint) }
        }
        .padding(.horizontal, 18 * s)
        .padding(.vertical, 15 * s)
        .frame(width: look.width)
        .modifier(CardBackground(kind: look.background, radius: look.radius, scheme: scheme,
                                 tint: tint.map { isGlass ? $0 : $0.opacity(look.colorIntensity) },
                                 intensity: look.colorIntensity))
        .overlay(alignment: .topTrailing) {
            if hovering, let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 20))
                        .symbolRenderingMode(.palette).foregroundStyle(.primary, .regularMaterial)
                }
                .buttonStyle(.plain)
                .offset(x: 6, y: -6)
                .help("Close Notification")
            }
        }
        .onHover { h in hovering = h; onHover?(h) }
        .environment(\.colorScheme, scheme)
    }

    private var content_: some View {
        HStack(alignment: .top, spacing: 14 * s) {
            if look.showIcon {
                Group {
                    if let icon = content.icon {
                        Image(nsImage: icon).resizable().interpolation(.high)
                    } else {
                        Image(systemName: "bell.badge.fill").resizable().scaledToFit().padding(8 * s)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 46 * s, height: 46 * s)
            }
            VStack(alignment: .leading, spacing: 3 * s) {
                HStack {
                    Text(content.appName.uppercased())
                        .font(.system(size: 11 * s, weight: .semibold)).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 8)
                    Text("now").font(.system(size: 11 * s)).foregroundStyle(.secondary)
                }
                if !content.title.isEmpty {
                    Text(content.title).font(.system(size: 15 * s, weight: .semibold)).lineLimit(2)
                }
                if !content.subtitle.isEmpty {
                    Text(content.subtitle).font(.system(size: 14 * s, weight: .medium)).lineLimit(1)
                }
                if !content.body.isEmpty {
                    Text(content.body).font(.system(size: 14 * s)).foregroundStyle(.primary.opacity(0.85)).lineLimit(4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var isGlass: Bool { look.background == .liquid || look.background == .liquidClear }

    /// notification color according to settings (nil = no color)
    private var tint: Color? {
        switch look.colorMode {
        case .none: nil
        case .app: content.appColor
        case .custom: look.customColor
        }
    }

    private var scheme: ColorScheme {
        switch look.theme {
        case .light: .light
        case .dark: .dark
        case .auto: NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
        }
    }
}

/// Timer bar: shrinks from right to left.
private struct TimerBar: View {
    @ObservedObject var countdown: Countdown
    let scale: Double
    let color: Color?
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.12))
                Capsule().fill(color.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.primary.opacity(0.5)))
                    .frame(width: max(0, g.size.width * countdown.progress))
            }
        }
        .frame(height: 4 * scale)
    }
}

/// Notification background: system Liquid Glass, frosted glass or solid.
private struct CardBackground: ViewModifier {
    let kind: NotificationBackground
    let radius: Double
    let scheme: ColorScheme
    let tint: Color?
    var intensity: Double = 0.35
    private var glassBoost: Double { intensity * 1.3 }

    @ViewBuilder func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        switch kind {
        case .liquid, .liquidClear:
            if #available(macOS 26.0, *) {
                // system Liquid Glass is colored with .tint, keeping the glass effect
                let glass: Glass = kind == .liquid ? .regular : .clear
                // a color layer inside the glass: the system .tint is nearly invisible here
                content.background(shape.fill(tint.map { $0.opacity(min(0.9, glassBoost)) } ?? .clear))
                    .glassEffect(glass, in: shape)
            } else {
                content.background { ZStack { shape.fill(.regularMaterial); shape.fill(tint ?? .clear) } }
            }
        case .blur:
            content.background { ZStack { shape.fill(.regularMaterial); shape.fill(tint ?? .clear) } }
                .overlay(shape.strokeBorder(.primary.opacity(0.08), lineWidth: 1))
        case .solid:
            content.background { ZStack {
                shape.fill(Color(nsColor: scheme == .dark ? NSColor(white: 0.16, alpha: 1) : NSColor(white: 0.98, alpha: 1)))
                shape.fill(tint ?? .clear)
            } }
                .overlay(shape.strokeBorder(.primary.opacity(0.08), lineWidth: 1))
        }
    }
}
