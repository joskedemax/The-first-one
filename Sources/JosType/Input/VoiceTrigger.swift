import Foundation

enum VoiceTrigger {

    static func detect(in textBeforeCaret: String, caretOffset: Int) -> Range<Int>? {
        let trigger = Settings.shared.voiceTrigger
        guard !trigger.isEmpty, textBeforeCaret.hasSuffix(trigger) else { return nil }
        let start = caretOffset - trigger.count
        guard start >= 0 else { return nil }
        return start..<caretOffset
    }
}
