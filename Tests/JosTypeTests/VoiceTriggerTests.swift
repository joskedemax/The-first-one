import XCTest
@testable import JosType

final class VoiceTriggerTests: XCTestCase {

    private var originalTrigger: String?

    override func setUp() {
        super.setUp()
        originalTrigger = UserDefaults.standard.string(forKey: "jostype.voiceTrigger")
        UserDefaults.standard.set(",,talk", forKey: "jostype.voiceTrigger")
    }

    override func tearDown() {
        if let original = originalTrigger {
            UserDefaults.standard.set(original, forKey: "jostype.voiceTrigger")
        } else {
            UserDefaults.standard.removeObject(forKey: "jostype.voiceTrigger")
        }
        super.tearDown()
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
