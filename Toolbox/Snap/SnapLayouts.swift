import Cocoa

/// A zone as a proportion of the screen's usable area (0…1).
struct SnapZone: Equatable {
    let unit: CGRect

    static let maximize = SnapZone(unit: CGRect(x: 0, y: 0, width: 1, height: 1))
    static let left = SnapZone(unit: CGRect(x: 0, y: 0, width: 0.5, height: 1))
    static let right = SnapZone(unit: CGRect(x: 0.5, y: 0, width: 0.5, height: 1))
    static let topLeft = SnapZone(unit: CGRect(x: 0, y: 0, width: 0.5, height: 0.5))
    static let topRight = SnapZone(unit: CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5))
    static let bottomLeft = SnapZone(unit: CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5))
    static let bottomRight = SnapZone(unit: CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5))

    static func == (a: SnapZone, b: SnapZone) -> Bool {
        abs(a.unit.minX - b.unit.minX) < 0.01 && abs(a.unit.minY - b.unit.minY) < 0.01 &&
        abs(a.unit.width - b.unit.width) < 0.01 && abs(a.unit.height - b.unit.height) < 0.01
    }

    func frame(in r: CGRect) -> CGRect {
        let x0 = r.minX + (unit.minX * r.width).rounded(), x1 = r.minX + (unit.maxX * r.width).rounded()
        let y0 = r.minY + (unit.minY * r.height).rounded(), y1 = r.minY + (unit.maxY * r.height).rounded()
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    var label: String {
        let a = unit.width * unit.height
        func near(_ v: CGFloat) -> Bool { abs(a - v) < 0.02 }
        if near(1) { return String(localized: "the whole screen") }
        if near(0.5) { return String(localized: "this half") }
        if near(0.25) { return String(localized: "this quarter") }
        if near(1.0 / 3) { return String(localized: "this third") }
        if near(2.0 / 3) { return String(localized: "these two thirds") }
        return String(localized: "this space")
    }
}

/// The Windows 11 layouts (top bar and ⌥Z). On vertical screens the zones are stacked on top of each other.
struct SnapLayout {
    let zones: [SnapZone]

    private static func z(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> SnapZone {
        SnapZone(unit: CGRect(x: x, y: y, width: w, height: h))
    }
    static let halves = SnapLayout(zones: [.left, .right])
    static let quarters = SnapLayout(zones: [.topLeft, .topRight, .bottomLeft, .bottomRight])

    static func all(for area: CGRect) -> [SnapLayout] {
        let t: CGFloat = 1.0 / 3
        if area.height > area.width { // vertical monitor
            return [
                SnapLayout(zones: [z(0, 0, 1, 0.5), z(0, 0.5, 1, 0.5)]),
                SnapLayout(zones: [z(0, 0, 1, t), z(0, t, 1, t), z(0, 2 * t, 1, t)]),
                SnapLayout(zones: [z(0, 0, 1, 2 * t), z(0, 2 * t, 1, t)]),
                quarters,
            ]
        }
        var list = [
            halves,
            SnapLayout(zones: [z(0, 0, 2 * t, 1), z(2 * t, 0, t, 1)]),
            SnapLayout(zones: [.left, .topRight, .bottomRight]),
            quarters,
            SnapLayout(zones: [z(0, 0, t, 1), z(t, 0, t, 1), z(2 * t, 0, t, 1)]),
        ]
        if area.width / area.height >= 2.1 { // ultrawide
            list.append(SnapLayout(zones: [z(0, 0, 0.25, 1), z(0.25, 0, 0.5, 1), z(0.75, 0, 0.25, 1)]))
        }
        return list
    }
}
