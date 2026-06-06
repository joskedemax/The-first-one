import AppKit
import ApplicationServices

/// The brain of the app: wires the focus tracker, prediction engine, overlay,
/// and key tap together. Uses the LLM for high-quality predictions when
/// available, falling back to the n-gram engine while the model loads.
@MainActor
final class Coordinator {

    private let ngramModel = LanguageModel()
    private let ngramEngine: PredictionEngine
    private let llmPredictor = LLMPredictor()
    private let focusTracker = FocusTracker()
    private let overlay = SuggestionOverlay()
    private let keyTap = KeyTap()

    private var active: (suggestion: Suggestion, snapshot: TextSnapshot)?

    private var lastTrainedText = ""
    private var lastProcessedSnapshot: (fullText: String, caretOffset: Int)?
    private var saveWorkItem: DispatchWorkItem?
    private var llmWorkItem: DispatchWorkItem?
    private let screenContext = ScreenContextProvider()
    private let speechTranscriber = SpeechTranscriber()
    private let invocationFilter = InvocationFilter()
    private let recordingIndicator = RecordingIndicator()
    private var isVoiceActive = false

    init() {
        ngramEngine = PredictionEngine(model: ngramModel)
    }

    // MARK: - Public

    var modelStatus: LLMPredictor.Status { llmPredictor.status }

    func start() {
        ngramModel.loadSeed()
        ngramModel.load()
        ngramEngine.refreshDictionary()

        focusTracker.onChange = { [weak self] snapshot in
            self?.handleSnapshot(snapshot)
        }
        keyTap.hasActiveSuggestion = { [weak self] in
            guard let self else { return false }
            return self.active != nil || self.isVoiceActive
        }
        keyTap.onAcceptWord = { [weak self] in self?.acceptNextWord() ?? false }
        keyTap.onAcceptAll = { [weak self] in self?.acceptAll() ?? false }
        keyTap.onDismiss = { [weak self] in
            guard let self else { return false }
            if self.isVoiceActive { return self.cancelVoice() }
            return self.dismissActive()
        }

        focusTracker.start()
        keyTap.start()

        // Start loading the selected model in the background.
        let selectedModel = Settings.shared.selectedModel
        Task { @MainActor in
            await llmPredictor.loadModel(selectedModel)
        }
    }

    func stop() {
        focusTracker.stop()
        keyTap.stop()
        llmPredictor.cancelPendingPrediction()
        llmPredictor.invalidateCache()
        speechTranscriber.cancelListening()
        clearSuggestion()
        lastProcessedSnapshot = nil
        ngramModel.save()
    }

    func setEnabled(_ enabled: Bool) {
        if enabled {
            focusTracker.start()
            keyTap.start()
        } else {
            clearSuggestion()
            llmPredictor.cancelPendingPrediction()
            focusTracker.stop()
            keyTap.stop()
        }
    }

    func switchModel(_ model: JosTypeModel) {
        Settings.shared.selectedModel = model
        Task { @MainActor in
            await llmPredictor.loadModel(model)
        }
    }

    // MARK: - Snapshot handling

    private func handleSnapshot(_ snapshot: TextSnapshot?) {
        guard Settings.shared.isEnabled, let snapshot else {
            clearSuggestion()
            return
        }
        guard !isVoiceActive else { return }

        // Deduplicate: skip if text and caret haven't changed.
        if let last = lastProcessedSnapshot,
           last.fullText == snapshot.fullText,
           last.caretOffset == snapshot.caretOffset {
            return
        }
        lastProcessedSnapshot = (snapshot.fullText, snapshot.caretOffset)

        let textBeforeCaret = String(snapshot.fullText.prefix(snapshot.caretOffset))

        // Check for ",,talk" voice trigger.
        if let triggerRange = VoiceTrigger.detect(in: textBeforeCaret, caretOffset: snapshot.caretOffset) {
            startVoiceCapture(element: snapshot.element, fullText: snapshot.fullText, triggerRange: triggerRange)
            return
        }

        scheduleTraining(for: snapshot.fullText)

        let ctx = Tokenizer.analyze(textBeforeCaret)
        if !ctx.currentPrefix.isEmpty && ctx.currentPrefix.count < Settings.shared.minPrefixLength {
            clearSuggestion()
            return
        }

        if let ngramSuggestion = ngramEngine.suggest(
            textBeforeCaret: textBeforeCaret,
            caretOffset: snapshot.caretOffset
        ) {
            present(ngramSuggestion, for: snapshot)
        }

        // Gate the (expensive) LLM continuation through the invocation filter
        // so we only fire it at sensible moments — not mid-word, not on thin
        // context, and not right after the user rejected a suggestion.
        if llmPredictor.isReady {
            let textAfterCaret = String(snapshot.fullText.dropFirst(snapshot.caretOffset))
            let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            if invocationFilter.shouldSuggestContinuation(
                textBeforeCaret: textBeforeCaret,
                textAfterCaret: textAfterCaret,
                bundleID: bundleID
            ) {
                scheduleLLMPrediction(textBeforeCaret: textBeforeCaret, snapshot: snapshot)
            }
        }
    }

