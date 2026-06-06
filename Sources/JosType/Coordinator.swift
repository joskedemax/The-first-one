import AppKit
import ApplicationServices

/// The brain of the app: wires the focus tracker, prediction engine, overlay,
/// and key tap together. Uses the LLM for high-quality predictions when
/// available, falling back to the n-gram engine while the model loads.
final class Coordinator {

    private let ngramModel = LanguageModel()
    private let ngramEngine: PredictionEngine
    private let llmPredictor = LLMPredictor()
    private let focusTracker = FocusTracker()
    private let overlay = SuggestionOverlay()
    private let keyTap = KeyTap()

    private var active: (suggestion: Suggestion, snapshot: TextSnapshot)?

    private var lastTrainedText = ""
    private var saveWorkItem: DispatchWorkItem?
    /// Debounce for LLM predictions — wait until user pauses typing.
    private var llmWorkItem: DispatchWorkItem?

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
        keyTap.hasActiveSuggestion = { [weak self] in self?.active != nil }
        keyTap.onAccept = { [weak self] in self?.acceptActive() ?? false }
        keyTap.onDismiss = { [weak self] in self?.dismissActive() ?? false }

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
        clearSuggestion()
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

        scheduleTraining(for: snapshot.fullText)

        let textBeforeCaret = String(snapshot.fullText.prefix(snapshot.caretOffset))
        let ctx = Tokenizer.analyze(textBeforeCaret)
        if !ctx.currentPrefix.isEmpty && ctx.currentPrefix.count < Settings.shared.minPrefixLength {
            clearSuggestion()
            return
        }

        // Immediately show n-gram suggestion for responsiveness.
        if let ngramSuggestion = ngramEngine.suggest(
            textBeforeCaret: textBeforeCaret,
            caretOffset: snapshot.caretOffset
        ) {
            present(ngramSuggestion, for: snapshot)
        }

        // If the LLM is ready, schedule a higher-quality prediction after a
        // short pause (so we don't run inference on every keystroke).
        if llmPredictor.isReady {
            scheduleLLMPrediction(textBeforeCaret: textBeforeCaret, snapshot: snapshot)
        }
    }

    private func scheduleLLMPrediction(textBeforeCaret: String, snapshot: TextSnapshot) {
        llmWorkItem?.cancel()
        llmPredictor.cancelPendingPrediction()

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                guard let result = await self.llmPredictor.predict(
                    context: textBeforeCaret, maxTokens: 25
                ) else { return }

                // Only show if the user hasn't moved on (snapshot still matches).
                let currentText = self.currentTextBeforeCaret()
                guard currentText == textBeforeCaret else { return }

                let suggestion = Suggestion(
                    kind: .nextWord,
                    insertText: result,
                    displayText: result,
                    replaceRange: snapshot.caretOffset..<snapshot.caretOffset
                )
                self.present(suggestion, for: snapshot)
            }
        }
        llmWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
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

        let caretUTF16 = utf16Caret(in: snapshot)
        let caretRange = CFRange(location: caretUTF16, length: 0)
        let probeRange = caretUTF16 > 0
            ? CFRange(location: caretUTF16 - 1, length: 1)
            : caretRange

        if let rect = AccessibilityBridge.boundsForRange(snapshot.element, caretRange),
           rect.height > 0 {
            overlay.show(suggestion, caretRect: rect)
        } else if let rect = AccessibilityBridge.boundsForRange(snapshot.element, probeRange),
                  rect.height > 0 {
            let adjusted = CGRect(x: rect.maxX, y: rect.origin.y,
                                  width: 0, height: rect.height)
            overlay.show(suggestion, caretRect: adjusted)
        } else if let rect = fallbackRect(for: snapshot.element) {
            overlay.show(suggestion, caretRect: rect)
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

    private func acceptActive() -> Bool {
        guard let (suggestion, snapshot) = active else { return false }
        let ok = TextInserter.apply(suggestion, to: snapshot.element, fullText: snapshot.fullText)
        clearSuggestion()
        if Settings.shared.isLearningEnabled {
            ngramModel.train(on: suggestion.insertText)
        }
        return ok
    }

    private func dismissActive() -> Bool {
        guard active != nil else { return false }
        clearSuggestion()
        return true
    }

    private func clearSuggestion() {
        active = nil
        overlay.hide()
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
