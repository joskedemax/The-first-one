import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private let coordinator = Coordinator()
    private var statusBar: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar only — no Dock icon. (Also set via LSUIElement in Info.plist.)
        NSApp.setActivationPolicy(.accessory)

        statusBar = StatusBarController(coordinator: coordinator)

        // Prompt for Accessibility up front so the user knows what's needed.
        if !AccessibilityBridge.isTrusted(prompt: true) {
            NSLog("JosType: waiting for Accessibility permission.")
        }

        coordinator.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator.stop()
    }
}
