import AppKit
import Carbon.HIToolbox

/// Intercepts keys to accept/dismiss suggestions.
///
/// - Tab: accept next word from suggestion
/// - Backtick (`): accept entire suggestion
/// - Right Arrow: accept entire suggestion
/// - Escape: dismiss suggestion
///
/// Primary mechanism: a CGEventTap (requires Input Monitoring permission).
/// Fallback: an NSEvent global monitor.
final class KeyTap {

    var onAcceptWord: (() -> Bool)?
    var onAcceptAll: (() -> Bool)?
    var onDismiss: (() -> Bool)?
    var hasActiveSuggestion: (() -> Bool)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var globalMonitor: Any?
    private var usingFallback = false

    private static let terminalBundleIDs: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "net.kovidgoyal.kitty",
        "com.mitchellh.ghostty",
        "dev.warp.Warp-Stable",
        "dev.warp.Warp",
        "com.github.wez.wezterm",
        "co.zeit.hyper",
        "com.panic.Prompt3",
        "io.alacritty",
    ]

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

        // Tab: accept next word (skip in terminal apps where Tab means completion)
        if !hasModifier && keyCode == kVK_Tab {
            if isTerminalFrontmost() {
                return Unmanaged.passUnretained(event)
            }
            if onAcceptWord?() == true { return nil }
        }

        // Backtick or Right Arrow: accept entire suggestion
        if !hasModifier && (keyCode == kVK_RightArrow || keyCode == kVK_ANSI_Grave) {
            if onAcceptAll?() == true { return nil }
        }

        if keyCode == kVK_Escape {
            if onDismiss?() == true { return nil }
        }

        return Unmanaged.passUnretained(event)
    }

    private func isTerminalFrontmost() -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier else { return false }
        return Self.terminalBundleIDs.contains(bundleID)
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

        if !hasModifier && keyCode == kVK_Tab {
            if isTerminalFrontmost() { return }
            DispatchQueue.main.async { [weak self] in
                _ = self?.onAcceptWord?()
            }
        } else if !hasModifier && (keyCode == kVK_RightArrow || keyCode == kVK_ANSI_Grave) {
            DispatchQueue.main.async { [weak self] in
                _ = self?.onAcceptAll?()
            }
        } else if keyCode == kVK_Escape {
            DispatchQueue.main.async { [weak self] in
                _ = self?.onDismiss?()
            }
        }
    }
}
