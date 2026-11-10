/// Names of the preferences saved by Toolbox (UserDefaults, the app's domain).
/// Toolbox and Power.app share them. To add one: a constant here, then
/// `@AppStorage(Pref.name)` in the settings views and an accessor in `Settings` for the rest of the code.
enum Pref {
    // Switcher (⌘Tab)
    static let switcherModifier = "modifier"
    static let switcherKey = "key"
    static let previewWidth = "previewWidth"
    static let titleOnTop = "titleOnTop"
    static let showMinimized = "showMinimized"
    static let showOtherDesktops = "showOtherDesktops"
    static let backgroundPreviews = "backgroundPreviews"
    static let closeButtonQuitsApp = "closeButtonQuitsApp"

    // Window snapping
    static let snapEnabled = "snapEnabled"
    static let snapAssist = "snapAssist"
    static let snapLinkedResize = "snapLinkedResize"
    static let snapLayoutBar = "snapLayoutBar"
    static let snapNearEdge = "snapNearEdge"
    static let snapKeys = "snapKeys"
    static let macTilingBackup = "macTilingBackup"   // how macOS tiling was set up before Toolbox

    // Dock
    static let dockPreviews = "dockPreviews"
    static let dockPreviewWidth = "dockPreviewWidth"
    static let dockMinimize = "dockMinimize"
    static let dockMinimizeScope = "dockMinimizeScope"
    static let toolboxInDock = "toolboxInDock"
    static let toolboxDockLastApplied = "toolboxDockLastApplied"

    // Power (also read by Power.app)
    static let powerButton = "powerButton"
    static let powerConfirm = "powerConfirm"
    static let powerIconColor = "powerIconColor"
    static let powerShowLock = "powerShowLock"
    static let powerShowLogout = "powerShowLogout"
    static let powerShowSleep = "powerShowSleep"
    static let powerShowDisplayOff = "powerShowDisplayOff"
    static let powerShowRestart = "powerShowRestart"
    static let powerShowShutdown = "powerShowShutdown"
    static let powerShowTimer = "powerShowTimer"
    static let powerLastApplied = "powerLastApplied"
    static let powerWasPinned = "powerWasPinned"

    // Quitting apps
    static let quitOnLastWindow = "quitOnLastWindow"
    static let quitExclusions = "quitExclusions"

    // Finder
    static let finderKeys = "finderKeys"
    static let finderPrefsApplied = "finderPrefsApplied"
    static let finderBackupShowExtensions = "finderBackupShowExtensions"

    // Keyboard
    static let ctrlShortcuts = "ctrlShortcuts"
    static let textKeys = "textKeys"
    static let rightCommandAltGr = "rightCommandAltGr"
    static let screenSnip = "screenSnip"

    // Notifications
    static let notificationStyle = "notificationStyle"
    static let centerNotifications = "centerNotifications"
    static let notificationDropAnimation = "notificationDropAnimation"
    static let notifBackground = "notifBackground"
    static let notifColorIntensity = "notifColorIntensity"
    static let notifColorMode = "notifColorMode"
    static let notifCustomColor = "notifCustomColor"
    static let notifDuration = "notifDuration"
    static let notifRadius = "notifRadius"
    static let notifShowIcon = "notifShowIcon"
    static let notifShowTimer = "notifShowTimer"
    static let notifTestApp = "notifTestApp"
    static let notifTextScale = "notifTextScale"
    static let notifTheme = "notifTheme"
    static let notifWidth = "notifWidth"

    // Updates
    static let importantUpdateAlerts = "importantUpdateAlerts"
    static let autoInstallUpdates = "autoInstallUpdates"
    static let updatedFromVersion = "updatedFromVersion"
    static let lastUpdateCheck = "lastUpdateCheck"
    static let lastBackgroundUpdateCheck = "lastBackgroundUpdateCheck"
    static let notifiedUpdateVersion = "notifiedUpdateVersion"
    static let updateFeedOverride = "updateFeedOverride"

    // Internal app state
    static let settingsSection = "settingsSection"
    static let launchedBefore = "launchedBefore"
    static let lastCrashCheck = "lastCrashCheck"
    static let lastCrash = "lastCrash"
    static let reRegisterLogin = "reRegisterLogin"
}
