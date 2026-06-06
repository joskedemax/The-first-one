import AppKit
import ApplicationServices

/// Thin, Swift-friendly wrappers over the C Accessibility (AX) API.
enum AccessibilityBridge {

    /// Whether the process is trusted for accessibility. If `prompt` is true,
    /// macOS shows the system dialog directing the user to System Settings.
    static func isTrusted(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as NSString
        let options = [key: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// The system-wide AX element (root for querying the focused UI element).
    static let systemWide = AXUIElementCreateSystemWide()

    /// Copy a string attribute from an element.
    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success
        else { return nil }
        return value as? String
    }

    /// Copy a generic element-typed attribute.
    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success
        else { return nil }
        // CFTypeRef that is actually an AXUIElement.
        guard let v = value, CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }

    /// The currently focused UI element across the whole system.
    static func focusedElement() -> AXUIElement? {
        element(systemWide, kAXFocusedUIElementAttribute as String)
    }

    /// Read the selected-text character range (caret is a zero-length range).
    static func selectedRange(_ element: AXUIElement) -> CFRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
              let axValue = value, CFGetTypeID(axValue) == AXValueGetTypeID()
        else { return nil }
        var range = CFRange()
        guard AXValueGetValue(axValue as! AXValue, .cfRange, &range) else { return nil }
        return range
    }

    /// Set the selected-text range (used to position the caret/selection).
    @discardableResult
    static func setSelectedRange(_ element: AXUIElement, _ range: CFRange) -> Bool {
        var r = range
        guard let axValue = AXValueCreate(.cfRange, &r) else { return false }
        return AXUIElementSetAttributeValue(
            element, kAXSelectedTextRangeAttribute as CFString, axValue) == .success
    }

    /// Replace the current selection (or insert at caret) with `text`.
    @discardableResult
    static func replaceSelectedText(_ element: AXUIElement, with text: String) -> Bool {
        AXUIElementSetAttributeValue(
            element, kAXSelectedTextAttribute as CFString, text as CFString) == .success
    }

    /// Screen-space bounds of a character range, if the app supports it.
    /// Returns a rect in Cocoa screen coordinates (origin bottom-left).
    static func boundsForRange(_ element: AXUIElement, _ range: CFRange) -> CGRect? {
        var r = range
        guard let axRange = AXValueCreate(.cfRange, &r) else { return nil }
        var result: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            axRange,
            &result) == .success,
              let value = result, CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(value as! AXValue, .cgRect, &rect) else { return nil }
        // AX rects use top-left origin (screen flipped); convert to Cocoa.
        return flipToCocoa(rect)
    }

    /// The Cocoa-coordinate frame of an element (position + size).
    static func frame(_ element: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let pv = posRef, CFGetTypeID(pv) == AXValueGetTypeID(),
              let sv = sizeRef, CFGetTypeID(sv) == AXValueGetTypeID()
        else { return nil }
        var pos = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(pv as! AXValue, .cgPoint, &pos)
        AXValueGetValue(sv as! AXValue, .cgSize, &size)
        return flipToCocoa(CGRect(origin: pos, size: size))
    }

    /// Try to read font size from the element's AXFont attribute.
    static func fontSize(_ element: AXUIElement) -> CGFloat? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXFont" as CFString, &value) == .success,
              let dict = value as? [String: Any],
              let size = dict["AXFontSize"] as? CGFloat else { return nil }
        return size
    }

    /// Convert a top-left-origin AX screen rect to Cocoa's bottom-left origin.
    static func flipToCocoa(_ rect: CGRect) -> CGRect {
        guard let primary = NSScreen.screens.first else { return rect }
        let totalHeight = primary.frame.maxY
        return CGRect(
            x: rect.origin.x,
            y: totalHeight - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

    /// PID of the app owning an element (for scoping observers).
    static func pid(of element: AXUIElement) -> pid_t? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else { return nil }
        return pid
    }
}
