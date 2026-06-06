import Foundation

/// A prefix tree for fast word completion, weighted by frequency.
/// Each terminal node stores a cumulative frequency so we can rank completions.
final class Trie {

    final class Node {
        var children: [Character: Node] = [:]
        var isWord = false
        var frequency: Int = 0
        /// Best (highest) frequency found anywhere in this subtree — lets us
        /// prune and rank during traversal without exploring everything.
        var maxSubtreeFrequency: Int = 0
    }

    private let root = Node()
    private(set) var count = 0

    /// Insert a word, adding `freq` to its existing frequency.
    func insert(_ word: String, frequency freq: Int = 1) {
        guard !word.isEmpty else { return }
        var node = root
        node.maxSubtreeFrequency = max(node.maxSubtreeFrequency, freq)
        for ch in word {
            let child = node.children[ch] ?? {
                let n = Node()
                node.children[ch] = n
                return n
            }()
            node = child
            node.maxSubtreeFrequency = max(node.maxSubtreeFrequency, freq)
        }
        if !node.isWord { count += 1 }
        node.isWord = true
        node.frequency += freq
        node.maxSubtreeFrequency = max(node.maxSubtreeFrequency, node.frequency)
    }

    /// True if the exact word exists in the trie.
    func contains(_ word: String) -> Bool {
        node(for: word)?.isWord ?? false
    }

    private func node(for prefix: String) -> Node? {
        var node = root
        for ch in prefix {
            guard let next = node.children[ch] else { return nil }
            node = next
        }
        return node
    }

    /// Return up to `limit` completions for `prefix`, ranked by frequency
    /// (highest first). Completions are full words including the prefix.
    func completions(for prefix: String, limit: Int = 5) -> [(word: String, frequency: Int)] {
        guard let start = node(for: prefix) else { return [] }
        var results: [(String, Int)] = []
        collect(node: start, prefix: prefix, into: &results)
        results.sort { $0.1 > $1.1 }
        if results.count > limit { results.removeLast(results.count - limit) }
        return results.map { (word: $0.0, frequency: $0.1) }
    }

    private func collect(node: Node, prefix: String, into results: inout [(String, Int)]) {
        if node.isWord {
            results.append((prefix, node.frequency))
        }
        for (ch, child) in node.children {
            collect(node: child, prefix: prefix + String(ch), into: &results)
        }
    }

    /// Every word in the trie (used to build the typo-correction dictionary).
    func allWords() -> [String] {
        var out: [String] = []
        collect(node: root, prefix: "", into: &out)
        return out
    }

    private func collect(node: Node, prefix: String, into out: inout [String]) {
        if node.isWord { out.append(prefix) }
        for (ch, child) in node.children {
            collect(node: child, prefix: prefix + String(ch), into: &out)
        }
    }
}
