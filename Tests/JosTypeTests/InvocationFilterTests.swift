import XCTest
@testable import JosType

@MainActor
final class InvocationFilterTests: XCTestCase {

    func testRejectsThinContext() {
        let filter = InvocationFilter()
        let result = filter.shouldSuggestContinuation(
            textBeforeCaret: "hi", textAfterCaret: "", bundleID: "com.test"
        )
        XCTAssertFalse(result)
    }

    func testRejectsMidWord() {
        let filter = InvocationFilter()
        let result = filter.shouldSuggestContinuation(
            textBeforeCaret: "the quick brown fox",
            textAfterCaret: "jumps",
            bundleID: "com.test"
        )
        XCTAssertFalse(result)
    }

    func testAllowsAtWordBoundary() {
        let filter = InvocationFilter()
        let result = filter.shouldSuggestContinuation(
            textBeforeCaret: "the quick brown fox ",
            textAfterCaret: "",
            bundleID: "com.test"
        )
        XCTAssertTrue(result)
    }

    func testAllowsBeforeClosingPunctuation() {
        let filter = InvocationFilter()
        let result = filter.shouldSuggestContinuation(
            textBeforeCaret: "the quick brown fox",
            textAfterCaret: ")",
            bundleID: "com.test"
        )
        XCTAssertTrue(result)
    }

    func testCooldownAfterRejection() {
        let filter = InvocationFilter()
        filter.baseCooldown = 10.0

        _ = filter.shouldSuggestContinuation(
            textBeforeCaret: "hello world test", textAfterCaret: "", bundleID: "com.test"
        )
        filter.noteRejected()

        let result = filter.shouldSuggestContinuation(
            textBeforeCaret: "hello world test again",
            textAfterCaret: "",
            bundleID: "com.test"
        )
        XCTAssertFalse(result)
    }

    func testAcceptedClearsCooldown() {
        let filter = InvocationFilter()
        filter.baseCooldown = 10.0

        filter.noteRejected()
        filter.noteAccepted()

        let result = filter.shouldSuggestContinuation(
            textBeforeCaret: "hello world test again",
            textAfterCaret: "",
            bundleID: "com.test"
        )
        XCTAssertTrue(result)
    }

    func testResetOnAppSwitch() {
        let filter = InvocationFilter()
        filter.baseCooldown = 10.0

        _ = filter.shouldSuggestContinuation(
            textBeforeCaret: "hello world test", textAfterCaret: "", bundleID: "com.app1"
        )
        filter.noteRejected()

        let result = filter.shouldSuggestContinuation(
            textBeforeCaret: "hello world test again",
            textAfterCaret: "",
            bundleID: "com.app2"
        )
        XCTAssertTrue(result)
    }

    func testIsWordChar() {
        XCTAssertTrue(InvocationFilter.isWordChar("a"))
        XCTAssertTrue(InvocationFilter.isWordChar("5"))
        XCTAssertFalse(InvocationFilter.isWordChar(" "))
        XCTAssertFalse(InvocationFilter.isWordChar(")"))
    }
}
