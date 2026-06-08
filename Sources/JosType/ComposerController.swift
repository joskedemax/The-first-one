import AppKit
import ApplicationServices

/// Drives the floating composer: opens it on the hotkey, captures the current
/// target, feeds typing through the prediction engines to paint ghost text, and
/// inserts the composed result into the chosen app.
@MainActor
final class ComposerController: NSObject {

    private let window = ComposerWindow()
    private let llmPredictor: LLMPredictor
    private let ngramEngine: PredictionEngine
    private let ngramModel: LanguageModel
    private let screenContext: ScreenContextProvider

    private var targets: [TargetApp] = []
    private var selectedTarget = 0
    private var capturedElement: AXUIElement?
    private var capturedPid: pid_t?

    private var llmTask: Task<Void, Never>?

    private static let llmDebounce: TimeInterval = 0.30
    private static let maxLLMTokens = 200

    init(
        llmPredictor: LLMPredictor,
        ngramEngine: PredictionEngine,
        ngramModel: LanguageModel,
        screenContext: ScreenContextProvider
    ) {
        self.llmPredictor = llmPredictor
        self.ngramEngine = ngramEngine
        self.ngramModel = ngramModel
        self.screenContext = screenContext
        super.init()

        window.textView.delegate = self
        window.textView.onSubmit = { [weak self] in self?.submit() }
        window.textView.onCancel = { [weak self] in self?.dismiss() }
        window.textView.onSelectTarget = { [weak self] oneBased in self?.selectTarget(oneBased - 1) }
        window.textView.onUserEdit = { [weak self] in self?.scheduleSuggestion() }
        window.onSelectChip = { [weak self] index in self?.selectTarget(index) }
    }

    // MARK: - Open / close

    func toggle() {
        window.isVisible ? dismiss() : open()
    }

    func open() {
        // Capture the destination BEFORE we take key focus.
        capturedElement = AccessibilityBridge.focusedElement()
        capturedPid = NSWorkspace.shared.frontmostApplication?.processIdentifier

        targets = TargetEnumerator.currentTargets(preferred: capturedPid)
        selectedTarget = 0

        window.textView.removeGhost()
        window.textView.string = ""
        window.setTargets(targets, selected: 0)
        window.show()

        screenContext.warmUp()
    }

    func dismiss() {
        llmTask?.cancel()
        llmTask = nil
        llmPredictor.cancelPendingPrediction()
        window.hide()
    }

    // MARK: - Targets

    private func selectTarget(_ index: Int) {
        guard targets.indices.contains(index) else { return }
        selectedTarget = index
        window.highlightChip(index)
    }

    // MARK: - Suggestions

    private func scheduleSuggestion() {
        llmTask?.cancel()
        llmPredictor.cancelPendingPrediction()

        let committed = window.textView.committedString
        let caret = committed.count

        // Instant n-gram ghost so something appears immediately.
        if let s = ngramEngine.suggest(textBeforeCaret: committed, caretOffset: caret),
           s.kind != .correction, !s.displayText.isEmpty {
            window.textView.showGhost(s.displayText)
        } else {
            window.textView.removeGhost()
        }
        window.refreshLayout()

        guard llmPredictor.isReady, committed.count >= 2 else { return }

        let visibleContext = screenContext.context()
        llmTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.llmDebounce))
            guard let self, !Task.isCancelled else { return }
            await self.llmPredictor.predictStreaming(
                context: committed,
                screenContext: visibleContext,
                maxTokens: Self.maxLLMTokens
            ) { [weak self] partial in
                guard let self else { return }
                // Ignore stale chunks if the user has typed on.
                guard self.window.textView.committedString == committed else { return }
                self.window.textView.showGhost(partial)
                self.window.refreshLayout()
            }
        }
    }

    // MARK: - Submit

    private func submit() {
        let text = window.textView.committedString.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = targets.indices.contains(selectedTarget) ? targets[selectedTarget] : nil
        let element = capturedElement
        dismiss()

        guard !text.isEmpty else { return }

        if Settings.shared.isLearningEnabled {
            ngramModel.train(on: text)
            ngramEngine.refreshDictionary()
            ngramModel.save()
        }

        TargetInserter.insert(text, pid: target?.pid, capturedElement: element)
    }
}

extension ComposerController: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        guard window.textView.textChangedShouldRecompute() else { return }
        scheduleSuggestion()
    }
}
