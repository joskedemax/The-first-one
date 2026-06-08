import AppKit
import ApplicationServices

@MainActor
final class VoiceCaptureController {

    private(set) var isActive = false

    private let speechTranscriber = SpeechTranscriber()
    private let recordingIndicator = RecordingIndicator()

    private static let errorDisplayDuration: TimeInterval = 2.0
    private static let maxContextualWords = 50

    var onFinished: (() -> Void)?

    func start(
        element: AXUIElement,
        fullText: String,
        triggerRange: Range<Int>,
        screenContext: String?,
        llmPredictor: LLMPredictor
    ) {
        isActive = true

        let utf16Start = AccessibilityBridge.utf16Offset(in: fullText, characterOffset: triggerRange.lowerBound)
        let utf16End = AccessibilityBridge.utf16Offset(in: fullText, characterOffset: triggerRange.upperBound)
        let cfRange = CFRange(location: utf16Start, length: utf16End - utf16Start)
        if !AccessibilityBridge.setSelectedRange(element, cfRange) {
            NSLog("JosType: failed to select trigger phrase range for deletion")
        }
        if !AccessibilityBridge.replaceSelectedText(element, with: "") {
            NSLog("JosType: failed to delete trigger phrase from field")
        }

        if let rect = AccessibilityBridge.boundsForRange(element, CFRange(location: utf16Start, length: 0)),
           rect.height > 0 {
            recordingIndicator.show(near: rect)
        }

        if let ctx = screenContext, !ctx.isEmpty {
            speechTranscriber.contextualStrings = extractContextualWords(from: ctx)
        } else {
            speechTranscriber.contextualStrings = []
        }

        speechTranscriber.onPartialResult = { [weak self] partial in
            self?.recordingIndicator.updatePartialText(partial)
        }

        let ctx = screenContext
        speechTranscriber.onTranscription = { [weak self] text in
            guard let self else { return }
            guard !text.isEmpty else {
                self.recordingIndicator.updatePartialText("Voice capture failed")
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(Self.errorDisplayDuration))
                    self?.isActive = false
                    self?.recordingIndicator.hide()
                    self?.onFinished?()
                }
                return
            }
            self.recordingIndicator.showProcessing()

            if llmPredictor.isReady {
                Task { @MainActor in
                    let cleaned = await llmPredictor.cleanTranscription(
                        raw: text, screenContext: ctx
                    )
                    self.isActive = false
                    self.recordingIndicator.hide()
                    if let focused = AccessibilityBridge.focusedElement() {
                        AccessibilityBridge.replaceSelectedText(focused, with: cleaned ?? text)
                    }
                    self.onFinished?()
                }
            } else {
                self.isActive = false
                self.recordingIndicator.hide()
                if let focused = AccessibilityBridge.focusedElement() {
                    AccessibilityBridge.replaceSelectedText(focused, with: text)
                }
                self.onFinished?()
            }
        }
        speechTranscriber.startListening()
    }

    func cancel() -> Bool {
        guard isActive else { return false }
        speechTranscriber.cancelListening()
        isActive = false
        recordingIndicator.hide()
        onFinished?()
        return true
    }

    private func extractContextualWords(from context: String) -> [String] {
        let words = context.components(separatedBy: .whitespacesAndNewlines)
        var unique = Set<String>()
        var result: [String] = []
        for word in words {
            let cleaned = word.trimmingCharacters(in: .punctuationCharacters)
            if cleaned.count >= 4 && cleaned.first?.isUppercase == true && unique.insert(cleaned).inserted {
                result.append(cleaned)
                if result.count >= Self.maxContextualWords { break }
            }
        }
        return result
    }

}
