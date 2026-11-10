import Cocoa
import SwiftUI

@MainActor
final class DockPreviewModel: ObservableObject {
    @Published var bundleID: String?
    @Published var appName = ""
    @Published var windows: [WindowInfo] = []
    @Published var images: [CGWindowID: NSImage] = [:]
    @Published var tileWidth: Double = 240
}

struct DockPreviewView: View {
    @ObservedObject var model: DockPreviewModel

    var body: some View {
        HStack(spacing: 10) {
            ForEach(model.windows.prefix(Self.visibleCount(model.windows.count, tileWidth: model.tileWidth)), id: \.id) { w in
                Tile(window: w, image: model.images[w.id], width: model.tileWidth)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { PanelBackground() }
    }

    /// How many previews fit in the screen width.
    static func visibleCount(_ n: Int, tileWidth: Double) -> Int {
        let fit = Int(((NSScreen.main?.frame.width ?? 1600) - 40) / (tileWidth + 26))
        return max(1, min(n, fit))
    }
}

private struct PanelBackground: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        if #available(macOS 26.0, *) {
            Color.clear.glassEffect(.regular, in: shape)
        } else {
            shape.fill(.regularMaterial).overlay(shape.strokeBorder(.primary.opacity(0.1), lineWidth: 1))
        }
    }
}

private struct Tile: View {
    let window: WindowInfo
    let image: NSImage?
    let width: Double
    @State private var hover = false
    @State private var hoverX = false

    private var badge: String? {
        switch window.state {
        case .minimized: String(localized: "Minimized")
        case .hidden: String(localized: "Hidden")
        case .otherDesktop: String(localized: "Other desktop")
        case .fullscreen: String(localized: "Full screen")
        case .normal: nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if let icon = window.icon { Image(nsImage: icon).resizable().frame(width: 16, height: 16) }
                Text(window.title).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.tail)
                    .frame(height: 20)
                Spacer(minLength: 4)
                Button { DockPreview.close(window) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(hoverX ? .white : .secondary)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(hoverX ? Color.red : Color.primary.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .onHover { hoverX = $0 }
                .opacity(hover ? 1 : 0)
                .help("Close window")
            }
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06))
                if let image {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .opacity(window.state == .normal ? 1 : 0.75)
                } else if let icon = window.icon {
                    Image(nsImage: icon).resizable().frame(width: 56, height: 56).opacity(0.8)
                }
                if let badge {
                    VStack {
                        Spacer()
                        Text(badge).font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Capsule().fill(.black.opacity(0.55))).foregroundStyle(.white)
                            .padding(6)
                    }
                }
            }
            .frame(width: width, height: width * 0.62)
        }
        .padding(8)
        .frame(width: width + 16)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(hover ? 0.12 : 0)))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture { DockPreview.focus(window) }
    }
}
