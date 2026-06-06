import AppKit

/// Owns the menu-bar item and its menu.
final class StatusBarController {

    private let statusItem: NSStatusItem
    private let coordinator: Coordinator

    private let enabledItem = NSMenuItem(
        title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
    private let learningItem = NSMenuItem(
        title: "Learn from my typing", action: #selector(toggleLearning), keyEquivalent: "")

    init(coordinator: Coordinator) {
        self.coordinator = coordinator
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        configureButton()
        buildMenu()
    }

    private func configureButton() {
        if let button = statusItem.button {
            // SF Symbol if available, else a glyph fallback.
            if let image = NSImage(
                systemSymbolName: "sparkles", accessibilityDescription: "Glide") {
                button.image = image
            } else {
                button.title = "✦"
            }
        }
    }

    private func buildMenu() {
        let menu = NSMenu()

        enabledItem.target = self
        enabledItem.state = Settings.shared.isEnabled ? .on : .off
        menu.addItem(enabledItem)

        learningItem.target = self
        learningItem.state = Settings.shared.isLearningEnabled ? .on : .off
        menu.addItem(learningItem)

        menu.addItem(.separator())

        let permItem = NSMenuItem(
            title: "Check Permissions…",
            action: #selector(checkPermissions),
            keyEquivalent: "")
        permItem.target = self
        menu.addItem(permItem)

        let aboutItem = NSMenuItem(
            title: "About Glide", action: #selector(about), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit Glide", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func toggleEnabled() {
        let newValue = !Settings.shared.isEnabled
        Settings.shared.isEnabled = newValue
        enabledItem.state = newValue ? .on : .off
        coordinator.setEnabled(newValue)
    }

    @objc private func toggleLearning() {
        let newValue = !Settings.shared.isLearningEnabled
        Settings.shared.isLearningEnabled = newValue
        learningItem.state = newValue ? .on : .off
    }

    @objc private func checkPermissions() {
        let trusted = AccessibilityBridge.isTrusted(prompt: true)
        let alert = NSAlert()
        alert.messageText = trusted ? "Accessibility: granted" : "Accessibility: not granted"
        alert.informativeText = trusted
            ? "Glide can read text fields. If suggestions still don't appear, also enable Input Monitoring in System Settings → Privacy & Security."
            : "Enable Glide under System Settings → Privacy & Security → Accessibility, and also under Input Monitoring."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func about() {
        let alert = NSAlert()
        alert.messageText = "Glide"
        alert.informativeText = "Smart, private, on-device autocomplete for Mac.\nPress Tab to accept a suggestion, Esc to dismiss."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
