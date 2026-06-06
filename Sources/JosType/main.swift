import AppKit

// Entry point. We build the app and delegate programmatically (no storyboard).
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
