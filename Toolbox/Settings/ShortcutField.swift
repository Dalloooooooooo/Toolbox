import Cocoa
import SwiftUI

/// While a shortcut is being recorded Toolbox's own keys and gestures stand aside,
/// so pressing the current shortcut records it instead of running it.
enum ShortcutRecording {
    static var active = false
}

/// "Click, then press": click the field, then press the key, the modifiers or the mouse button to use.
/// Esc cancels; the arrow brings back the default.
struct ShortcutField: View {
    let pref: String
    let defaultValue: Shortcut
    var mode: Shortcut.Mode = .press
    var onChange: () -> Void = {}

    @State private var value: Shortcut
    @State private var recording = false
    @State private var monitor: Any?
    @State private var held = Shortcut()

    init(pref: String, default d: Shortcut, mode: Shortcut.Mode = .press, onChange: @escaping () -> Void = {}) {
        self.pref = pref
        defaultValue = d
        self.mode = mode
        self.onChange = onChange
        _value = State(initialValue: Shortcut.load(pref, default: d))
    }

    var body: some View {
        HStack(spacing: 4) {
            Button { recording ? stop() : start() } label: {
                Text(recording ? (mode == .hold ? String(localized: "Hold the keys or button…") : String(localized: "Press the shortcut…"))
                               : value.display)
                    .frame(minWidth: 120)
                    .foregroundStyle(recording ? Color.accentColor : .primary)
            }
            .buttonStyle(.bordered)
            .help(String(localized: "Click, then press the key or mouse button to use. Esc cancels."))
            if value != defaultValue && !recording {
                Button { set(defaultValue) } label: { Image(systemName: "arrow.uturn.backward") }
                    .buttonStyle(.borderless)
                    .help(String(localized: "Back to \(defaultValue.display)"))
            }
        }
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        held = Shortcut()
        ShortcutRecording.active = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged, .otherMouseDown, .rightMouseDown]) { e in
            handle(e)
            return nil // the keys being recorded don't reach the app
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
        ShortcutRecording.active = false
    }

    private func set(_ s: Shortcut) {
        value = s
        s.save(pref)
        onChange()
    }

    private func handle(_ e: NSEvent) {
        let flags = CGEventFlags(rawValue: UInt64(e.modifierFlags.rawValue))
        var s = Shortcut.modifiers(flags)
        switch e.type {
        case .keyDown:
            if e.keyCode == 53, !s.hasModifiers { stop(); return } // Esc: cancel
            // a key that types something needs ⌃, ⌥ or ⌘, otherwise you couldn't type it any more
            guard mode == .press, Shortcut.isNonTyping(Int(e.keyCode)) || s.control || s.option != .none || s.command != .none else {
                NSSound.beep(); return
            }
            s.keyCode = Int(e.keyCode)
            set(s); stop()
        case .flagsChanged:
            guard mode == .hold else { return }
            if s.hasModifiers {
                // the combination grows while keys are added; it's recorded when they're all released
                held.shift = held.shift || s.shift
                held.control = held.control || s.control
                if s.option != .none { held.option = s.option }
                if s.command != .none { held.command = s.command }
            } else if held.hasModifiers {
                set(held); stop()
            }
        case .otherMouseDown, .rightMouseDown:
            // right click only with a modifier, or every context menu would stop working
            guard e.buttonNumber >= 2 || s.hasModifiers else { NSSound.beep(); return }
            s.mouseButton = e.buttonNumber
            set(s); stop()
        default: break
        }
    }
}
