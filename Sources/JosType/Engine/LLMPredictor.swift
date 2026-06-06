import Foundation
import MLXLLM
import MLXLMCommon
import MLXHuggingFace
import HuggingFace
import Tokenizers

enum JosTypeModel: String, CaseIterable {
    case gemma4_4b = "Gemma 4 4B"
    case smollm3_3b = "SmolLM3 3B"
    case gemma3_1b = "Gemma 3 1B"

    var registryConfig: ModelConfiguration {
        switch self {
        case .gemma4_4b: return LLMRegistry.gemma4_e4b_it_4bit
        case .smollm3_3b: return LLMRegistry.smollm3_3b_4bit
        case .gemma3_1b: return LLMRegistry.gemma3_1B_qat_4bit
        }
    }

    var displayDescription: String {
        switch self {
        case .gemma4_4b: return "Best quality, ~2.5 GB"
        case .smollm3_3b: return "Good quality, ~1.8 GB"
        case .gemma3_1b: return "Fastest, ~800 MB"
        }
    }
}

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
    private var currentModel: JosTypeModel?
    private var generationTask: Task<String?, Never>?

    func loadModel(_ model: JosTypeModel) async {
        if currentModel == model && status == .ready { return }
        currentModel = model
        modelContainer = nil

        setStatus(.loading)

        do {
            let container = try await #huggingFaceLoadModelContainer(
                configuration: model.registryConfig
            )
            modelContainer = container
            setStatus(.ready)
            NSLog("JosType: model \(model.rawValue) loaded successfully.")
        } catch {
            let msg = error.localizedDescription
            NSLog("JosType: failed to load model: \(msg)")
            setStatus(.failed(msg))
        }
    }

    func predict(context: String, screenContext: String? = nil, maxTokens: Int = 80) async -> String? {
        guard status == .ready, let container = modelContainer else { return nil }

        generationTask?.cancel()

        let prompt = buildPrompt(context: context, screenContext: screenContext)

        let task = Task<String?, Never> {
            do {
                // Use a fresh ChatSession each time to avoid history accumulation.
                let session = ChatSession(container)
                let response = try await session.respond(to: prompt)
                if Task.isCancelled { return nil }

                let cleaned = cleanResponse(response, maxLength: 200)
                // Reject degenerate output: too short, or just echoes the context tail.
                guard cleaned.count >= 2 else { return nil }
                let contextTail = String(context.suffix(40)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !contextTail.isEmpty && cleaned.lowercased() == contextTail.lowercased() { return nil }
                NSLog("JosType: prediction (\(cleaned.count) chars): \(cleaned.prefix(80))…")
                return cleaned
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
        guard status == .ready, let container = modelContainer else { return nil }
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
            let session = ChatSession(container)
            let response = try await session.respond(to: prompt)
            let cleaned = response.trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? nil : cleaned
        } catch {
            NSLog("JosType: transcription cleanup error: \(error.localizedDescription)")
            return nil
        }
    }

    private func buildPrompt(context: String, screenContext: String?) -> String {
        let trimmed = String(context.suffix(600))

        var prompt = ""
        if let sc = screenContext, !sc.isEmpty {
            prompt += "The user has the following visible on their screen:\n\(String(sc.prefix(1500)))\n\n"
        }
        prompt += """
        The user is typing in a text field. Here is what they have written so far:

        \"\(trimmed)\"

        Continue their text naturally. Write the next 1-2 sentences that would \
        logically follow. Match their tone and style. Output ONLY the continuation \
        text with no quotes, labels, or explanation.
        """
        return prompt
    }

    private func cleanResponse(_ response: String, maxLength: Int) -> String {
        var result = response.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove any leading quotes the model may have added.
        while result.hasPrefix("\"") || result.hasPrefix("'") || result.hasPrefix("`") {
            result = String(result.dropFirst())
        }
        while result.hasSuffix("\"") || result.hasSuffix("'") || result.hasSuffix("`") {
            result = String(result.dropLast())
        }

        // Take up to two sentences (stop at second sentence-ending punctuation).
        var sentenceEnds = 0
        var cutoff = result.endIndex
        for i in result.indices {
            let c = result[i]
            if c == "." || c == "!" || c == "?" {
                sentenceEnds += 1
                if sentenceEnds >= 2 {
                    cutoff = result.index(after: i)
                    break
                }
            }
        }
        result = String(result[result.startIndex..<cutoff])

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
