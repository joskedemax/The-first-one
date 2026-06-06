import Foundation

/// Finds the closest known word to a possibly-misspelled token using
/// Damerau–Levenshtein edit distance (insertion, deletion, substitution,
/// transposition). Kept deliberately small and dependency-free.
struct TypoCorrector {

    /// Words considered "correct", paired with frequency for tie-breaking.
    private var dictionary: [String: Int] = [:]
    /// Index by length so we only compare against plausibly-close words.
    private var byLength: [Int: [String]] = [:]

    mutating func setDictionary(_ words: [(word: String, frequency: Int)]) {
        dictionary.removeAll(keepingCapacity: true)
        byLength.removeAll(keepingCapacity: true)
        for (w, f) in words {
            let lw = w.lowercased()
            dictionary[lw] = max(dictionary[lw] ?? 0, f)
            byLength[lw.count, default: []].append(lw)
        }
    }

    func isKnown(_ word: String) -> Bool {
        dictionary[word.lowercased()] != nil
    }

    /// Suggest a correction for `word`, or nil if it's already known / too far.
    /// `maxDistance` scales with word length: short words get distance 1.
    func correction(for word: String) -> String? {
        let lower = word.lowercased()
        guard lower.count >= 3 else { return nil }        // don't "fix" tiny tokens
        if dictionary[lower] != nil { return nil }        // already correct

        let maxDistance = lower.count <= 5 ? 1 : 2
        var best: (word: String, distance: Int, frequency: Int)? = nil

        // Only candidates whose length is within `maxDistance` can be that close.
        for len in (lower.count - maxDistance)...(lower.count + maxDistance) {
            guard let candidates = byLength[len] else { continue }
            for cand in candidates {
                let d = Self.damerauLevenshtein(lower, cand, limit: maxDistance)
                guard d <= maxDistance else { continue }
                let freq = dictionary[cand] ?? 0
                if best == nil
                    || d < best!.distance
                    || (d == best!.distance && freq > best!.frequency) {
                    best = (cand, d, freq)
                }
            }
        }

        guard let result = best else { return nil }
        // Preserve original capitalization style.
        return Self.matchCase(of: word, to: result.word)
    }

    /// Bounded Damerau–Levenshtein. Returns a value > `limit` early if the
    /// distance is guaranteed to exceed it.
    static func damerauLevenshtein(_ a: String, _ b: String, limit: Int) -> Int {
        let s = Array(a), t = Array(b)
        let n = s.count, m = t.count
        if abs(n - m) > limit { return limit + 1 }
        if n == 0 { return m }
        if m == 0 { return n }

        var prevPrev = [Int](repeating: 0, count: m + 1)
        var prev = Array(0...m)
        var curr = [Int](repeating: 0, count: m + 1)

        for i in 1...n {
            curr[0] = i
            var rowMin = curr[0]
            for j in 1...m {
                let cost = s[i - 1] == t[j - 1] ? 0 : 1
                var value = min(
                    prev[j] + 1,        // deletion
                    curr[j - 1] + 1,    // insertion
                    prev[j - 1] + cost  // substitution
                )
                if i > 1 && j > 1
                    && s[i - 1] == t[j - 2]
                    && s[i - 2] == t[j - 1] {
                    value = min(value, prevPrev[j - 2] + 1) // transposition
                }
                curr[j] = value
                rowMin = min(rowMin, value)
            }
            if rowMin > limit { return limit + 1 }
            prevPrev = prev
            prev = curr
            curr = [Int](repeating: 0, count: m + 1)
        }
        return prev[m]
    }

    /// Apply the capitalization pattern of `source` to `target`.
    private static func matchCase(of source: String, to target: String) -> String {
        if source == source.uppercased() && source.count > 1 {
            return target.uppercased()
        }
        if let first = source.first, first.isUppercase {
            return target.prefix(1).uppercased() + target.dropFirst()
        }
        return target
    }
}
