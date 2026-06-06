import Foundation
import MLXLLM
import MLXLMCommon
import MLXHuggingFace
import HuggingFace
import Tokenizers

/// Available on-device models, smallest to largest.
enum JosTypeModel: String, CaseIterable {
    case gemma3_1b = "Gemma 3 1B"

    var registryConfig: ModelConfiguration {
        switch self {
        case .gemma3_1b: return LLMRegistry.gemma3_1B_qat_4bit
        }
    }
}

/// Manages a local LLM for high-quality text prediction using Apple MLX.
/// Downloads the model from HuggingFace on first use and caches it locally.
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

    private var modelContainer: ModelContainer?
    private var chatSession: ChatSession?
    private var currentModel: JosTypeModel?
    private var generationTask: Task<String?, Never>?

    func loadModel(_ model: JosTypeModel) async {
        if currentModel == model && status == .ready { return }
        currentModel = model
        modelContainer = nil
        chatSession = nil

        setStatus(.loading)

        do {
            let container = try await #huggingFaceLoadModelContainer(
                configuration: model.registryConfig
            )
            modelContainer = container
            chatSession = ChatSession(container)
            setStatus(.ready)
            NSLog("JosType: model \(model.rawValue) loaded successfully.")
        } catch {
            let msg = error.localizedDescription
            NSLog("JosType: failed to load model: \(msg)")
            setStatus(.failed(msg))
        }
    }

    func predict(context: String, screenContext: String? = nil, maxTokens: Int = 50) async -> String? {
        guard status == .ready, let session = chatSession else { return nil }

        generationTask?.cancel()

        let prompt = buildPrompt(context: context, screenContext: screenContext)
        let task = Task<String?, Never> {
            do {
                let response = try await session.respond(to: prompt)
                if Task.isCancelled { return nil }

                let cleaned = cleanResponse(response, maxLength: 150)
                return cleaned.isEmpty ? nil : cleaned
            } catch {
                if !Task.isCancelled {
                    NSLog("JosType: prediction error: \(error.localizedDescription)")
                }
                return nil
            }
        }
        generationTask = task
        return await task.value
    }

    func cancelPendingPrediction() {
        generationTask?.cancel()
        generationTask = nil
    }

    var isReady: Bool { status == .ready }

    func cleanTranscription(raw: String, screenContext: String?) async -> String? {
        guard status == .ready, let session = chatSession else { return nil }
        var prompt = ""
        if let sc = screenContext, !sc.isEmpty {
            prompt += "Context from the user's screen:\n\(String(sc.prefix(1500)))\n\n"
        }
        prompt += """
        Clean up this voice transcription for insertion into a text field. \
        Fix grammar, remove filler words (um, uh, like), fix punctuation, \
        and use correct capitalization. Use any technical terms or names from \
        the screen context if they match what was spoken. \
        Output ONLY the cleaned text, nothing else:

        \(raw)
        """
        do {
            let response = try await session.respond(to: prompt)
            let cleaned = response.trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? nil : cleaned
        } catch {
            NSLog("JosType: transcription cleanup error: \(error.localizedDescription)")
            return nil
        }
    }

    private func buildPrompt(context: String, screenContext: String?) -> String {
        var parts: [String] = []
        if let sc = screenContext, !sc.isEmpty {
            parts.append("Visible on screen for reference:\n\(String(sc.prefix(2000)))")
        }
        let trimmed = String(context.suffix(500))
        parts.append("""
        Continue the following text naturally. Output ONLY the continuation, \
        no explanations, no quotes. Write one or two complete sentences that \
        flow naturally from what was written:

        \(trimmed)
        """)
        return parts.joined(separator: "\n\n")
    }

    private func cleanResponse(_ response: String, maxLength: Int) -> String {
        var result = response.trimmingCharacters(in: .whitespacesAndNewlines)

        if let newlineIdx = result.firstIndex(of: "\n") {
            result = String(result[result.startIndex..<newlineIdx])
        }

        if result.count > maxLength {
            let prefix = String(result.prefix(maxLength))
            if let lastSpace = prefix.lastIndex(of: " ") {
                result = String(prefix[prefix.startIndex..<lastSpace])
            } else {
                result = prefix
            }
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func setStatus(_ s: Status) {
        status = s
        onStatusChange?(s)
    }
}
