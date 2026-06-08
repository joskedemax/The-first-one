import XCTest
@testable import JosType

@MainActor
final class CleanResponseTests: XCTestCase {

    private let predictor = LLMPredictor()

    // MARK: - cleanResponse

    func testStripsWhitespace() {
        let result = predictor.cleanResponse("  hello world  ", maxLength: 200)
        XCTAssertEqual(result, "hello world")
    }

    func testStripsQuotes() {
        XCTAssertEqual(predictor.cleanResponse("\"hello\"", maxLength: 200), "hello")
        XCTAssertEqual(predictor.cleanResponse("'hello'", maxLength: 200), "hello")
        XCTAssertEqual(predictor.cleanResponse("`hello`", maxLength: 200), "hello")
    }

    func testLimitsToFourSentences() {
        let input = "First. Second. Third. Fourth. Fifth."
        let result = predictor.cleanResponse(input, maxLength: 500)
        XCTAssertEqual(result, "First. Second. Third. Fourth.")
    }

    func testTruncatesAtMaxLength() {
        let input = "This is a fairly long sentence that should be truncated at a word boundary"
        let result = predictor.cleanResponse(input, maxLength: 30)
        XCTAssertLessThanOrEqual(result.count, 30)
        XCTAssertFalse(result.hasSuffix(" "))
    }

    func testTruncatesAtWordBoundary() {
        let input = "word1 word2 word3 word4 word5"
        let result = predictor.cleanResponse(input, maxLength: 15)
        XCTAssertTrue(result == "word1 word2" || result == "word1 word2 wo" == false)
        XCTAssertFalse(result.contains("word3"))
    }

    func testEmptyResponse() {
        XCTAssertEqual(predictor.cleanResponse("", maxLength: 200), "")
    }

    func testSingleSentence() {
        let result = predictor.cleanResponse("Just one sentence.", maxLength: 200)
        XCTAssertEqual(result, "Just one sentence.")
    }

    // MARK: - postProcess

    func testRejectsShortOutput() {
        let result = predictor.postProcess("a", context: "hello ")
        XCTAssertNil(result)
    }

    func testRejectsContextEcho() {
        let result = predictor.postProcess("hello world", context: "some text hello world")
        XCTAssertNil(result)
    }

    func testAddsLeadingSpace() {
        let result = predictor.postProcess("world is great today.", context: "hello")
        XCTAssertTrue(result?.hasPrefix(" ") ?? false)
    }

    func testNoLeadingSpaceAfterWhitespace() {
        let result = predictor.postProcess("world is great today.", context: "hello ")
        XCTAssertFalse(result?.hasPrefix(" ") ?? true)
    }

    func testValidPrediction() {
        let result = predictor.postProcess("and the world is beautiful.", context: "Hello ")
        XCTAssertNotNil(result)
        XCTAssertEqual(result, "and the world is beautiful.")
    }
}
