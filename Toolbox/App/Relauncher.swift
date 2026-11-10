import Cocoa

/// Quits Toolbox and runs `then` (shell commands) as soon as the process has actually exited.
/// Used to relaunch after an update or a language change, and to finish uninstalling.
enum Relauncher {
    static func quit(then script: String) {
        let pid = ProcessInfo.processInfo.processIdentifier
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; \(script)"]
        do { try p.run() } catch { Log.error("could not prepare to quit: \(error.localizedDescription)") }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { NSApp.terminate(nil) }
    }

    /// Reopens the given app (usually this one) after quitting.
    static func relaunch(_ app: URL = Bundle.main.bundleURL, background: Bool = false) {
        quit(then: "/usr/bin/open \(shellQuoted(app.path))" + (background ? " --args --background" : ""))
    }

    static func shellQuoted(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}
