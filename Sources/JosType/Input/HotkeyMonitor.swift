import AppKit

/// Detects a quick double-tap of the Shift (⇧) key as a global trigger.
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

    /// Fired (on the main actor) when the user double-taps Shift.
    var onDoubleTapShift: (@MainActor () -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?

    private var shiftDown = false
    private var lastShiftPress: TimeInterval = 0
    private var lastFire: TimeInterval = 0

    private let doubleTapWindow: TimeInterval = 0.35
    private let refractory: TimeInterval = 0.5

    // Left/right Shift virtual key codes.
    private let shiftKeyCodes: Set<UInt16> = [56, 60]

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
        shiftDown = false
    }

    private func handle(_ event: NSEvent) {
        guard shiftKeyCodes.contains(event.keyCode) else { return }
        let nowDown = event.modifierFlags.contains(.shift)

        // Ignore if other modifiers are held (user is doing Shift+Cmd etc.).
        let otherModifiers: NSEvent.ModifierFlags = [.command, .option, .control]
        if !event.modifierFlags.intersection(otherModifiers).isEmpty { return }

        // Only react to the press edge (released → pressed).
        if nowDown && !shiftDown {
            let now = ProcessInfo.processInfo.systemUptime
            if now - lastShiftPress < doubleTapWindow && now - lastFire > refractory {
                lastFire = now
                let callback = onDoubleTapShift
                Task { @MainActor in callback?() }
            }
            lastShiftPress = now
        }
        shiftDown = nowDown
    }
}
