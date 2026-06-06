import Foundation

enum VoiceTrigger {

    static let trigger = ",,talk"

    static func detect(in textBeforeCaret: String, caretOffset: Int) -> Range<Int>? {
        guard textBeforeCaret.hasSuffix(trigger) else { return nil }
        let start = caretOffset - trigger.count
        guard start >= 0 else { return nil }
        return start..<caretOffset
    }
}
