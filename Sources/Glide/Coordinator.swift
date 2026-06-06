import AppKit
import ApplicationServices

/// The brain of the app: wires the focus tracker, prediction engine, overlay,
/// and key tap together. Owns the "currently shown suggestion" state.
final class Coordinator {

    private let model = LanguageModel()
    private let engine: PredictionEngine
    private let focusTracker = FocusTracker()
    private let overlay = SuggestionOverlay()
    private let keyTap = KeyTap()

    /// State for the suggestion that's currently on screen.
    private var active: (suggestion: Suggestion, snapshot: TextSnapshot)?

    /// Buffer of recently typed text awaiting a training pass.
    private var trainingBuffer = ""
    private var lastTrainedText = ""
    private var saveWorkItem: DispatchWorkItem?

    init() {
        engine = PredictionEngine(model: model)
    }

    // MARK: - Lifecycle

    func start() {
        model.loadSeed()
        model.load()
        engine.refreshDictionary()

        focusTracker.onChange = { [weak self] snapshot in
            self?.handleSnapshot(snapshot)
        }
        keyTap.hasActiveSuggestion = { [weak self] in self?.active != nil }
        keyTap.onAccept = { [weak self] in self?.acceptActive() ?? false }
        keyTap.onDismiss = { [weak self] in self?.dismissActive() ?? false }

        focusTracker.start()
        keyTap.start()
    }

    func stop() {
        focusTracker.stop()
        keyTap.stop()
        clearSuggestion()
        model.save()
    }

    /// Called when the user toggles Glide off/on from the menu.
    func setEnabled(_ enabled: Bool) {
        if enabled {
            focusTracker.start()
            keyTap.start()
        } else {
            clearSuggestion()
            focusTracker.stop()
            keyTap.stop()
        }
    }

    // MARK: - Snapshot handling

    private func handleSnapshot(_ snapshot: TextSnapshot?) {
        guard Settings.shared.isEnabled, let snapshot else {
            clearSuggestion()
            return
        }

        // Opportunistically learn from the field's text.
        scheduleTraining(for: snapshot.fullText)

        let textBeforeCaret = String(snapshot.fullText.prefix(snapshot.caretOffset))

        // Respect the minimum-prefix setting for completions.
        let ctx = Tokenizer.analyze(textBeforeCaret)
        if !ctx.currentPrefix.isEmpty && ctx.currentPrefix.count < Settings.shared.minPrefixLength {
            clearSuggestion()
            return
        }

        guard let suggestion = engine.suggest(
            textBeforeCaret: textBeforeCaret,
            caretOffset: snapshot.caretOffset
        ) else {
            clearSuggestion()
            return
        }

        present(suggestion, for: snapshot)
    }

    private func present(_ suggestion: Suggestion, for snapshot: TextSnapshot) {
        active = (suggestion, snapshot)

        // Locate the caret on screen to anchor the ghost text.
        let caretRange = CFRange(location: utf16Caret(in: snapshot), length: 0)
        if let rect = AccessibilityBridge.boundsForRange(snapshot.element, caretRange),
           rect.width >= 0, rect.height > 0 {
            overlay.show(suggestion, caretRect: rect)
        } else if let rect = fallbackRect(for: snapshot.element) {
            overlay.show(suggestion, caretRect: rect)
        } else {
            // Can't place it; keep the suggestion live for Tab but draw nothing.
            overlay.hide()
        }
    }

    /// A coarse fallback anchor: the bottom-left of the focused element's frame.
    private func fallbackRect(for element: AXUIElement) -> CGRect? {
        // Some elements expose a frame via kAXFrameAttribute (not universal).
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

    // MARK: - Accept / dismiss

    private func acceptActive() -> Bool {
        guard let (suggestion, snapshot) = active else { return false }
        let ok = TextInserter.apply(suggestion, to: snapshot.element, fullText: snapshot.fullText)
        clearSuggestion()
        // The accepted text is good training signal.
        if Settings.shared.isLearningEnabled {
            model.train(on: suggestion.insertText)
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

    /// Debounced training: when the field text settles, learn the delta and
    /// periodically persist + refresh the typo dictionary.
    private func scheduleTraining(for text: String) {
        guard Settings.shared.isLearningEnabled else { return }
        guard text != lastTrainedText else { return }
        lastTrainedText = text

        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.model.train(on: text)
            self.engine.refreshDictionary()
            self.model.save()
        }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: work)
    }
}
