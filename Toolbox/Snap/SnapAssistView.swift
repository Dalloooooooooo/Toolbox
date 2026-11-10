import Cocoa
import SwiftUI

/// Thumbnail layout: as many columns as needed to make the thumbnails as large as possible.
/// A single window fills almost the whole space, two windows split it, and so on.
struct AssistGrid {
    let columns: Int
    let tile: CGSize
    let scroll: Bool

    static let spacing: CGFloat = 18
    static let minWidth: CGFloat = 170

    /// Thumbnail height for a given width: 16:10 preview + title row + margins.
    static func height(for w: CGFloat) -> CGFloat { w * 0.625 + titleHeight(w) + 26 }
    static func titleHeight(_ w: CGFloat) -> CGFloat { min(max(w * 0.06, 18), 34) }

    /// Space for the grid inside the panel: minus the padding and the two header lines of SnapAssistView.
    static func gridSize(panel: CGSize) -> CGSize {
        CGSize(width: max(0, panel.width - 44), height: max(0, panel.height - 44 - 56))
    }

    /// Size of the preview image inside a tile (the tile minus its title row and padding).
    static func previewSize(count n: Int, panel: CGSize) -> CGSize {
        let tile = best(count: n, in: gridSize(panel: panel)).tile
        let w = max(1, tile.width - 18)
        return CGSize(width: w, height: max(1, tile.height - titleHeight(tile.width) - 26))
    }

    static func best(count n: Int, in size: CGSize) -> AssistGrid {
        guard n > 0, size.width > 0, size.height > 0 else { return AssistGrid(columns: 1, tile: .zero, scroll: false) }
        let s = spacing
        var bestW: CGFloat = 0, bestC = 1
        for c in 1...n {
            let rows = CGFloat((n + c - 1) / c)
            let byWidth = (size.width - s * CGFloat(c - 1)) / CGFloat(c)
            let rowH = (size.height - s * (rows - 1)) / rows
            let byHeight = (rowH - 34 - 26) / 0.625 // inverse of height(for:), conservative estimate
            let w = min(byWidth, byHeight, size.width * 0.92)
            if w > bestW { bestW = w; bestC = c }
        }
        if bestW >= minWidth {
            return AssistGrid(columns: bestC, tile: CGSize(width: bestW, height: height(for: bestW)), scroll: false)
        }
        let c = max(1, Int((size.width + s) / (minWidth + s))) // too many windows: minimum size, scrolling
        return AssistGrid(columns: c, tile: CGSize(width: minWidth, height: height(for: minWidth)), scroll: true)
    }
}

struct SnapAssistView: View {
    @ObservedObject var model: SnapAssist

    var body: some View {
        VStack(spacing: 4) {
            Text("Choose a window for \(model.zoneLabel)").font(.headline)
            Text("Click elsewhere or press Esc to leave the space empty")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.bottom, 12)
            GeometryReader { geo in
                let grid = AssistGrid.best(count: model.candidates.count, in: geo.size)
                if grid.scroll {
                    ScrollView { tiles(grid).frame(maxWidth: .infinity) }
                } else {
                    tiles(grid).frame(width: geo.size.width, height: geo.size.height) // centered
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { // click on the background, outside the thumbnails: the space stays empty
            Button(action: model.dismiss) { Color.clear.contentShape(Rectangle()) }.buttonStyle(.plain)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.15)))
    }

    private func tiles(_ grid: AssistGrid) -> some View {
        let items = Array(model.candidates.enumerated())
        let rows = stride(from: 0, to: items.count, by: grid.columns).map {
            Array(items[$0..<min($0 + grid.columns, items.count)])
        }
        return VStack(spacing: AssistGrid.spacing) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: AssistGrid.spacing) { // the last row, if incomplete, stays centered
                    ForEach(rows[r], id: \.element.id) { i, c in
                        Button { model.choose(c) } label: {
                            SnapTile(info: c.info, preview: model.previews[c.id], selected: model.selected == i,
                                     width: grid.tile.width)
                                .frame(width: grid.tile.width, height: grid.tile.height)
                        }
                        .buttonStyle(.plain)
                        .overlay(alignment: .topTrailing) {
                            if model.selected == i {
                                Button { model.close(c) } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 11, weight: .bold))
                                        .frame(width: 24, height: 24)
                                        .background(Circle().fill(Color.red.opacity(0.9)))
                                        .foregroundStyle(.white)
                                }
                                .buttonStyle(.plain)
                                .help("Close this window")
                                .padding(6)
                            }
                        }
                        .onHover { if $0, model.selected != i { model.selected = i } }
                    }
                }
            }
        }
    }
}

private struct SnapTile: View {
    let info: WindowInfo
    let preview: NSImage?
    let selected: Bool
    let width: CGFloat

    var body: some View {
        let font = min(max(width * 0.035, 11), 20)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let icon = info.icon { Image(nsImage: icon).resizable().frame(width: font * 1.5, height: font * 1.5) }
                Text(info.title).font(.system(size: font, weight: .medium)).lineLimit(1)
                if info.state == .minimized {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                        .font(.system(size: font * 0.8)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 28) // room for the X
            }
            .frame(height: AssistGrid.titleHeight(width))
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.15))
                if let preview {
                    Image(nsImage: preview).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                } else if let icon = info.icon {
                    Image(nsImage: icon).resizable().frame(width: width * 0.22, height: width * 0.22).opacity(0.85)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(0.25), radius: selected ? 10 : 4, y: 2)
        }
        .padding(9)
        .background(RoundedRectangle(cornerRadius: 12).fill(selected ? Color.accentColor.opacity(0.22) : .white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2.5))
        .animation(.easeOut(duration: 0.12), value: selected)
        .contentShape(Rectangle())
    }
}
