import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private let coordinator = Coordinator()
    private var statusBar: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar only — no Dock icon. (Also set via LSUIElement in Info.plist.)
        NSApp.setActivationPolicy(.accessory)

        statusBar = StatusBarController(coordinator: coordinator)

        // On first launch (or if permissions are missing), guide the user.
        if !Settings.shared.hasCompletedSetup || !PermissionsGuide.allGranted {
            DispatchQueue.main.async {
                PermissionsGuide.showSetupWizard()
                Settings.shared.hasCompletedSetup = true
            }
        }

        coordinator.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator.stop()
    }
}
