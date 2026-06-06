import AppKit
import Speech
import AVFoundation

@MainActor
enum PermissionsGuide {

    struct Status {
        let accessibility: Bool
        let inputMonitoring: Bool
        let microphone: AVAuthorizationStatus
        let speechRecognition: SFSpeechRecognizerAuthorizationStatus
    }

    static func check() -> Status {
        Status(
            accessibility: AccessibilityBridge.isTrusted(prompt: false),
            inputMonitoring: checkInputMonitoring(),
            microphone: AVCaptureDevice.authorizationStatus(for: .audio),
            speechRecognition: SFSpeechRecognizer.authorizationStatus()
        )
    }

    static var allGranted: Bool {
        let s = check()
        return s.accessibility && s.inputMonitoring
            && s.microphone == .authorized
            && s.speechRecognition == .authorized
    }

    static func showSetupWizard() {
        let status = check()
        if status.accessibility && status.inputMonitoring
            && status.microphone == .authorized
            && status.speechRecognition == .authorized {
            showAllGoodAlert()
            return
        }
        showStepByStep(status)
    }

    static func runStartupCheck() {
        let status = check()
        let missing = !status.accessibility || !status.inputMonitoring
        if missing {
            showStepByStep(status)
        }
    }

    // MARK: - Step-by-step wizard

    private static func showStepByStep(_ status: Status) {
        // Step 1: Accessibility
        if !status.accessibility {
            let proceed = showPermissionStep(
                step: 1,
                title: "Accessibility Permission Required",
                message: """
                JosType needs Accessibility access to read text fields \
                and insert suggestions across all apps.

                Click "Open Settings" to go to:
                System Settings → Privacy & Security → Accessibility

                Find JosType in the list and toggle it ON.
                If JosType isn't listed, click the + button to add it.
                """,
                buttonTitle: "Open Settings",
                settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
            )
            if !proceed { return }
            waitForPermission(message: "Waiting for Accessibility permission...\nToggle JosType ON in System Settings, then click Continue.") {
                AccessibilityBridge.isTrusted(prompt: false)
            }
        }

        // Step 2: Input Monitoring
        if !status.inputMonitoring {
            let proceed = showPermissionStep(
                step: 2,
                title: "Input Monitoring Permission Required",
                message: """
                JosType needs Input Monitoring to detect Tab, Backtick, \
                and Escape keys for accepting/dismissing suggestions.

                Click "Open Settings" to go to:
                System Settings → Privacy & Security → Input Monitoring

                Find JosType and toggle it ON.
                If it's not listed, you may need to restart JosType after \
                granting Accessibility.
                """,
                buttonTitle: "Open Settings",
                settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
            )
            if !proceed { return }
        }

        // Step 3: Microphone (for ,,talk)
        if status.microphone != .authorized {
            let proceed = showPermissionStep(
                step: 3,
                title: "Microphone Permission (for Voice Input)",
                message: """
                JosType can transcribe your speech when you type ",,talk" \
                in any text field. This requires microphone access.

                Click "Grant Access" and approve the system dialog.
                You can also grant this later in:
                System Settings → Privacy & Security → Microphone
                """,
                buttonTitle: "Grant Access",
                action: {
                    AVCaptureDevice.requestAccess(for: .audio) { _ in }
                }
            )
            if !proceed { return }
        }

        // Step 4: Speech Recognition (for ,,talk)
        if status.speechRecognition != .authorized {
            let proceed = showPermissionStep(
                step: 4,
                title: "Speech Recognition Permission (for Voice Input)",
                message: """
                JosType uses Apple's speech recognition to transcribe \
                your voice into text. This requires Speech Recognition access.

                Click "Grant Access" and approve the system dialog.
                You can also grant this later in:
                System Settings → Privacy & Security → Speech Recognition
                """,
                buttonTitle: "Grant Access",
                action: {
                    SFSpeechRecognizer.requestAuthorization { _ in }
                }
            )
            if !proceed { return }
        }

        // Final status
        let final_ = check()
        showFinalStatus(final_)
    }

    // MARK: - Alert helpers

    private static func showPermissionStep(
        step: Int,
        title: String,
        message: String,
        buttonTitle: String,
        settingsURL: String
    ) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Step \(step): \(title)"
        alert.informativeText = message
        alert.addButton(withTitle: buttonTitle)
        alert.addButton(withTitle: "Skip")
        alert.addButton(withTitle: "Cancel Setup")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let url = URL(string: settingsURL) {
                NSWorkspace.shared.open(url)
            }
            return true
        } else if response == .alertThirdButtonReturn {
            return false
        }
        return true
    }

    private static func showPermissionStep(
        step: Int,
        title: String,
        message: String,
        buttonTitle: String,
        action: @escaping () -> Void
    ) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Step \(step): \(title)"
        alert.informativeText = message
        alert.addButton(withTitle: buttonTitle)
        alert.addButton(withTitle: "Skip")
        alert.addButton(withTitle: "Cancel Setup")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            action()
            return true
        } else if response == .alertThirdButtonReturn {
            return false
        }
        return true
    }

    private static func waitForPermission(message: String, check: @escaping () -> Bool) {
        guard !check() else { return }
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Waiting for Permission"
        alert.informativeText = message
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Skip")
        alert.runModal()
    }

    private static func showAllGoodAlert() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "All Permissions Granted"
        alert.informativeText = """
        ✓ Accessibility — granted
        ✓ Input Monitoring — granted
        ✓ Microphone — granted
        ✓ Speech Recognition — granted

        JosType is fully set up and ready to use!

        Shortcuts:
        • Tab — accept next word
        • ` (backtick) — accept entire suggestion
        • Esc — dismiss suggestion
        • ,,talk — voice-to-text input
        """
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private static func showFinalStatus(_ status: Status) {
        let items = [
            ("Accessibility", status.accessibility),
            ("Input Monitoring", status.inputMonitoring),
            ("Microphone", status.microphone == .authorized),
            ("Speech Recognition", status.speechRecognition == .authorized),
        ]
        let lines = items.map { name, ok in
            ok ? "✓ \(name) — granted" : "✗ \(name) — not granted"
        }
        let allOK = items.allSatisfy(\.1)

        let alert = NSAlert()
        alert.alertStyle = allOK ? .informational : .warning
        alert.messageText = allOK ? "Setup Complete" : "Setup Incomplete"
        alert.informativeText = lines.joined(separator: "\n") + "\n\n"
            + (allOK
               ? "JosType is fully set up and ready to use!"
               : "Some permissions are missing. JosType will work with reduced functionality. You can re-run this setup from the menu bar at any time.")
        if allOK {
            alert.informativeText += """

            Shortcuts:
            • Tab — accept next word
            • ` (backtick) — accept entire suggestion
            • Esc — dismiss suggestion
            • ,,talk — voice-to-text input
            """
        }
        alert.addButton(withTitle: "OK")
        if !allOK {
            alert.addButton(withTitle: "Open System Settings")
        }
        let response = alert.runModal()
        if !allOK && response == .alertSecondButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    // MARK: - Input Monitoring check

    private static func checkInputMonitoring() -> Bool {
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, _, event, _ in Unmanaged.passUnretained(event) },
            userInfo: nil
        )
        let granted = tap != nil
        return granted
    }
}
