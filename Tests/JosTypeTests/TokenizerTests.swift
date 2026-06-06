import XCTest
@testable import JosType

final class TokenizerTests: XCTestCase {

    // MARK: - analyze()

    func testAnalyzeEmptyString() {
        let ctx = Tokenizer.analyze("")
        XCTAssertEqual(ctx.currentPrefix, "")
        XCTAssertTrue(ctx.priorWords.isEmpty)
        XCTAssertEqual(ctx.prefixRange, 0..<0)
    }

    func testAnalyzeSingleWord() {
        let ctx = Tokenizer.analyze("hel")
        XCTAssertEqual(ctx.currentPrefix, "hel")
        XCTAssertTrue(ctx.priorWords.isEmpty)
        XCTAssertEqual(ctx.prefixRange, 0..<3)
    }

    func testAnalyzeWordWithPrior() {
        let ctx = Tokenizer.analyze("the quick br")
        XCTAssertEqual(ctx.currentPrefix, "br")
        XCTAssertEqual(ctx.priorWords, ["the", "quick"])
    }

    func testAnalyzeCaretAfterSpace() {
        let ctx = Tokenizer.analyze("hello ")
        XCTAssertEqual(ctx.currentPrefix, "")
        XCTAssertEqual(ctx.priorWords, ["hello"])
    }

    func testAnalyzePunctuationBoundary() {
        let ctx = Tokenizer.analyze("end. St")
        XCTAssertEqual(ctx.currentPrefix, "St")
        XCTAssertEqual(ctx.priorWords, ["end"])
    }

    func testAnalyzeMaxTwoPriorWords() {
        let ctx = Tokenizer.analyze("one two three four")
        XCTAssertEqual(ctx.currentPrefix, "four")
        XCTAssertEqual(ctx.priorWords.count, 2)
        XCTAssertEqual(ctx.priorWords, ["two", "three"])
    }

    func testAnalyzeAllWhitespace() {
        let ctx = Tokenizer.analyze("   ")
        XCTAssertEqual(ctx.currentPrefix, "")
        XCTAssertTrue(ctx.priorWords.isEmpty)
    }

    func testAnalyzeApostrophe() {
        let ctx = Tokenizer.analyze("don't")
        XCTAssertEqual(ctx.currentPrefix, "don't")
    }

    func testAnalyzeHyphen() {
        let ctx = Tokenizer.analyze("well-kn")
        XCTAssertEqual(ctx.currentPrefix, "well-kn")
    }

    // MARK: - tokenize()

    func testTokenizeBasic() {
        let tokens = Tokenizer.tokenize("Hello World")
        XCTAssertEqual(tokens, ["hello", "world"])
    }

    func testTokenizePunctuation() {
        let tokens = Tokenizer.tokenize("Hello, world! How are you?")
        XCTAssertEqual(tokens, ["hello", "world", "how", "are", "you"])
    }

    func testTokenizeEmpty() {
        XCTAssertTrue(Tokenizer.tokenize("").isEmpty)
    }

    func testTokenizeAllWhitespace() {
        XCTAssertTrue(Tokenizer.tokenize("   \n  ").isEmpty)
    }

    func testTokenizePreservesApostrophe() {
        let tokens = Tokenizer.tokenize("don't can't")
        XCTAssertEqual(tokens, ["don't", "can't"])
    }

    // MARK: - isWordChar()

    func testIsWordChar() {
        XCTAssertTrue(Tokenizer.isWordChar("a"))
        XCTAssertTrue(Tokenizer.isWordChar("Z"))
        XCTAssertTrue(Tokenizer.isWordChar("5"))
        XCTAssertTrue(Tokenizer.isWordChar("'"))
        XCTAssertTrue(Tokenizer.isWordChar("-"))
        XCTAssertTrue(Tokenizer.isWordChar("_"))
        XCTAssertFalse(Tokenizer.isWordChar(" "))
        XCTAssertFalse(Tokenizer.isWordChar("."))
        XCTAssertFalse(Tokenizer.isWordChar(","))
    }
}
