import Cocoa
import SwiftUI

struct TestApp: Identifiable, Hashable {
    let name: String
    let path: String
    var id: String { path }
    var icon: NSImage { NSWorkspace.shared.icon(forFile: path) }

    /// All installed apps (system, main and per-user Applications folders), in alphabetical order.
    static let all: [TestApp] = {
        let dirs = ["/Applications", "/System/Applications", "/System/Applications/Utilities", NSHomeDirectory() + "/Applications"]
        var seen = Set<String>(), apps: [TestApp] = []
        for dir in dirs {
            for file in (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [] where file.hasSuffix(".app") {
                let path = "\(dir)/\(file)"
                let name = FileManager.default.displayName(atPath: path).replacingOccurrences(of: ".app", with: "")
                if seen.insert(name).inserted { apps.append(TestApp(name: name, path: path)) }
            }
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }()

    /// A believable sample message for the app.
    var sample: (title: String, body: String) {
        let n = name.lowercased()
        switch true {
        case n.contains("whatsapp"): return (String(localized: "Mom"), String(localized: "Have you eaten? Coming over for dinner tonight? 🍝"))
        case n.contains("telegram"): return ("Luca", String(localized: "I sent you the file, take a look when you can"))
        case n.contains("messag"): return ("Anna", String(localized: "See you at 8 in front of the cinema? 🎬"))
        case n.contains("mail"): return (String(localized: "November invoice"), String(localized: "Dear customer, please find this month's invoice attached."))
        case n.contains("calend"): return (String(localized: "Team meeting"), String(localized: "In 10 minutes · Meeting room 2"))
        case n.contains("discord"): return (String(localized: "#general"), String(localized: "Marco: anyone playing tonight?"))
        case n.contains("slack"): return (String(localized: "#project"), String(localized: "Giulia: I updated the presentation"))
        case n.contains("spotify"): return (String(localized: "Now playing"), String(localized: "New episode of your favorite podcast"))
        case n.contains("promemoria") || n.contains("reminders"): return (String(localized: "Reminders"), String(localized: "Buy milk 🥛"))
        default: return (name, String(localized: "This is a test notification from \(name)"))
        }
    }
}

// MARK: - "Notifications" settings page

struct NotificationsPage: View {
    @AppStorage(Pref.notificationStyle) private var style = NotificationStyleKind.toolbox.rawValue
    @AppStorage(Pref.centerNotifications) private var centerNotifications = true
    @AppStorage(Pref.notificationDropAnimation) private var notificationDropAnimation = true
    @AppStorage(Pref.notifWidth) private var width = 460.0
    @AppStorage(Pref.notifTextScale) private var textScale = 1.15
    @AppStorage(Pref.notifRadius) private var radius = 26.0
    @AppStorage(Pref.notifDuration) private var duration = 6.0
    @AppStorage(Pref.notifTheme) private var theme = NotificationTheme.auto.rawValue
    @AppStorage(Pref.notifBackground) private var background = NotificationBackground.defaultValue.rawValue
    @AppStorage(Pref.notifShowTimer) private var showTimer = true
    @AppStorage(Pref.notifColorMode) private var colorMode = NotificationColorMode.app.rawValue
    @AppStorage(Pref.notifCustomColor) private var customColorHex = "#3478F6"
    @AppStorage(Pref.notifColorIntensity) private var colorIntensity = 0.35
    @StateObject private var previewCountdown = Countdown(0.65)
    @AppStorage(Pref.notifShowIcon) private var showIcon = true

    @AppStorage(Pref.notifTestApp) private var testAppPath = TestApp.all.first { $0.name == "WhatsApp" }?.path ?? ""
    @State private var testTitle = ""
    @State private var testBody = ""
    private var testApp: TestApp? { TestApp.all.first { $0.path == testAppPath } ?? TestApp.all.first }

    private func showTest(count: Int) {
        guard let app = testApp else { return }
        let senders = [testTitle, "Giulia", "Paolo"]
        let bodies = [testBody, String(localized: "OK, talk later 👍"), String(localized: "Did you see the last message?")]
        for i in 0..<count {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.7) {
                NotificationPresenter.shared.show(
                    NotificationContent(id: UUID().uuidString, appName: app.name, title: senders[i], subtitle: "",
                                        body: bodies[i], icon: app.icon),
                    original: nil)
            }
        }
    }

    private static let sample = NotificationContent(
        id: "anteprima", appName: String(localized: "Messages"), title: "Anna",
        subtitle: "", body: String(localized: "See you at 8 in front of the cinema? 🎬"))

    private var look: NotificationLook {
        NotificationLook(width: width, textScale: textScale, radius: radius, duration: duration,
                         theme: NotificationTheme(rawValue: theme) ?? .auto,
                         background: NotificationBackground(rawValue: background) ?? .defaultValue,
                         showIcon: showIcon, showTimer: showTimer,
                         colorMode: NotificationColorMode(rawValue: colorMode) ?? .app,
                         customColor: Color(hex: customColorHex) ?? .blue, colorIntensity: colorIntensity)
    }

    var body: some View {
        Form {
            Section("Notification style") {
                Picker("Style", selection: $style) {
                    Text("Toolbox (customizable)").tag(NotificationStyleKind.toolbox.rawValue)
                    Text("macOS (moved only)").tag(NotificationStyleKind.system.rawValue)
                }
                .pickerStyle(.segmented)
                HStack {
                    Spacer()
                    Button("Send a real test notification") { NotificationMover.sendTest() }
                }
            }

            if style == NotificationStyleKind.toolbox.rawValue {
                Section("Preview") {
                    HStack {
                        Spacer()
                        NotificationCard(content: Self.sample, look: look, countdown: previewCountdown)
                            .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
                            .padding(.vertical, 8)
                        Spacer()
                    }
                }
                Section("Customize") {
                    slider(String(localized: "Width"), $width, 340...640, step: 10, value: "\(Int(width)) pt")
                    slider(String(localized: "Text size"), $textScale, 0.9...1.6, step: 0.05, value: "\(Int(textScale * 100))%")
                    slider(String(localized: "Rounded corners"), $radius, 8...36, step: 1, value: "\(Int(radius))")
                    slider(String(localized: "Stays visible for"), $duration, 3...20, step: 1, value: "\(Int(duration)) s")
                    Picker("Theme", selection: $theme) {
                        ForEach(NotificationTheme.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    Picker("Background", selection: $background) {
                        ForEach(NotificationBackground.available) { Text($0.label).tag($0.rawValue) }
                    }
                    Toggle("Timer bar (pauses while the pointer is over it)", isOn: $showTimer)
                }
                Section("Color") {
                    Picker("Tint the notification", selection: $colorMode) {
                        ForEach(NotificationColorMode.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    if colorMode == NotificationColorMode.custom.rawValue {
                        ColorPicker("Color", selection: Binding(
                            get: { Color(hex: customColorHex) ?? .blue },
                            set: { customColorHex = $0.hex }), supportsOpacity: false)
                    }
                    if colorMode != NotificationColorMode.none.rawValue {
                        slider(String(localized: "Intensity"), $colorIntensity, 0.1...0.8, step: 0.05, value: "\(Int(colorIntensity * 100))%")
                    }
                    if colorMode == NotificationColorMode.app.rawValue {
                        Text("The color is taken from the app's icon (e.g. green for Messages, blue for Mail). Apps with a gray icon stay uncolored. The timer bar takes the same color too.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Toggle("Show the app icon", isOn: $showIcon)
                    HStack {
                        Spacer()
                        Button("Reset") {
                            width = 460; textScale = 1.15; radius = 26; duration = 6
                            theme = NotificationTheme.auto.rawValue
                            background = NotificationBackground.defaultValue.rawValue; showIcon = true; showTimer = true
                            colorMode = NotificationColorMode.app.rawValue; colorIntensity = 0.35
                        }
                    }
                }
                Section("Test mode") {
                    Picker("App", selection: $testAppPath) {
                        ForEach(TestApp.all) { app in
                            Label { Text(app.name) } icon: { Image(nsImage: app.icon) }.tag(app.path)
                        }
                    }
                    .onChange(of: testAppPath, initial: true) { _, _ in
                        if let app = testApp { testTitle = app.sample.title; testBody = app.sample.body }
                    }
                    TextField("Title", text: $testTitle)
                    TextField("Message", text: $testBody)
                    HStack {
                        Spacer()
                        Button("Show 3 in a row") { showTest(count: 3) }
                        Button("Show notification") { showTest(count: 1) }.keyboardShortcut(.defaultAction)
                    }
                    Text("The notification is simulated by Toolbox with the chosen app's icon, name and color: macOS doesn't allow sending a real one on behalf of another app. The button at the top, on the other hand, sends a real notification through macOS.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Section {
                    Text("Notifications slide down at the top center and stack one below the other. Click to open them; hover over them to keep them in place and to show the ✕ that closes them.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            } else {
                Section("macOS notifications") {
                    Toggle("Show notifications at the top center", isOn: $centerNotifications)
                    Toggle("Slide them down from the top", isOn: $notificationDropAnimation)
                        .disabled(!centerNotifications)
                    Text("Notifications stay the macOS ones, moved to the top center.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func slider(_ label: String, _ binding: Binding<Double>, _ range: ClosedRange<Double>, step: Double,
                        value: String) -> some View {
        LabeledContent(label) {
            HStack {
                Slider(value: binding, in: range, step: step)
                Text(value).monospacedDigit().foregroundStyle(.secondary).frame(width: 56, alignment: .trailing)
            }
        }
    }
}
