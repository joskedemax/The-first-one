import XCTest
@testable import JosType

final class VoiceTriggerTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.standard.set(",,talk", forKey: "jostype.voiceTrigger")
    }

    func testDetectsTriggerAtEnd() {
        let range = VoiceTrigger.detect(in: "hello ,,talk", caretOffset: 12)
        XCTAssertNotNil(range)
        XCTAssertEqual(range, 6..<12)
    }

    func testReturnsNilWhenNotPresent() {
        let range = VoiceTrigger.detect(in: "hello world", caretOffset: 11)
        XCTAssertNil(range)
    }

    func testReturnsNilOnEmptyText() {
        let range = VoiceTrigger.detect(in: "", caretOffset: 0)
        XCTAssertNil(range)
    }

    func testTriggerAtStart() {
        let range = VoiceTrigger.detect(in: ",,talk", caretOffset: 6)
        XCTAssertNotNil(range)
        XCTAssertEqual(range, 0..<6)
    }

    func testCustomTrigger() {
        UserDefaults.standard.set("//voice", forKey: "jostype.voiceTrigger")
        let range = VoiceTrigger.detect(in: "text //voice", caretOffset: 12)
        XCTAssertNotNil(range)
        XCTAssertEqual(range, 5..<12)
    }

    func testEmptyTriggerReturnsNil() {
        UserDefaults.standard.set("", forKey: "jostype.voiceTrigger")
        let range = VoiceTrigger.detect(in: ",,talk", caretOffset: 6)
        XCTAssertNil(range)
    }

    func testPartialTriggerNotDetected() {
        let range = VoiceTrigger.detect(in: ",,tal", caretOffset: 5)
        XCTAssertNil(range)
    }
}
