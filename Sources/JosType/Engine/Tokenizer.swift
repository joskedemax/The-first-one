import Foundation

/// Lightweight word tokenizer used by the prediction engine.
///
/// We operate on the text *before* the caret. We need three things from it:
///   - the word currently being typed (the trailing run of word characters),
///   - the one or two words preceding it (for n-gram context),
///   - whether the caret is sitting mid-word or just after a separator.
enum Tokenizer {

    /// Characters that count as part of a word.
    static func isWordChar(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || c == "'" || c == "-" || c == "_"
    }

    struct Context {
        /// The partial word immediately before the caret (may be empty).
        let currentPrefix: String
        /// Up to two preceding complete words, oldest first. e.g. ["the", "quick"].
        let priorWords: [String]
        /// Range (in `Character` offsets within the source string) of `currentPrefix`.
        let prefixRange: Range<Int>
    }

    /// Parse the text that appears before the caret.
    static func analyze(_ textBeforeCaret: String) -> Context {
        let chars = Array(textBeforeCaret)
        let end = chars.count
        var start = end
        // Walk back over the trailing word characters to isolate the current prefix.
        while start > 0 && isWordChar(chars[start - 1]) {
            start -= 1
        }
        let currentPrefix = String(chars[start..<end])

        // Collect up to two complete words before `start`.
        var priorWords: [String] = []
        var i = start
        while priorWords.count < 2 && i > 0 {
            // Skip separators.
            while i > 0 && !isWordChar(chars[i - 1]) { i -= 1 }
            guard i > 0 else { break }
            let wEnd = i
            while i > 0 && isWordChar(chars[i - 1]) { i -= 1 }
            priorWords.append(String(chars[i..<wEnd]))
        }
        priorWords.reverse()

        return Context(
            currentPrefix: currentPrefix,
            priorWords: priorWords,
            prefixRange: start..<end
        )
    }

    /// Split arbitrary text into lowercased word tokens (for training).
    static func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        for c in text {
            if isWordChar(c) {
                current.append(c)
            } else if !current.isEmpty {
                tokens.append(current.lowercased())
                current = ""
            }
        }
        if !current.isEmpty { tokens.append(current.lowercased()) }
        return tokens
    }
}
