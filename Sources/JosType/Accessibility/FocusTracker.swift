import AppKit
import ApplicationServices

/// Snapshot of the focused text field at a moment in time.
struct TextSnapshot {
    let element: AXUIElement
    let fullText: String
    let caretOffset: Int      // character index of the caret
}

/// Watches the system for focus and text changes in editable fields and
/// reports snapshots. Uses AX observers on the frontmost app, refreshing the
/// observer when the active application changes.
final class FocusTracker {

    var onChange: ((TextSnapshot?) -> Void)?

    private var observer: AXObserver?
    private var observedPID: pid_t?
    private var observedElement: AXUIElement?

    func start() {
        // Re-evaluate whenever the active app changes.
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeAppChanged),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        attachToFrontmostApp()
    }

    func stop() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        teardownObserver()
        observedElement = nil
        onChange?(nil)
    }

    @objc private func activeAppChanged() {
        attachToFrontmostApp()
    }

    private func attachToFrontmostApp() {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        let pid = app.processIdentifier
        if pid == observedPID { return }
        teardownObserver()
        observedPID = pid

        var obs: AXObserver?
        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            let tracker = Unmanaged<FocusTracker>.fromOpaque(refcon).takeUnretainedValue()
            tracker.emitCurrentSnapshot()
        }
        guard AXObserverCreate(pid, callback, &obs) == .success, let observer = obs else { return }
        self.observer = observer

        let appElement = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for note in [
            kAXFocusedUIElementChangedNotification,
            kAXValueChangedNotification,
            kAXSelectedTextChangedNotification
        ] {
            AXObserverAddNotification(observer, appElement, note as CFString, refcon)
        }
        CFRunLoopAddSource(
            CFRunLoopGetCurrent(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )
        emitCurrentSnapshot()
    }

    private func teardownObserver() {
        if let observer {
            CFRunLoopRemoveSource(
                CFRunLoopGetCurrent(),
                AXObserverGetRunLoopSource(observer),
                .defaultMode
            )
        }
        observer = nil
        observedPID = nil
    }

    /// Read the focused element and report a snapshot (or nil if not editable).
    func emitCurrentSnapshot() {
        guard let focused = AccessibilityBridge.focusedElement() else {
            observedElement = nil
            onChange?(nil)
            return
        }
        observedElement = focused

        // Must have a string value and a caret to be useful.
        guard let text = AccessibilityBridge.string(focused, kAXValueAttribute as String),
              let range = AccessibilityBridge.selectedRange(focused) else {
            onChange?(nil)
            return
        }
        // Only act on a collapsed caret (no active selection).
        guard range.length == 0 else {
            onChange?(nil)
            return
        }
        let caret = clamp(range.location, 0, (text as NSString).length)
        // Convert NSString (UTF-16) caret offset into Character offset for our engine.
        let caretCharOffset = characterOffset(in: text, utf16Offset: caret)
        onChange?(TextSnapshot(element: focused, fullText: text, caretOffset: caretCharOffset))
    }

    /// The element currently focused, for the inserter to act on.
    var currentElement: AXUIElement? { observedElement }

    private func clamp(_ v: Int, _ lo: Int, _ hi: Int) -> Int { max(lo, min(hi, v)) }

    private func characterOffset(in string: String, utf16Offset: Int) -> Int {
        let ns = string as NSString
        let safe = clamp(utf16Offset, 0, ns.length)
        let prefix = ns.substring(to: safe)
        return prefix.count
    }
}
