import Foundation

/// A single suggestion to present to the user.
struct Suggestion: Equatable {
    enum Kind {
        case completion   // finishing the current word
        case nextWord     // predicting the following word
        case correction   // fixing a typo in the current word
    }

    let kind: Kind
    /// The text that will actually be inserted on accept.
    let insertText: String
    /// What the user sees as ghost text (often same as insertText).
    let displayText: String
    /// Character range in the source field that the insert replaces.
    /// For completion/nextWord this is an empty range at the caret.
    let replaceRange: Range<Int>
}

/// Turns "text before the caret" into a ranked best `Suggestion`.
final class PredictionEngine {

    private let model: LanguageModel
    private var corrector = TypoCorrector()

    init(model: LanguageModel) {
        self.model = model
        refreshDictionary()
    }

    /// Rebuild the typo dictionary from the current model. Call after training
    /// rounds; cheap enough to call periodically.
    func refreshDictionary() {
        corrector.setDictionary(model.dictionarySnapshot())
    }

    /// Produce the best suggestion for the text up to the caret, or nil.
    /// `caretOffset` is the caret's character index in the full field text.
    func suggest(textBeforeCaret: String, caretOffset: Int) -> Suggestion? {
        let ctx = Tokenizer.analyze(textBeforeCaret)
        let prefixStart = caretOffset - ctx.currentPrefix.count

        // Case 1: actively typing a word -> complete it, or correct it.
        if !ctx.currentPrefix.isEmpty {
            let prefix = ctx.currentPrefix

            // Prefer a completion if one extends the prefix.
            let lowerPrefix = prefix.lowercased()
            if let best = model.completions(for: lowerPrefix, limit: 1).first,
               best.word.count > lowerPrefix.count {
                let suffix = String(best.word.dropFirst(lowerPrefix.count))
                if !suffix.isEmpty {
                    return Suggestion(
                        kind: .completion,
                        insertText: suffix,
                        displayText: suffix,
                        replaceRange: caretOffset..<caretOffset
                    )
                }
            }

            // No completion: if the (whole) word looks misspelled, offer a fix.
            // Only when prefix is at least 3 chars and unknown.
            if prefix.count >= 3,
               !corrector.isKnown(prefix),
               let fix = corrector.correction(for: prefix),
               fix.lowercased() != prefix.lowercased() {
                return Suggestion(
                    kind: .correction,
                    insertText: fix,
                    displayText: fix,
                    replaceRange: prefixStart..<caretOffset
                )
            }
            return nil
        }

        // Case 2: caret sits after a separator -> predict the next word.
        let candidates = model.nextWordCandidates(prior: ctx.priorWords, limit: 1)
        if let top = candidates.first {
            // Match capitalization if we're at the start of a sentence.
            let needsCap = shouldCapitalize(textBeforeCaret: textBeforeCaret)
            let word = needsCap ? top.word.prefix(1).uppercased() + top.word.dropFirst() : top.word
            return Suggestion(
                kind: .nextWord,
                insertText: word,
                displayText: word,
                replaceRange: caretOffset..<caretOffset
            )
        }
        return nil
    }

    private func shouldCapitalize(textBeforeCaret: String) -> Bool {
        let trimmed = textBeforeCaret.trimmingCharacters(in: .whitespaces)
        guard let last = trimmed.last else { return true }       // start of field
        return last == "." || last == "!" || last == "?"
    }
}
