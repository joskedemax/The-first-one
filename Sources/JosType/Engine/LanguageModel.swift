import Foundation

/// On-device statistical language model.
///
/// Holds unigram frequencies (in a `Trie` for prefix completion) plus bigram
/// and trigram counts for next-word prediction. Seeded from a bundled word
/// list, then continuously updated from the user's own typing and persisted
/// to Application Support.
final class LanguageModel {

    let trie = Trie()
    private(set) var unigrams: [String: Int] = [:]
    /// bigrams["the"] -> ["quick": 3, "lazy": 1, ...]
    private var bigrams: [String: [String: Int]] = [:]
    /// trigrams["the quick"] -> ["brown": 2, ...]
    private var trigrams: [String: [String: Int]] = [:]

    private let queue = DispatchQueue(label: "app.jostype.languagemodel", attributes: .concurrent)

    // MARK: - Seeding

    /// Load the bundled seed word list (word<TAB>frequency per line).
    func loadSeed() {
        guard let url = Bundle.module.url(forResource: "seed_words", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return
        }
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "\t")
            guard let word = parts.first.map(String.init) else { continue }
            let freq = parts.count > 1 ? Int(parts[1]) ?? 1 : 1
            insertUnigram(word.lowercased(), count: freq)
        }
    }

    // MARK: - Training

    /// Train from a chunk of free text (e.g. something the user just typed).
    func train(on text: String) {
        let tokens = Tokenizer.tokenize(text)
        guard !tokens.isEmpty else { return }
        queue.async(flags: .barrier) {
            for (i, tok) in tokens.enumerated() {
                self.insertUnigram(tok, count: 1, locked: true)
                if i >= 1 {
                    self.bigrams[tokens[i - 1], default: [:]][tok, default: 0] += 1
                }
                if i >= 2 {
                    let key = tokens[i - 2] + " " + tokens[i - 1]
                    self.trigrams[key, default: [:]][tok, default: 0] += 1
                }
            }
        }
    }

    private func insertUnigram(_ word: String, count: Int, locked: Bool = false) {
        let work = {
            self.unigrams[word, default: 0] += count
            self.trie.insert(word, frequency: count)
        }
        if locked { work() } else { queue.async(flags: .barrier, execute: work) }
    }

    // MARK: - Prediction

    /// Rank next-word candidates given up to two prior words.
    /// Trigram evidence is weighted above bigram evidence.
    func nextWordCandidates(prior: [String], limit: Int = 5) -> [(word: String, score: Int)] {
        queue.sync {
            var scores: [String: Int] = [:]
            if prior.count >= 2 {
                let key = prior[prior.count - 2] + " " + prior[prior.count - 1]
                for (w, c) in trigrams[key] ?? [:] { scores[w, default: 0] += c * 4 }
            }
            if let last = prior.last {
                for (w, c) in bigrams[last] ?? [:] { scores[w, default: 0] += c * 2 }
            }
            return scores
                .sorted { $0.value > $1.value }
                .prefix(limit)
                .map { (word: $0.key, score: $0.value) }
        }
    }

    func completions(for prefix: String, limit: Int = 5) -> [(word: String, frequency: Int)] {
        queue.sync { trie.completions(for: prefix, limit: limit) }
    }

    /// Snapshot of (word, frequency) pairs for the typo dictionary.
    func dictionarySnapshot() -> [(word: String, frequency: Int)] {
        queue.sync { unigrams.map { (word: $0.key, frequency: $0.value) } }
    }

    // MARK: - Persistence

    private struct Persisted: Codable {
        var unigrams: [String: Int]
        var bigrams: [String: [String: Int]]
        var trigrams: [String: [String: Int]]
    }

    private static var storeURL: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("JosType", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("model.json")
    }

    func load() {
        guard let data = try? Data(contentsOf: Self.storeURL),
              let decoded = try? JSONDecoder().decode(Persisted.self, from: data) else {
            return
        }
        queue.async(flags: .barrier) {
            self.bigrams = decoded.bigrams
            self.trigrams = decoded.trigrams
            for (w, c) in decoded.unigrams {
                self.unigrams[w, default: 0] += c
                self.trie.insert(w, frequency: c)
            }
        }
    }

    func save() {
        queue.sync {
            let snapshot = Persisted(unigrams: unigrams, bigrams: bigrams, trigrams: trigrams)
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: Self.storeURL, options: .atomic)
        }
    }
}
