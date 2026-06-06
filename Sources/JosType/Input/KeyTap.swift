import AppKit
import Carbon.HIToolbox

/// Intercepts Tab, Right-Arrow, and Escape to accept/dismiss suggestions.
///
/// Primary mechanism: a CGEventTap (requires Input Monitoring permission).
/// Fallback: an NSEvent global monitor that detects the keypress *after* it
/// reaches the app and immediately undoes the unwanted character.
final class KeyTap {

    var onAccept: (() -> Bool)?
    var onDismiss: (() -> Bool)?
    var hasActiveSuggestion: (() -> Bool)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var globalMonitor: Any?
    private var usingFallback = false

    func start() {
        if tryCreateEventTap() {
            NSLog("JosType: event tap active (primary mode).")
            usingFallback = false
        } else {
            NSLog("JosType: event tap failed — using fallback key monitor. Grant Input Monitoring for best experience.")
            startFallbackMonitor()
            usingFallback = true
        }
    }

    func stop() {
        stopEventTap()
        stopFallbackMonitor()
    }

    // MARK: - Primary: CGEventTap

    private func tryCreateEventTap() -> Bool {
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let tap = Unmanaged<KeyTap>.fromOpaque(refcon).takeUnretainedValue()
            return tap.handleTap(type: type, event: event)
        }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: refcon
        ) else {
            return false
        }
        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func stopEventTap() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    private func handleTap(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown else { return Unmanaged.passUnretained(event) }
        guard hasActiveSuggestion?() == true else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        let hasModifier = flags.contains(.maskCommand)
            || flags.contains(.maskControl)
            || flags.contains(.maskAlternate)

        if !hasModifier && (keyCode == kVK_Tab || keyCode == kVK_RightArrow) {
            if onAccept?() == true { return nil }
        } else if keyCode == kVK_Escape {
            if onDismiss?() == true { return nil }
        }
        return Unmanaged.passUnretained(event)
    }

    // MARK: - Fallback: NSEvent global monitor

    private func startFallbackMonitor() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleFallbackKey(event)
        }
    }

    private func stopFallbackMonitor() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
        }
        globalMonitor = nil
    }

    private func handleFallbackKey(_ event: NSEvent) {
        guard hasActiveSuggestion?() == true else { return }
        let keyCode = Int(event.keyCode)
        let hasModifier = event.modifierFlags.contains(.command)
            || event.modifierFlags.contains(.control)
            || event.modifierFlags.contains(.option)

        if !hasModifier && (keyCode == kVK_Tab || keyCode == kVK_RightArrow) {
            DispatchQueue.main.async { [weak self] in
                _ = self?.onAccept?()
            }
        } else if keyCode == kVK_Escape {
            DispatchQueue.main.async { [weak self] in
                _ = self?.onDismiss?()
            }
        }
    }
}
