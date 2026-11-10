import Cocoa
import Combine
import Quartz

let app = NSApplication.shared
let delegate = ExplorerApp.shared
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
