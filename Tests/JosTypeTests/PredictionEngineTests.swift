import XCTest
@testable import JosType

final class PredictionEngineTests: XCTestCase {

    private func makeEngine(words: [(String, Int)], bigrams: [(String, String, Int)] = []) -> PredictionEngine {
        let model = LanguageModel()
        for (word, freq) in words {
            model.train(on: String(repeating: "\(word) ", count: freq))
        }
        let expectation = XCTestExpectation(description: "training completes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { expectation.fulfill() }
        wait(for: [expectation], timeout: 2.0)
        let engine = PredictionEngine(model: model)
        return engine
    }

    func testCompletionForPartialWord() {
        let engine = makeEngine(words: [("application", 10)])
        let suggestion = engine.suggest(textBeforeCaret: "app", caretOffset: 3)
        XCTAssertNotNil(suggestion)
        XCTAssertEqual(suggestion?.kind, .completion)
        XCTAssertEqual(suggestion?.insertText, "lication")
    }

    func testNoSuggestionForUnknownPrefix() {
        let engine = makeEngine(words: [("hello", 10)])
        let suggestion = engine.suggest(textBeforeCaret: "xyz", caretOffset: 3)
        XCTAssertNil(suggestion)
    }

    func testCorrectionForMisspelling() {
        let engine = makeEngine(words: [("hello", 50)])
        let suggestion = engine.suggest(textBeforeCaret: "hallo", caretOffset: 5)
        XCTAssertNotNil(suggestion)
        XCTAssertEqual(suggestion?.kind, .correction)
        XCTAssertEqual(suggestion?.insertText.lowercased(), "hello")
        XCTAssertEqual(suggestion?.replaceRange, 0..<5)
    }

    func testNoCorrectionForKnownWord() {
        let engine = makeEngine(words: [("hello", 10)])
        let suggestion = engine.suggest(textBeforeCaret: "hello", caretOffset: 5)
        XCTAssertNil(suggestion)
    }

    func testNextWordPrediction() {
        let model = LanguageModel()
        model.train(on: "the quick brown the quick red")
        let expectation = XCTestExpectation(description: "training completes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { expectation.fulfill() }
        wait(for: [expectation], timeout: 2.0)
        let engine = PredictionEngine(model: model)
        let suggestion = engine.suggest(textBeforeCaret: "the ", caretOffset: 4)
        XCTAssertNotNil(suggestion)
        XCTAssertEqual(suggestion?.kind, .nextWord)
        XCTAssertEqual(suggestion?.insertText, "quick")
    }

    func testCapitalizesAfterPeriod() {
        let model = LanguageModel()
        model.train(on: "end. hello world")
        let expectation = XCTestExpectation(description: "training completes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { expectation.fulfill() }
        wait(for: [expectation], timeout: 2.0)
        let engine = PredictionEngine(model: model)
        let suggestion = engine.suggest(textBeforeCaret: "end. ", caretOffset: 5)
        if let s = suggestion {
            XCTAssertEqual(s.kind, .nextWord)
            let first = s.insertText.first
            XCTAssertTrue(first?.isUppercase ?? false, "Expected capitalized word, got: \(s.insertText)")
        }
    }

    func testCompletionPreferredOverCorrection() {
        let engine = makeEngine(words: [("application", 50), ("apple", 10)])
        let suggestion = engine.suggest(textBeforeCaret: "app", caretOffset: 3)
        XCTAssertEqual(suggestion?.kind, .completion)
    }

    func testEmptyTextReturnsNil() {
        let engine = makeEngine(words: [("hello", 10)])
        let suggestion = engine.suggest(textBeforeCaret: "", caretOffset: 0)
        XCTAssertNil(suggestion)
    }

    func testShortWordNotCorrected() {
        let engine = makeEngine(words: [("at", 100)])
        let suggestion = engine.suggest(textBeforeCaret: "ta", caretOffset: 2)
        XCTAssertNil(suggestion)
    }
}
