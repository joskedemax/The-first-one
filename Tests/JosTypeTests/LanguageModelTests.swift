import XCTest
@testable import JosType

final class LanguageModelTests: XCTestCase {

    func testTrainUpdatesUnigrams() {
        let model = LanguageModel()
        model.train(on: "hello world hello")

        let expectation = XCTestExpectation(description: "barrier completes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            XCTAssertEqual(model.unigrams["hello"], 2)
            XCTAssertEqual(model.unigrams["world"], 1)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)
    }

    func testBigramCandidates() {
        let model = LanguageModel()
        model.train(on: "the quick brown fox the quick red car")

        let expectation = XCTestExpectation(description: "barrier completes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            let candidates = model.nextWordCandidates(prior: ["the"], limit: 5)
            let words = candidates.map(\.word)
            XCTAssertTrue(words.contains("quick"))
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)
    }

    func testTrigramCandidates() {
        let model = LanguageModel()
        model.train(on: "the quick brown the quick brown the quick red")

        let expectation = XCTestExpectation(description: "barrier completes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            let candidates = model.nextWordCandidates(prior: ["the", "quick"], limit: 5)
            let words = candidates.map(\.word)
            XCTAssertTrue(words.contains("brown"))
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)
    }

    func testEmptyTrainingIsNoop() {
        let model = LanguageModel()
        model.train(on: "")

        let expectation = XCTestExpectation(description: "barrier completes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            XCTAssertTrue(model.unigrams.isEmpty)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)
    }

    func testCompletionsForTrainedWords() {
        let model = LanguageModel()
        model.train(on: "application apple appetizer")

        let expectation = XCTestExpectation(description: "barrier completes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            let completions = model.completions(for: "app", limit: 5)
            let words = completions.map(\.word)
            XCTAssertTrue(words.contains("application"))
            XCTAssertTrue(words.contains("apple"))
            XCTAssertTrue(words.contains("appetizer"))
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)
    }
}
