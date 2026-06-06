import AppKit
import Carbon.HIToolbox

/// A CGEventTap that intercepts Tab and Escape — but *only* when a suggestion
/// is currently visible. When no suggestion is showing, every keystroke passes
/// through untouched, so normal Tab behavior is preserved.
final class KeyTap {

    /// Called when the user accepts the suggestion (Tab). Return true if the
    /// event was consumed (a suggestion existed and was applied).
    var onAccept: (() -> Bool)?
    /// Called when the user dismisses the suggestion (Esc). Return true if a
    /// suggestion existed and was dismissed.
    var onDismiss: (() -> Bool)?
    /// Whether a suggestion is currently visible. Read on the event-tap thread.
    var hasActiveSuggestion: (() -> Bool)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    func start() {
        let mask = (1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let tap = Unmanaged<KeyTap>.fromOpaque(refcon).takeUnretainedValue()
            return tap.handle(type: type, event: event)
        }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: refcon
        ) else {
            NSLog("Glide: failed to create event tap (Input Monitoring permission needed).")
            return
        }
        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Re-enable if the system disabled the tap (e.g. after a timeout).
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown else { return Unmanaged.passUnretained(event) }

        // Only intercept when a suggestion is on screen.
        guard hasActiveSuggestion?() == true else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        // Ignore Tab combined with modifiers (e.g. Cmd-Tab app switching).
        let hasModifier = flags.contains(.maskCommand)
            || flags.contains(.maskControl)
            || flags.contains(.maskAlternate)

        if keyCode == kVK_Tab && !hasModifier {
            if onAccept?() == true {
                return nil // consume — don't insert a literal tab
            }
        } else if keyCode == kVK_Escape {
            if onDismiss?() == true {
                return nil // consume the escape
            }
        }
        return Unmanaged.passUnretained(event)
    }
}
