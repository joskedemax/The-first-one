import AppKit

/// Decides WHEN to surface a suggestion, to avoid noise.
///
/// Mirrors the heuristics used by GitHub Copilot's invocation filter:
///   - don't suggest on too-little context
///   - don't suggest mid-word (when a word character sits right of the caret)
///   - back off (cooldown) after the user rejects suggestions
///   - reset state when the focused app/context changes
@MainActor
final class InvocationFilter {

    /// Minimum non-whitespace characters before the caret to consider suggesting.
    var minContextLength = 8
    /// Base cooldown applied after a rejection; grows with repeated rejections.
    var baseCooldown: TimeInterval = 1.2
    /// Hard ceiling on the cooldown.
    var maxCooldown: TimeInterval = 8.0
    /// Rejection count resets after this long with no new rejections.
    var rejectionDecayInterval: TimeInterval = 120.0

    private var lastRejectionTime: Date?
    private var rejectionCount = 0
    private var lastBundleID: String?

    /// Whether the LLM continuation should be requested for this context.
    func shouldSuggestContinuation(
        textBeforeCaret: String,
        textAfterCaret: String,
        bundleID: String?
    ) -> Bool {
        // Reset rejection state when the user switches apps.
        if bundleID != lastBundleID {
            lastBundleID = bundleID
            reset()
        }

        // 1. Require enough preceding context.
        let trimmed = textBeforeCaret.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count < minContextLength { return false }

        // 2. Don't interrupt mid-word: only continue when the caret is at end of
        //    text or the next character is whitespace or a closing character.
        if let next = textAfterCaret.first {
            let closers: Set<Character> = [")", "]", "}", "\"", "'", ";", ",", ".", "!", "?"]
            if Self.isWordChar(next) && !closers.contains(next) {
                return false
            }
        }

        // 3. Decay old rejections so cooldown doesn't persist forever.
        if let t = lastRejectionTime, Date().timeIntervalSince(t) > rejectionDecayInterval {
            reset()
        }

        // 4. Respect cooldown after rejections.
        if let t = lastRejectionTime, Date().timeIntervalSince(t) < currentCooldown() {
            return false
        }

        return true
    }

    func noteAccepted() {
        rejectionCount = 0
        lastRejectionTime = nil
    }

    func noteRejected() {
        rejectionCount += 1
        lastRejectionTime = Date()
    }

    func reset() {
        rejectionCount = 0
        lastRejectionTime = nil
    }

    private func currentCooldown() -> TimeInterval {
        min(baseCooldown * Double(max(1, rejectionCount)), maxCooldown)
    }

    static func isWordChar(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || c == "'" || c == "-" || c == "_"
    }
}
