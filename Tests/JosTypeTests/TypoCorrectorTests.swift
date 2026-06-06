import XCTest
@testable import JosType

final class TypoCorrectorTests: XCTestCase {

    private func makeCorrector(words: [(String, Int)]) -> TypoCorrector {
        var c = TypoCorrector()
        c.setDictionary(words.map { (word: $0.0, frequency: $0.1) })
        return c
    }

    func testKnownWordReturnsNil() {
        let c = makeCorrector(words: [("hello", 10)])
        XCTAssertNil(c.correction(for: "hello"))
    }

    func testKnownWordCaseInsensitive() {
        let c = makeCorrector(words: [("hello", 10)])
        XCTAssertNil(c.correction(for: "Hello"))
    }

    func testSingleSubstitution() {
        let c = makeCorrector(words: [("hello", 10)])
        let fix = c.correction(for: "hallo")
        XCTAssertEqual(fix?.lowercased(), "hello")
    }

    func testTransposition() {
        let c = makeCorrector(words: [("the", 100)])
        let fix = c.correction(for: "teh")
        XCTAssertEqual(fix?.lowercased(), "the")
    }

    func testShortWordsSkipped() {
        let c = makeCorrector(words: [("at", 100)])
        XCTAssertNil(c.correction(for: "ta"))
    }

    func testDistanceTooLarge() {
        let c = makeCorrector(words: [("hello", 10)])
        XCTAssertNil(c.correction(for: "xxxxx"))
    }

    func testCasePreservationTitleCase() {
        let c = makeCorrector(words: [("hello", 10)])
        let fix = c.correction(for: "Hallo")
        XCTAssertEqual(fix, "Hello")
    }

    func testCasePreservationAllCaps() {
        let c = makeCorrector(words: [("hello", 10)])
        let fix = c.correction(for: "HALLO")
        XCTAssertEqual(fix, "HELLO")
    }

    func testPreferHigherFrequency() {
        let c = makeCorrector(words: [("cat", 5), ("car", 50)])
        let fix = c.correction(for: "cas")
        XCTAssertEqual(fix, "car")
    }

    // MARK: - Damerau-Levenshtein distance

    func testDLIdentical() {
        XCTAssertEqual(TypoCorrector.damerauLevenshtein("abc", "abc", limit: 3), 0)
    }

    func testDLSingleInsert() {
        XCTAssertEqual(TypoCorrector.damerauLevenshtein("abc", "abcd", limit: 3), 1)
    }

    func testDLSingleDelete() {
        XCTAssertEqual(TypoCorrector.damerauLevenshtein("abcd", "abc", limit: 3), 1)
    }

    func testDLSingleSubstitution() {
        XCTAssertEqual(TypoCorrector.damerauLevenshtein("abc", "axc", limit: 3), 1)
    }

    func testDLTransposition() {
        XCTAssertEqual(TypoCorrector.damerauLevenshtein("ab", "ba", limit: 3), 1)
    }

    func testDLBoundedLimit() {
        let d = TypoCorrector.damerauLevenshtein("abcdef", "xyzxyz", limit: 2)
        XCTAssertGreaterThan(d, 2)
    }

    func testDLEmptyStrings() {
        XCTAssertEqual(TypoCorrector.damerauLevenshtein("", "", limit: 5), 0)
        XCTAssertEqual(TypoCorrector.damerauLevenshtein("abc", "", limit: 5), 3)
        XCTAssertEqual(TypoCorrector.damerauLevenshtein("", "abc", limit: 5), 3)
    }
}
