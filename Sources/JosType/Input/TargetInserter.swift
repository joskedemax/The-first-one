import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Drops composed text into a target app. Prefers the Accessibility API (clean,
/// no clipboard side-effects); falls back to a synthesized ⌘V paste when the
/// target's focused element can't be written directly (common in Electron / web
/// views like the Claude desktop app).
enum TargetInserter {

    static func insert(_ text: String, pid: pid_t?, capturedElement: AXUIElement?) {
        guard !text.isEmpty else { return }

        // Try Accessibility synchronously first — AXUIElement isn't Sendable, so
        // it must not cross a Task boundary. AX writes don't require the target
        // app to be frontmost.
        let inserted = insertViaAX(text, pid: pid, captured: capturedElement)

        // Bring the target forward so the user sees the result land.
        if let pid, let app = NSRunningApplication(processIdentifier: pid) {
            app.activate(options: [])
        }

        if inserted { return }

        // Fallback: paste once the app is frontmost. Electron apps (Claude
        // Desktop, VS Code, Slack, etc.) need extra time to fully activate
        // and place focus in their web view before ⌘V lands.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))

            // Click into the target's focused element to ensure the Electron
            // web view actually has keyboard focus.
            if let pid {
                let appElement = AXUIElementCreateApplication(pid)
                if let focused = AccessibilityBridge.element(appElement, kAXFocusedUIElementAttribute as String) {
                    var posRef: CFTypeRef?
                    var sizeRef: CFTypeRef?
                    AXUIElementCopyAttributeValue(focused, kAXPositionAttribute as CFString, &posRef)
                    AXUIElementCopyAttributeValue(focused, kAXSizeAttribute as CFString, &sizeRef)
                    var pos = CGPoint.zero
                    var size = CGSize.zero
                    if let pv = posRef, CFGetTypeID(pv) == AXValueGetTypeID() {
                        AXValueGetValue(pv as! AXValue, .cgPoint, &pos)
                    }
                    if let sv = sizeRef, CFGetTypeID(sv) == AXValueGetTypeID() {
                        AXValueGetValue(sv as! AXValue, .cgSize, &size)
                    }
                    if size.width > 0 && size.height > 0 {
                        let clickPt = CGPoint(x: pos.x + size.width / 2, y: pos.y + size.height / 2)
                        let src = CGEventSource(stateID: .combinedSessionState)
                        let mouseDown = CGEvent(mouseEventSource: src, mouseType: .leftMouseDown, mouseCursorPosition: clickPt, mouseButton: .left)
                        let mouseUp = CGEvent(mouseEventSource: src, mouseType: .leftMouseUp, mouseCursorPosition: clickPt, mouseButton: .left)
                        mouseDown?.post(tap: .cghidEventTap)
                        mouseUp?.post(tap: .cghidEventTap)
                        try? await Task.sleep(for: .milliseconds(100))
                    }
                }
            }

            paste(text)
        }
    }

    private static func insertViaAX(_ text: String, pid: pid_t?, captured: AXUIElement?) -> Bool {
        // The element that was focused when the composer opened, if it's still
        // in the chosen app.
        if let captured,
           let cpid = AccessibilityBridge.pid(of: captured),
           pid == nil || cpid == pid,
           AccessibilityBridge.replaceSelectedText(captured, with: text) {
            return true
        }

        guard let pid else { return false }
        let appElement = AXUIElementCreateApplication(pid)
        if let focused = AccessibilityBridge.element(appElement, kAXFocusedUIElementAttribute as String),
           AccessibilityBridge.replaceSelectedText(focused, with: text) {
            return true
        }
        return false
    }

    private static func paste(_ text: String) {
        let pasteboard = NSPasteboard.general
        let saved = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)

        // Restore the user's previous clipboard once the paste has landed.
        // Re-fetch the pasteboard inside the task (NSPasteboard isn't Sendable).
        if let saved {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(450))
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(saved, forType: .string)
            }
        }
    }
}
