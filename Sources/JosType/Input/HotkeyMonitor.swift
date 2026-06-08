import AppKit

/// Detects a quick double-tap of the Control (⌃) key as a global trigger.
///
/// Uses NSEvent monitors (global + local) on `.flagsChanged` rather than a
/// CGEventTap — we never need to *consume* the keystroke, just observe it, and
/// global keyboard monitoring is already covered by the Accessibility trust the
/// app requires.
///
/// Deliberately **not** `@MainActor`: the NSEvent monitor handlers are not
/// main-actor-isolated, so (matching `KeyTap`'s pattern) this stays a plain
/// class and hops to the main actor only to fire the callback.
final class HotkeyMonitor {

    /// Fired (on the main actor) when the user double-taps Control.
    var onDoubleTapControl: (@MainActor () -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?

    private var controlDown = false
    private var lastControlPress: TimeInterval = 0
    private var lastFire: TimeInterval = 0

    private let doubleTapWindow: TimeInterval = 0.4
    private let refractory: TimeInterval = 0.5

    // Left/right Control virtual key codes.
    private let controlKeyCodes: Set<UInt16> = [59, 62]

    func start() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handle(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    func stop() {
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
        if let m = localMonitor { NSEvent.removeMonitor(m) }
        globalMonitor = nil
        localMonitor = nil
        controlDown = false
    }

    private func handle(_ event: NSEvent) {
        guard controlKeyCodes.contains(event.keyCode) else { return }
        let nowDown = event.modifierFlags.contains(.control)

        // Only react to the press edge (released → pressed).
        if nowDown && !controlDown {
            let now = ProcessInfo.processInfo.systemUptime
            if now - lastControlPress < doubleTapWindow && now - lastFire > refractory {
                lastFire = now
                let callback = onDoubleTapControl
                Task { @MainActor in callback?() }
            }
            lastControlPress = now
        }
        controlDown = nowDown
    }
}
