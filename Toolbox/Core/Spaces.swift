import Cocoa

// Private macOS APIs (the same ones used by the most popular switchers) for desktops (Spaces)
// and for bringing to the front a window that is on another desktop.
private typealias CGSConnectionID = UInt32
@_silgen_name("CGSMainConnectionID")
private func CGSMainConnectionID() -> CGSConnectionID
@_silgen_name("CGSCopyManagedDisplaySpaces")
private func CGSCopyManagedDisplaySpaces(_ cid: CGSConnectionID) -> CFArray
@_silgen_name("CGSCopyWindowsWithOptionsAndTags")
private func CGSCopyWindowsWithOptionsAndTags(_ cid: CGSConnectionID, _ owner: Int, _ spaces: CFArray, _ options: Int,
                                              _ setTags: UnsafeMutablePointer<Int>,
                                              _ clearTags: UnsafeMutablePointer<Int>) -> CFArray
@_silgen_name("GetProcessForPID")
private func toolboxGetProcessForPID(_ pid: pid_t, _ psn: UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus
@_silgen_name("_SLPSSetFrontProcessWithOptions")
private func _SLPSSetFrontProcessWithOptions(_ psn: UnsafeMutablePointer<ProcessSerialNumber>, _ wid: UInt32,
                                             _ mode: UInt32) -> CGError
@_silgen_name("SLPSPostEventRecordTo")
private func SLPSPostEventRecordTo(_ psn: UnsafeMutablePointer<ProcessSerialNumber>,
                                   _ bytes: UnsafeMutablePointer<UInt8>) -> CGError

enum Spaces {
    /// Windows on desktops other than the current one (on every monitor).
    static func windowsInOtherSpaces() -> [(id: CGWindowID, fullscreen: Bool)] {
        let cid = CGSMainConnectionID()
        guard let displays = CGSCopyManagedDisplaySpaces(cid) as? [[String: Any]] else { return [] }
        var result: [(CGWindowID, Bool)] = []
        for display in displays {
            let current = (display["Current Space"] as? [String: Any])?["ManagedSpaceID"] as? Int
            for space in display["Spaces"] as? [[String: Any]] ?? [] {
                guard let sid = space["ManagedSpaceID"] as? Int, sid != current else { continue }
                let fullscreen = (space["type"] as? Int) == 4 // 4 = full-screen app
                var set = 0, clear = 0
                let ids = CGSCopyWindowsWithOptionsAndTags(cid, 0, [sid] as CFArray, 2, &set, &clear) as? [Int] ?? []
                result += ids.map { (CGWindowID($0), fullscreen) }
            }
        }
        return result
    }

    /// Brings a window to the front even if it is on another desktop (macOS switches there on its own).
    static func focus(windowID: CGWindowID, pid: pid_t) {
        var psn = ProcessSerialNumber()
        guard toolboxGetProcessForPID(pid, &psn) == noErr else { return }
        _ = _SLPSSetFrontProcessWithOptions(&psn, windowID, 0x200) // 0x200 = "user-initiated"
        // makes the window "key": a synthetic event like the one the Window Server sends
        var bytes = [UInt8](repeating: 0, count: 0xf8)
        bytes[0x04] = 0xf8
        bytes[0x3a] = 0x10
        withUnsafeBytes(of: windowID) { for (i, b) in $0.enumerated() { bytes[0x3c + i] = b } }
        for i in 0x20..<0x30 { bytes[i] = 0xff }
        bytes[0x08] = 0x01
        _ = SLPSPostEventRecordTo(&psn, &bytes)
        bytes[0x08] = 0x02
        _ = SLPSPostEventRecordTo(&psn, &bytes)
    }
}
