import AppKit
import ApplicationServices

/// The brain of the app. Owns the prediction engines and wires the global
/// hotkey to the floating composer (the single input surface where JosType's
/// autocomplete runs), and keeps the focus tracker alive for the ",,talk"
/// voice trigger and on-the-fly personalization.
@MainActor
final class Coordinator {

    private static let trainingSaveDelay: TimeInterval = 2.0

    private let ngramModel = LanguageModel()
    private let ngramEngine: PredictionEngine
    private let llmPredictor = LLMPredictor()
    private let focusTracker = FocusTracker()
    private let screenContext = ScreenContextProvider()
    private let voiceCapture = VoiceCaptureController()
    private let hotkey = HotkeyMonitor()
    private let composer: ComposerController

    private var lastTrainedText = ""
    private var saveWorkItem: DispatchWorkItem?

    init() {
        ngramEngine = PredictionEngine(model: ngramModel)
        composer = ComposerController(
            llmPredictor: llmPredictor,
            ngramEngine: ngramEngine,
            ngramModel: ngramModel,
            screenContext: screenContext
        )
    }

    // MARK: - Public

    var modelStatus: LLMPredictor.Status { llmPredictor.status }
    var onModelStatusChange: ((LLMPredictor.Status) -> Void)? {
        get { llmPredictor.onStatusChange }
        set { llmPredictor.onStatusChange = newValue }
    }

    func start() {
        ngramModel.loadSeed()
        ngramModel.load()
        ngramEngine.refreshDictionary()

        focusTracker.onChange = { [weak self] snapshot in
            self?.handleSnapshot(snapshot)
        }
        hotkey.onDoubleTapControl = { [weak self] in
            self?.composer.toggle()
        }

        focusTracker.start()
        hotkey.start()
        screenContext.warmUp()

        let selectedModel = Settings.shared.selectedModel
        Task { @MainActor in
            await llmPredictor.loadModel(selectedModel)
        }
    }

    func stop() {
        focusTracker.stop()
        hotkey.stop()
        composer.dismiss()
        llmPredictor.cancelPendingPrediction()
        _ = voiceCapture.cancel()
        saveWorkItem?.cancel()
        saveWorkItem = nil
        ngramModel.save()
    }

    func setEnabled(_ enabled: Bool) {
        if enabled {
            focusTracker.start()
            hotkey.start()
        } else {
            composer.dismiss()
            llmPredictor.cancelPendingPrediction()
            saveWorkItem?.cancel()
            saveWorkItem = nil
            focusTracker.stop()
            hotkey.stop()
        }
    }

    func switchModel(_ model: JosTypeModel) {
        Settings.shared.selectedModel = model
        Task { @MainActor in
            await llmPredictor.loadModel(model)
        }
    }

    /// Open the composer from a menu action.
    func openComposer() {
        composer.open()
    }

    // MARK: - Snapshot handling (voice trigger + personalization only)

    private func handleSnapshot(_ snapshot: TextSnapshot?) {
        guard Settings.shared.isEnabled, let snapshot else { return }
        guard !voiceCapture.isActive else { return }

        let textBeforeCaret = String(snapshot.fullText.prefix(snapshot.caretOffset))

        // ",,talk" voice trigger still works inline in any field.
        if let triggerRange = VoiceTrigger.detect(in: textBeforeCaret, caretOffset: snapshot.caretOffset) {
            startVoiceCapture(element: snapshot.element, fullText: snapshot.fullText, triggerRange: triggerRange)
            return
        }

        scheduleTraining(for: snapshot.fullText)
    }

    // MARK: - Voice capture

    private func startVoiceCapture(element: AXUIElement, fullText: String, triggerRange: Range<Int>) {
        voiceCapture.start(
            element: element,
            fullText: fullText,
            triggerRange: triggerRange,
            screenContext: screenContext.context(),
            llmPredictor: llmPredictor
        )
    }

    // MARK: - Training

    private func scheduleTraining(for text: String) {
        guard Settings.shared.isLearningEnabled else { return }
        guard text != lastTrainedText else { return }
        lastTrainedText = text

        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.ngramModel.train(on: text)
                self.ngramEngine.refreshDictionary()
                self.ngramModel.save()
            }
        }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.trainingSaveDelay, execute: work)
    }
}
