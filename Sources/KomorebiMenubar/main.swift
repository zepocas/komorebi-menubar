import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// Menubar-only: no Dock icon or app menu (LSUIElement in Info.plist does the same when bundled).
app.setActivationPolicy(.accessory)
app.run()
