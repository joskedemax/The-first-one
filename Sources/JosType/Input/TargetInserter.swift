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

            // Click into the best text field to give the Electron web view
            // keyboard focus. Searches the focused window first.
            if let pid {
                let appElement = AXUIElementCreateApplication(pid)
                let clickTarget = AccessibilityBridge.element(appElement, kAXFocusedUIElementAttribute as String)
                    ?? AccessibilityBridge.findEditableTextField(in: appElement)
                if let clickTarget {
                    clickCenter(of: clickTarget)
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }

            paste(text)
        }
    }

    private static func insertViaAX(_ text: String, pid: pid_t?, captured: AXUIElement?) -> Bool {
        // 1. The element that was focused when the composer opened.
        if let captured,
           let cpid = AccessibilityBridge.pid(of: captured),
           pid == nil || cpid == pid,
           AccessibilityBridge.replaceSelectedText(captured, with: text) {
            return true
        }

        guard let pid else { return false }
        let appElement = AXUIElementCreateApplication(pid)

        // 2. The currently focused element in the target app.
        if let focused = AccessibilityBridge.element(appElement, kAXFocusedUIElementAttribute as String),
           AccessibilityBridge.replaceSelectedText(focused, with: text) {
            return true
        }

        // 3. Walk the AX tree to find an editable text field (Electron apps
        //    often don't report a focused element until the user clicks in).
        if let textField = AccessibilityBridge.findEditableTextField(in: appElement) {
            if AccessibilityBridge.replaceSelectedText(textField, with: text) {
                return true
            }
        }

        return false
    }

    /// Synthesize a click at the center of an AX element. AX position is in
    /// CG (top-left-origin) coordinates, which is what CGEvent expects.
    private static func clickCenter(of element: AXUIElement) {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef)
        AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef)
        var pos = CGPoint.zero
        var size = CGSize.zero
        if let pv = posRef, CFGetTypeID(pv) == AXValueGetTypeID() {
            AXValueGetValue(pv as! AXValue, .cgPoint, &pos)
        }
        if let sv = sizeRef, CFGetTypeID(sv) == AXValueGetTypeID() {
            AXValueGetValue(sv as! AXValue, .cgSize, &size)
        }
        guard size.width > 0 && size.height > 0 else { return }
        let pt = CGPoint(x: pos.x + size.width / 2, y: pos.y + size.height / 2)
        let src = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(mouseEventSource: src, mouseType: .leftMouseDown, mouseCursorPosition: pt, mouseButton: .left)
        let up = CGEvent(mouseEventSource: src, mouseType: .leftMouseUp, mouseCursorPosition: pt, mouseButton: .left)
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
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
