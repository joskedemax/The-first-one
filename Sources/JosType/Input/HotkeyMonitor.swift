import AppKit

/// Detects a quick double-tap of the Option (⌥) key as a global trigger.
///
/// Uses NSEvent monitors (global + local) on `.flagsChanged` rather than a
/// CGEventTap — we never need to *consume* the keystroke, just observe it, and
/// global keyboard monitoring is already covered by the Accessibility trust the
/// app requires.
@MainActor
final class HotkeyMonitor {

    /// Fired when the user double-taps Option within `doubleTapWindow`.
    var onDoubleTapOption: (() -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?

    private var optionDown = false
    private var lastOptionPress: TimeInterval = 0
    private var lastFire: TimeInterval = 0

    private let doubleTapWindow: TimeInterval = 0.4
    private let refractory: TimeInterval = 0.5

    // Left/right Option virtual key codes.
    private let optionKeyCodes: Set<UInt16> = [58, 61]

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
        optionDown = false
    }

    private func handle(_ event: NSEvent) {
        guard optionKeyCodes.contains(event.keyCode) else { return }
        let nowDown = event.modifierFlags.contains(.option)

        // Only react to the press edge (released → pressed).
        if nowDown && !optionDown {
            let now = ProcessInfo.processInfo.systemUptime
            if now - lastOptionPress < doubleTapWindow && now - lastFire > refractory {
                lastFire = now
                onDoubleTapOption?()
            }
            lastOptionPress = now
        }
        optionDown = nowDown
    }
}
