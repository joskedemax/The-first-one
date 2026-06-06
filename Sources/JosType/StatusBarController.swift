import AppKit

@MainActor
final class StatusBarController {

    private let statusItem: NSStatusItem
    private let coordinator: Coordinator

    private let enabledItem = NSMenuItem(
        title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
    private let learningItem = NSMenuItem(
        title: "Learn from my typing", action: #selector(toggleLearning), keyEquivalent: "")
    private let modelStatusItem = NSMenuItem(title: "Model: loading…", action: nil, keyEquivalent: "")

    private var modelMenuItems: [NSMenuItem] = []

    init(coordinator: Coordinator) {
        self.coordinator = coordinator
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        configureButton()
        buildMenu()
    }

    private func configureButton() {
        if let button = statusItem.button {
            if let image = NSImage(
                systemSymbolName: "sparkles", accessibilityDescription: "JosType") {
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

        // Model status
        modelStatusItem.isEnabled = false
        menu.addItem(modelStatusItem)
        updateModelStatus()

        // Model selection submenu
        let modelMenu = NSMenu()
        for model in JosTypeModel.allCases {
            let item = NSMenuItem(
                title: model.rawValue,
                action: #selector(selectModel(_:)),
                keyEquivalent: "")
            item.target = self
            item.representedObject = model
            if model == Settings.shared.selectedModel {
                item.state = .on
            }
            modelMenu.addItem(item)
            modelMenuItems.append(item)
        }
        let modelItem = NSMenuItem(title: "Model", action: nil, keyEquivalent: "")
        modelItem.submenu = modelMenu
        menu.addItem(modelItem)

        menu.addItem(.separator())

        let voiceItem = NSMenuItem(
            title: "Voice Trigger: \(Settings.shared.voiceTrigger)",
            action: #selector(changeVoiceTrigger),
            keyEquivalent: "")
        voiceItem.target = self
        menu.addItem(voiceItem)

        menu.addItem(.separator())

        let permItem = NSMenuItem(
            title: "Check Permissions…",
            action: #selector(checkPermissions),
            keyEquivalent: "")
        permItem.target = self
        menu.addItem(permItem)

        let aboutItem = NSMenuItem(
            title: "About JosType", action: #selector(about), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit JosType", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    func updateModelStatus() {
        switch coordinator.modelStatus {
        case .idle:
            modelStatusItem.title = "Model: not loaded"
        case .downloading(let progress):
            modelStatusItem.title = "Model: downloading \(Int(progress * 100))%…"
        case .loading:
            modelStatusItem.title = "Model: loading…"
        case .ready:
            modelStatusItem.title = "Model: \(Settings.shared.selectedModel.rawValue) ✓"
        case .failed(let msg):
            modelStatusItem.title = "Model: failed — \(msg)"
        }
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

    @objc private func selectModel(_ sender: NSMenuItem) {
        guard let model = sender.representedObject as? JosTypeModel else { return }
        for item in modelMenuItems { item.state = .off }
        sender.state = .on
        coordinator.switchModel(model)
        updateModelStatus()
    }

    @objc private func checkPermissions() {
        PermissionsGuide.showSetupWizard()
    }

    @objc private func about() {
        let alert = NSAlert()
        alert.messageText = "JosType"
        alert.informativeText = """
        Smart, private, on-device autocomplete for Mac.
        Powered by Gemma — runs entirely on your machine.

        Tab → accept next word
        ` (backtick) → accept entire suggestion
        Right Arrow → accept entire suggestion
        Esc → dismiss
        \(Settings.shared.voiceTrigger) → voice-to-text input
        """
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func changeVoiceTrigger() {
        let alert = NSAlert()
        alert.messageText = "Voice Trigger Phrase"
        alert.informativeText = "Type this phrase in any text field to activate voice-to-text."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        input.stringValue = Settings.shared.voiceTrigger
        alert.accessoryView = input

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let newTrigger = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !newTrigger.isEmpty {
                Settings.shared.voiceTrigger = newTrigger
                buildMenu()
            }
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
