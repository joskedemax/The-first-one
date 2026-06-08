import XCTest
@testable import JosType

final class TrieTests: XCTestCase {

    func testInsertAndContains() {
        let trie = Trie()
        trie.insert("hello")
        XCTAssertTrue(trie.contains("hello"))
        XCTAssertFalse(trie.contains("hell"))
        XCTAssertFalse(trie.contains("helloo"))
    }

    func testCountIncrementsOnNewWords() {
        let trie = Trie()
        XCTAssertEqual(trie.count, 0)
        trie.insert("a")
        XCTAssertEqual(trie.count, 1)
        trie.insert("b")
        XCTAssertEqual(trie.count, 2)
        trie.insert("a")
        XCTAssertEqual(trie.count, 2)
    }

    func testFrequencyAccumulates() {
        let trie = Trie()
        trie.insert("word", frequency: 3)
        trie.insert("word", frequency: 5)
        let results = trie.completions(for: "word")
        XCTAssertEqual(results.first?.frequency, 8)
    }

    func testCompletionsRankedByFrequency() {
        let trie = Trie()
        trie.insert("apple", frequency: 10)
        trie.insert("application", frequency: 5)
        trie.insert("appetizer", frequency: 20)
        let results = trie.completions(for: "app")
        XCTAssertEqual(results.first?.word, "appetizer")
        XCTAssertEqual(results.count, 3)
    }

    func testCompletionsRespectsLimit() {
        let trie = Trie()
        for i in 0..<20 {
            trie.insert("word\(i)", frequency: i)
        }
        let results = trie.completions(for: "word", limit: 3)
        XCTAssertEqual(results.count, 3)
        XCTAssertEqual(results.first?.word, "word19")
    }

    func testEmptyTrieReturnsNoCompletions() {
        let trie = Trie()
        XCTAssertTrue(trie.completions(for: "any").isEmpty)
    }

    func testUnknownPrefixReturnsEmpty() {
        let trie = Trie()
        trie.insert("hello")
        XCTAssertTrue(trie.completions(for: "xyz").isEmpty)
    }

    func testSingleCharacterWord() {
        let trie = Trie()
        trie.insert("a", frequency: 5)
        XCTAssertTrue(trie.contains("a"))
        let results = trie.completions(for: "a")
        XCTAssertEqual(results.first?.word, "a")
    }

    func testEmptyWordNotInserted() {
        let trie = Trie()
        trie.insert("")
        XCTAssertEqual(trie.count, 0)
    }

    func testAllWords() {
        let trie = Trie()
        trie.insert("cat")
        trie.insert("car")
        trie.insert("dog")
        let all = Set(trie.allWords())
        XCTAssertEqual(all, ["cat", "car", "dog"])
    }
}