    private func scheduleLLMPrediction(textBeforeCaret: String, snapshot: TextSnapshot) {
        llmWorkItem?.cancel()
        llmPredictor.cancelPendingPrediction()

        let visibleContext = screenContext.context()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                _ = await self.llmPredictor.predictStreaming(
                    context: textBeforeCaret,
                    screenContext: visibleContext,
                    maxTokens: 80
                ) { [weak self] partialText in
                    guard let self else { return }

                    // Only update if the user hasn't moved on.
                    let currentText = self.currentTextBeforeCaret()
                    guard currentText == textBeforeCaret else { return }

                    let suggestion = Suggestion(
                        kind: .nextWord,
                        insertText: partialText,
                        displayText: partialText,
                        replaceRange: snapshot.caretOffset..<snapshot.caretOffset
                    )

                    if self.overlay.isVisible, self.active != nil {
                        self.active = (suggestion, snapshot)
                        self.overlay.updateText(partialText)
                    } else {
                        self.present(suggestion, for: snapshot)
                    }
                }
            }
        }
        llmWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func currentTextBeforeCaret() -> String? {
        focusTracker.emitCurrentSnapshot()
        guard let elem = focusTracker.currentElement,
              let text = AccessibilityBridge.string(elem, kAXValueAttribute as String),
              let range = AccessibilityBridge.selectedRange(elem),
              range.length == 0 else { return nil }
        let caret = max(0, min(range.location, (text as NSString).length))
        let prefix = (text as NSString).substring(to: caret)
        return prefix
    }

    // MARK: - Present / accept / dismiss

    private func present(_ suggestion: Suggestion, for snapshot: TextSnapshot) {
        active = (suggestion, snapshot)

        let fieldFrame = AccessibilityBridge.frame(snapshot.element)
        let fontSize = AccessibilityBridge.fontSize(snapshot.element)
        let font = fontSize.map { NSFont.systemFont(ofSize: $0) }

        let caretUTF16 = utf16Caret(in: snapshot)
        let caretRange = CFRange(location: caretUTF16, length: 0)
        let probeRange = caretUTF16 > 0
            ? CFRange(location: caretUTF16 - 1, length: 1)
            : caretRange

        if let rect = AccessibilityBridge.boundsForRange(snapshot.element, caretRange),
           rect.height > 0 {
            overlay.show(suggestion, caretRect: rect, fieldFrame: fieldFrame, font: font)
        } else if let rect = AccessibilityBridge.boundsForRange(snapshot.element, probeRange),
                  rect.height > 0 {
            let adjusted = CGRect(x: rect.maxX, y: rect.origin.y,
                                  width: 0, height: rect.height)
            overlay.show(suggestion, caretRect: adjusted, fieldFrame: fieldFrame, font: font)
        } else if let rect = fallbackRect(for: snapshot.element) {
            overlay.show(suggestion, caretRect: rect, fieldFrame: fieldFrame, font: font)
        } else {
            overlay.hide()
        }
    }

    private func fallbackRect(for element: AXUIElement) -> CGRect? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, "AXFrame" as CFString, &value) == .success,
              let v = value, CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(v as! AXValue, .cgRect, &rect) else { return nil }
        if let primary = NSScreen.screens.first {
            rect.origin.y = primary.frame.maxY - rect.origin.y - rect.height
        }
        return CGRect(x: rect.minX + 4, y: rect.minY + 2, width: 0, height: rect.height)
    }

    private func utf16Caret(in snapshot: TextSnapshot) -> Int {
        let prefix = String(snapshot.fullText.prefix(snapshot.caretOffset))
        return (prefix as NSString).length
    }

    private func acceptAll() -> Bool {
        guard let (suggestion, snapshot) = active else { return false }
        let ok = TextInserter.apply(suggestion, to: snapshot.element, fullText: snapshot.fullText)
        clearSuggestion()
        lastProcessedSnapshot = nil
        invocationFilter.noteAccepted()
        if Settings.shared.isLearningEnabled {
            ngramModel.train(on: suggestion.insertText)
        }
        return ok
    }

    private func acceptNextWord() -> Bool {
        guard let (suggestion, snapshot) = active else { return false }
        let text = suggestion.insertText
        guard !text.isEmpty else { return false }

        // Find the end of the first word (include trailing space).
        let trimmed = text.drop(while: { $0 == " " })
        guard let spaceIdx = trimmed.firstIndex(of: " ") else {
            return acceptAll()
        }
        let wordEnd = trimmed.index(after: spaceIdx)
        let firstWord = String(text[text.startIndex..<wordEnd])
        let remaining = String(text[wordEnd...])

        // Insert just the first word.
        let wordSuggestion = Suggestion(
            kind: suggestion.kind,
            insertText: firstWord,
            displayText: firstWord,
            replaceRange: suggestion.replaceRange
        )
        let ok = TextInserter.apply(wordSuggestion, to: snapshot.element, fullText: snapshot.fullText)
        guard ok else { return false }
        lastProcessedSnapshot = nil

        if remaining.trimmingCharacters(in: .whitespaces).isEmpty {
            clearSuggestion()
        } else {
            // Update active suggestion with remaining text.
            let newCaretOffset = suggestion.replaceRange.upperBound + firstWord.count
            let newSnapshot = TextSnapshot(
                element: snapshot.element,
                fullText: snapshot.fullText + firstWord,
                caretOffset: newCaretOffset
            )
            let remainingSuggestion = Suggestion(
                kind: suggestion.kind,
                insertText: remaining,
                displayText: remaining,
                replaceRange: newCaretOffset..<newCaretOffset
            )
            active = (remainingSuggestion, newSnapshot)
            present(remainingSuggestion, for: newSnapshot)
        }

        invocationFilter.noteAccepted()
        if Settings.shared.isLearningEnabled {
            ngramModel.train(on: firstWord)
        }
        return true
    }

    private func dismissActive() -> Bool {
        guard active != nil else { return false }
        clearSuggestion()
        invocationFilter.noteRejected()
        return true
    }

    private func clearSuggestion() {
        active = nil
        overlay.hide()
    }

    // MARK: - Voice capture

    private func startVoiceCapture(element: AXUIElement, fullText: String, triggerRange: Range<Int>) {
        isVoiceActive = true
        clearSuggestion()
        lastProcessedSnapshot = nil

        // Delete ",,talk" from the field.
        let utf16Start = utf16Index(in: fullText, characterOffset: triggerRange.lowerBound)
        let utf16End = utf16Index(in: fullText, characterOffset: triggerRange.upperBound)
        let cfRange = CFRange(location: utf16Start, length: utf16End - utf16Start)
        AccessibilityBridge.setSelectedRange(element, cfRange)
        AccessibilityBridge.replaceSelectedText(element, with: "")

        // Show floating recording pill near caret.
        if let rect = AccessibilityBridge.boundsForRange(element, CFRange(location: utf16Start, length: 0)) {
            recordingIndicator.show(near: rect)
        }

        // Bias recognition with words from the screen context.
        let ctx = screenContext.context()
        if let ctx, !ctx.isEmpty {
            let words = extractContextualWords(from: ctx)
            speechTranscriber.contextualStrings = words
        } else {
            speechTranscriber.contextualStrings = []
        }

        speechTranscriber.onPartialResult = { [weak self] partial in
            self?.recordingIndicator.updatePartialText(partial)
        }

        speechTranscriber.onTranscription = { [weak self] text in
            guard let self else { return }
            guard !text.isEmpty else {
                self.isVoiceActive = false
                self.recordingIndicator.hide()
                self.lastProcessedSnapshot = nil
                return
            }
            self.recordingIndicator.showProcessing()

            if self.llmPredictor.isReady {
                Task { @MainActor in
                    let cleaned = await self.llmPredictor.cleanTranscription(
                        raw: text, screenContext: ctx
                    )
                    self.isVoiceActive = false
                    self.recordingIndicator.hide()
                    if let focused = AccessibilityBridge.focusedElement() {
                        AccessibilityBridge.replaceSelectedText(focused, with: cleaned ?? text)
                    }
                    self.lastProcessedSnapshot = nil
                }
            } else {
                self.isVoiceActive = false
                self.recordingIndicator.hide()
                if let focused = AccessibilityBridge.focusedElement() {
                    AccessibilityBridge.replaceSelectedText(focused, with: text)
                }
                self.lastProcessedSnapshot = nil
            }
        }
        speechTranscriber.startListening()
    }

    private func cancelVoice() -> Bool {
        guard isVoiceActive else { return false }
        speechTranscriber.cancelListening()
        isVoiceActive = false
        recordingIndicator.hide()
        lastProcessedSnapshot = nil
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
                if result.count >= 50 { break }
            }
        }
        return result
    }

    private func utf16Index(in string: String, characterOffset: Int) -> Int {
        let clamped = max(0, min(characterOffset, string.count))
        let idx = string.index(string.startIndex, offsetBy: clamped)
        return string.utf16.distance(from: string.startIndex, to: idx)
    }

    // MARK: - Training

    private func scheduleTraining(for text: String) {
        guard Settings.shared.isLearningEnabled else { return }
        guard text != lastTrainedText else { return }
        lastTrainedText = text

        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.ngramModel.train(on: text)
            self.ngramEngine.refreshDictionary()
            self.ngramModel.save()
        }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: work)
    }
}
