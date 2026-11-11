import Cocoa

/// A zone layout, like PowerToys FancyZones: rectangles (as proportions of the screen's usable area)
/// you can drop windows into. Templates generate their zones from a count; custom layouts store them.
struct ZoneLayout: Codable, Identifiable, Equatable {
    enum Kind: String, Codable, CaseIterable {
        case blank, focus, columns, rows, grid, priorityGrid // templates
        case customGrid, canvas                              // drawn by the user

        var isTemplate: Bool { self != .customGrid && self != .canvas }

        var templateName: String {
            switch self {
            case .blank: String(localized: "No layout")
            case .focus: String(localized: "Focus")
            case .columns: String(localized: "Columns")
            case .rows: String(localized: "Rows")
            case .grid: String(localized: "Grid")
            case .priorityGrid: String(localized: "Priority Grid")
            case .customGrid: String(localized: "Grid")
            case .canvas: String(localized: "Canvas")
            }
        }
    }

    var id: UUID
    var name: String
    var kind: Kind
    var zoneCount = 3            // templates
    var customZones: [CGRect] = [] // custom layouts, 0…1
    var showSpacing = false      // off: windows touch each other and the screen edges
    var spacing = 16             // points between zones (and around them), when on
    var sensitivity = 20         // highlight distance: near a border between two zones, both light up
    var hotkey: Int?             // custom layouts: ⌥⌃⌘ + number (0…9)

    var displayName: String { kind.isTemplate ? kind.templateName : name }

    /// Zones as proportions of the area (0…1), in order (their numbers are index + 1).
    var zones: [CGRect] {
        switch kind {
        case .customGrid, .canvas: return customZones
        case .blank: return []
        case .focus: return Self.focus(zoneCount)
        case .columns: return Self.split(zoneCount, vertical: false)
        case .rows: return Self.split(zoneCount, vertical: true)
        case .grid: return Self.grid(zoneCount)
        case .priorityGrid: return Self.priorityGrid(zoneCount)
        }
    }

    /// The zones on screen: `area` is the screen's usable area (CoreGraphics coordinates).
    /// With spacing, every zone keeps the same gap from its neighbors and from the screen edges.
    func frames(in area: CGRect) -> [CGRect] {
        let s = showSpacing ? CGFloat(spacing) : 0
        return zones.map { u in
            let x0 = (area.minX + u.minX * area.width).rounded(), x1 = (area.minX + u.maxX * area.width).rounded()
            let y0 = (area.minY + u.minY * area.height).rounded(), y1 = (area.minY + u.maxY * area.height).rounded()
            func inset(_ atEdge: Bool) -> CGFloat { atEdge ? s : (s / 2).rounded(.down) }
            let l = inset(u.minX < 0.001), r = inset(u.maxX > 0.999), t = inset(u.minY < 0.001), b = inset(u.maxY > 0.999)
            return CGRect(x: x0 + l, y: y0 + t, width: max(40, x1 - x0 - l - r), height: max(40, y1 - y0 - t - b))
        }
    }

    // MARK: Templates

    static let templateIDs: [Kind: UUID] = [
        .blank: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        .focus: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        .columns: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
        .rows: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
        .grid: UUID(uuidString: "00000000-0000-0000-0000-000000000005")!,
        .priorityGrid: UUID(uuidString: "00000000-0000-0000-0000-000000000006")!,
    ]

    static func template(_ kind: Kind) -> ZoneLayout {
        ZoneLayout(id: templateIDs[kind]!, name: kind.templateName, kind: kind, zoneCount: kind == .grid ? 4 : 3)
    }

    static let maxZones = 40

    private static func split(_ n: Int, vertical: Bool) -> [CGRect] {
        let n = max(1, n)
        return (0..<n).map { i in
            let a = CGFloat(i) / CGFloat(n), b = CGFloat(i + 1) / CGFloat(n)
            return vertical ? CGRect(x: 0, y: a, width: 1, height: b - a) : CGRect(x: a, y: 0, width: b - a, height: 1)
        }
    }

    /// Cells filling the screen: as square as possible, the last row with fewer, wider cells.
    private static func grid(_ n: Int) -> [CGRect] {
        let n = max(1, n)
        let cols = Int(CGFloat(n).squareRoot().rounded(.up))
        let rows = (n + cols - 1) / cols
        var out: [CGRect] = []
        for r in 0..<rows {
            let inRow = r == rows - 1 ? n - cols * (rows - 1) : cols
            let y0 = CGFloat(r) / CGFloat(rows), y1 = CGFloat(r + 1) / CGFloat(rows)
            for c in 0..<inRow {
                let x0 = CGFloat(c) / CGFloat(inRow), x1 = CGFloat(c + 1) / CGFloat(inRow)
                out.append(CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0))
            }
        }
        return out
    }

    /// A large zone in the middle with the others stacked at the sides.
    private static func priorityGrid(_ n: Int) -> [CGRect] {
        switch max(1, n) {
        case 1: return [CGRect(x: 0, y: 0, width: 1, height: 1)]
        case 2: return [CGRect(x: 0, y: 0, width: 2.0 / 3, height: 1), CGRect(x: 2.0 / 3, y: 0, width: 1.0 / 3, height: 1)]
        case let n:
            let side = n - 1, left = (side + 1) / 2, right = side - left
            // numbered from left to right, as they appear
            var out = (0..<left).map { CGRect(x: 0, y: CGFloat($0) / CGFloat(left), width: 0.25, height: 1 / CGFloat(left)) }
            out.append(CGRect(x: 0.25, y: 0, width: 0.5, height: 1))
            for i in 0..<right {
                out.append(CGRect(x: 0.75, y: CGFloat(i) / CGFloat(right), width: 0.25, height: 1 / CGFloat(right)))
            }
            return out
        }
    }

    /// Overlapping windows, slightly offset from each other.
    private static func focus(_ n: Int) -> [CGRect] {
        let n = max(1, n)
        let size: CGFloat = 0.6
        let step = n > 1 ? min(0.08, (1 - size) / CGFloat(n - 1)) : 0
        let start = (1 - size - step * CGFloat(n - 1)) / 2
        return (0..<n).map { i in
            CGRect(x: start + step * CGFloat(i), y: start + step * CGFloat(i), width: size, height: size)
        }
    }
}
