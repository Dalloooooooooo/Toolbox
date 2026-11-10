import Cocoa

/// ⌥Z (Win+Z): the layouts next to the active window. Click, arrows + Return, or layout number then zone number.
final class LayoutFlyout {
    static let shared = LayoutFlyout()
    private let picker = LayoutPicker(style: .flyout)
    private var chosen: ((SnapLayout, Int) -> Void)?
    private var pendingLayout: Int?
    private var area: CGRect = .zero

    var isVisible: Bool { picker.isVisible }

    func show(near f: CGRect, area: CGRect, choose: @escaping (SnapLayout, Int) -> Void) {
        chosen = choose
        pendingLayout = nil
        self.area = area
        let layouts = SnapLayout.all(for: area)
        picker.onChoose = { [weak self] l, z in self?.pick(l, z) }
        picker.show(layouts: layouts, area: area) { size in
            // at the top right of the window, where Windows has the Maximize button
            let x = min(max(f.maxX - size.width - 8, area.minX + 8), area.maxX - size.width - 8)
            let y = min(max(f.minY + 34, area.minY + 8), area.maxY - size.height - 8)
            return CGPoint(x: x, y: y)
        }
    }

    private func pick(_ l: Int, _ z: Int) {
        let layouts = picker.layouts
        dismiss()
        guard l < layouts.count, z < layouts[l].zones.count else { return }
        chosen?(layouts[l], z)
    }

    func dismiss() { picker.hide(); pendingLayout = nil }

    func mouseDown(at p: CGPoint) {
        guard isVisible, !picker.contains(p) else { return }
        DispatchQueue.main.async { self.dismiss() }
    }

    /// Keys while it is open. Returns true if the key was used.
    func handleKey(_ key: Int64) -> Bool {
        guard isVisible else { return false }
        let digits: [Int64: Int] = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9]
        let handled = [53, 123, 124, 125, 126, 48, 36, 76].contains(key) || digits[key] != nil
        DispatchQueue.main.async {
            switch key {
            case 53: self.dismiss()
            case 123, 126: self.stepHighlight(-1)
            case 124, 125, 48: self.stepHighlight(1)
            case 36, 76: if let h = self.picker.highlight { self.pick(h.0, h.1) }
            default:
                guard let n = digits[key] else { self.dismiss(); return }
                if let l = self.pendingLayout { self.pick(l, n - 1) }
                else if n - 1 < self.picker.layouts.count { self.pendingLayout = n - 1; self.picker.highlight = (n - 1, 0) }
            }
        }
        return handled
    }

    private func stepHighlight(_ d: Int) {
        // LayoutPicker doesn't expose its view: go through the highlighted zone
        let layouts = picker.layouts
        let flat = layouts.indices.flatMap { l in layouts[l].zones.indices.map { (l, $0) } }
        guard !flat.isEmpty else { return }
        let cur = picker.highlight.flatMap { h in flat.firstIndex { $0 == h } } ?? (d > 0 ? -1 : 0)
        picker.highlight = flat[(cur + d + flat.count) % flat.count]
    }
}
