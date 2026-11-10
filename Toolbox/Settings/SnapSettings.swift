import Cocoa

enum SnapSettings {
    private static let d = UserDefaults.standard
    private static func flag(_ k: String) -> Bool { d.object(forKey: k) as? Bool ?? true }
    static var enabled: Bool { flag(Pref.snapEnabled) }
    static var assist: Bool { flag(Pref.snapAssist) }
    static var linkedResize: Bool { flag(Pref.snapLinkedResize) }
    static var layoutBar: Bool { flag(Pref.snapLayoutBar) }
    static var nearEdge: Bool { flag(Pref.snapNearEdge) }
    static var keys: Bool { flag(Pref.snapKeys) }
    static var greenButton: Bool { flag(Pref.greenButtonMaximizes) }
    static var animate: Bool { flag(Pref.snapAnimate) }
}
