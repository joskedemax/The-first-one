import Foundation
import LocalLLMClient
import LocalLLMClientLlama

/// Available on-device models, smallest to largest.
enum JosTypeModel: String, CaseIterable {
    case gemma3_1b = "Gemma 3 1B"
    case gemma4_e2b = "Gemma 4 E2B"
    case gemma3_4b = "Gemma 3 4B"

    var hfRepo: String {
        switch self {
        case .gemma3_1b:  return "lmstudio-community/gemma-3-1B-it-qat-GGUF"
        case .gemma4_e2b: return "lmstudio-community/gemma-4-2B-it-qat-GGUF"
        case .gemma3_4b:  return "lmstudio-community/gemma-3-4B-it-qat-GGUF"
        }
    }

    var ggufFilename: String {
        switch self {
        case .gemma3_1b:  return "gemma-3-1B-it-QAT-Q4_0.gguf"
        case .gemma4_e2b: return "gemma-4-2B-it-QAT-Q4_0.gguf"
        case .gemma3_4b:  return "gemma-3-4B-it-QAT-Q4_0.gguf"
        }
    }

    var contextSize: Int {
        switch self {
        case .gemma3_1b:  return 2048
        case .gemma4_e2b: return 2048
        case .gemma3_4b:  return 4096
        }
    }
}

/// Manages a local LLM for high-quality text prediction. Downloads the model
/// on first use and persists it to Application Support.
@MainActor
final class LLMPredictor {

    enum Status: Equatable {
        case idle
        case downloading(progress: Double)
        case loading
        case ready
        case failed(String)
    }

    private(set) var status: Status = .idle
    var onStatusChange: ((Status) -> Void)?

    private var session: LLMSession?
    private var currentModel: JosTypeModel?
    private var generationTask: Task<String?, Never>?

    /// Load a model. Downloads from HuggingFace if not cached locally.
    func loadModel(_ model: JosTypeModel) async {
        if currentModel == model && status == .ready { return }
        currentModel = model
        session = nil

        setStatus(.downloading(progress: 0))

        do {
            let llmModel = LLMModel.llama(
                id: model.hfRepo,
                model: model.ggufFilename
            )
            setStatus(.loading)
            session = LLMSession(model: llmModel)
            setStatus(.ready)
            NSLog("JosType: model \(model.rawValue) loaded successfully.")
        } catch {
            let msg = error.localizedDescription
            NSLog("JosType: failed to load model: \(msg)")
            setStatus(.failed(msg))
        }
    }

    /// Generate a short inline completion for the given context.
    /// Returns the predicted continuation, or nil on failure/timeout.
    func predict(context: String, maxTokens: Int = 20) async -> String? {
        guard status == .ready, let session else { return nil }

        generationTask?.cancel()

        let prompt = buildPrompt(context: context)
        let task = Task<String?, Never> {
            var result = ""
            do {
                for try await token in session.streamResponse(to: prompt) {
                    if Task.isCancelled { return nil }
                    result += token
                    // Stop at sentence boundaries or newlines for inline suggestions.
                    if result.count >= maxTokens { break }
                    if result.contains("\n") {
                        result = String(result.prefix(while: { $0 != "\n" }))
                        break
                    }
                    if let last = result.last, ".!?".contains(last) && result.count > 3 {
                        break
                    }
                }
            } catch {
                if !Task.isCancelled {
                    NSLog("JosType: prediction error: \(error.localizedDescription)")
                }
                return nil
            }
            return result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : result
        }
        generationTask = task
        return await task.value
    }

    func cancelPendingPrediction() {
        generationTask?.cancel()
        generationTask = nil
    }

    var isReady: Bool { status == .ready }

    private func buildPrompt(context: String) -> String {
        // Use a completion-style prompt that tells the model to continue text.
        let trimmed = String(context.suffix(500))
        return """
        Continue the following text naturally. Output ONLY the continuation, \
        no explanations, no quotes. Keep it to one short sentence or phrase:

        \(trimmed)
        """
    }

    private func setStatus(_ s: Status) {
        status = s
        onStatusChange?(s)
    }
}
