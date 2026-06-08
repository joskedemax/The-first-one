import AppKit
import ApplicationServices

/// Applies an accepted `Suggestion` to a focused text element via the AX API.
enum TextInserter {

    /// Insert/replace text to satisfy `suggestion`. Returns true on success.
    ///
    /// - For completions and next-word, `replaceRange` is empty at the caret,
    ///   so we just insert at the current insertion point.
    /// - For corrections, we first select the misspelled word's range, then
    ///   replace the selection with the fix.
    @discardableResult
    static func apply(_ suggestion: Suggestion, to element: AXUIElement, fullText: String) -> Bool {
        if suggestion.replaceRange.isEmpty {
            return AccessibilityBridge.replaceSelectedText(element, with: suggestion.insertText)
        }

        let utf16Start = AccessibilityBridge.utf16Offset(in: fullText, characterOffset: suggestion.replaceRange.lowerBound)
        let utf16End = AccessibilityBridge.utf16Offset(in: fullText, characterOffset: suggestion.replaceRange.upperBound)
        let cfRange = CFRange(location: utf16Start, length: utf16End - utf16Start)

        guard AccessibilityBridge.setSelectedRange(element, cfRange) else { return false }
        return AccessibilityBridge.replaceSelectedText(element, with: suggestion.insertText)
    }

}
