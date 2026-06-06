import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import MLXHuggingFace
import HuggingFace
import Tokenizers

/// Available on-device models.
///
/// Base (pretrained) models are best for autocomplete — their training objective
/// *is* "continue the text", so they produce natural continuations instead of
/// chatty instruction-following. Instruct models are kept as options.
enum JosTypeModel: String, CaseIterable {
    case smollm3_3b_base = "SmolLM3 3B (base)"
    case qwen3_1_7b_base = "Qwen3 1.7B (base)"
    case gemma4_4b = "Gemma 4 4B (instruct)"
    case gemma3_1b = "Gemma 3 1B (instruct)"

    /// Whether this is a base/pretrained model (use raw completion, no chat template).
    var isBase: Bool {
        switch self {
        case .smollm3_3b_base, .qwen3_1_7b_base: return true
        case .gemma4_4b, .gemma3_1b: return false
        }
    }

    var registryConfig: ModelConfiguration {
        switch self {
        case .smollm3_3b_base: return ModelConfiguration(id: "mlx-community/SmolLM3-3B-Base-4bit")
        case .qwen3_1_7b_base: return ModelConfiguration(id: "mlx-community/Qwen3-1.7B-Base-4bit")
        case .gemma4_4b: return LLMRegistry.gemma4_e4b_it_4bit
        case .gemma3_1b: return LLMRegistry.gemma3_1B_qat_4bit
        }
    }

    var displayDescription: String {
        switch self {
        case .smollm3_3b_base: return "Best quality, ~1.8 GB"
        case .qwen3_1_7b_base: return "Fast & good, ~1 GB"
        case .gemma4_4b: return "Instruct, ~2.5 GB"
        case .gemma3_1b: return "Fastest, ~800 MB"
        }
    }
}

/// Manages a local LLM for high-quality text prediction using Apple MLX.
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

        let isBase = currentModel?.isBase ?? false

        let task = Task<String?, Never> {
            let raw: String?
            if isBase {
                let prompt = buildBasePrompt(context: context, screenContext: screenContext)
                raw = await self.rawComplete(container: container, prompt: prompt, maxTokens: maxTokens)
            } else {
                let prompt = buildInstructPrompt(context: context, screenContext: screenContext)
                do {
                    let session = ChatSession(container)
                    raw = try await session.respond(to: prompt)
                } catch {
                    if !Task.isCancelled {
                        NSLog("JosType: prediction error: \(error.localizedDescription)")
                    }
                    raw = nil
                }
            }

            guard let response = raw, !Task.isCancelled else { return nil }

            var cleaned = cleanResponse(response, maxLength: 200)
            guard cleaned.count >= 2 else { return nil }

            // Reject degenerate output that just echoes the context tail.
            let contextTail = String(context.suffix(40)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !contextTail.isEmpty && cleaned.lowercased() == contextTail.lowercased() { return nil }

            // Preserve a word boundary: if the user's text ends mid-token and the
            // completion starts with a word char, insert a leading space so we
            // don't jam words together ("the" + "store" -> "the store").
            if let last = context.last, !last.isWhitespace,
               let first = cleaned.first, (first.isLetter || first.isNumber) {
                cleaned = " " + cleaned
            }

            NSLog("JosType: prediction (\(cleaned.count) chars): \(cleaned.prefix(80))…")
            return cleaned
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
        Fix grammar and punctuation, remove filler words (um, uh, like), and use \
        correct capitalization. Resolve self-corrections (e.g. "5pm, actually 6pm" \
        becomes "6pm"). Never reword or add content that wasn't spoken — only fix \
        errors. Use technical terms or names from the screen context if they match. \
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

    // MARK: - Raw completion (base models)

    /// Generate a raw continuation without applying any chat template — the
    /// correct path for base/pretrained models.
    private func rawComplete(container: ModelContainer, prompt: String, maxTokens: Int) async -> String? {
        do {
            let text = try await container.perform { (context: ModelContext) -> String in
                let tokens = context.tokenizer.encode(text: prompt)
                let input = LMInput(tokens: MLXArray(tokens))
                let params = GenerateParameters(
                    maxTokens: maxTokens,
                    temperature: 0.3,
                    topP: 0.95,
                    repetitionPenalty: 1.1
                )
                var output = ""
                let stream = try MLXLMCommon.generate(
                    input: input, cache: nil, parameters: params, context: context
                )
                for await item in stream {
                    if case .chunk(let s) = item {
                        output += s
                        if output.count > 250 { break }
                    }
                }
                return output
            }
            return text
        } catch {
            NSLog("JosType: raw completion error: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Prompts

    /// For base models: just give the text to continue. Optionally prepend a
    /// short context paragraph so the continuation is informed by the screen.
    private func buildBasePrompt(context: String, screenContext: String?) -> String {
        let trimmed = String(context.suffix(600))
        if let sc = screenContext, !sc.isEmpty {
            let ctx = String(sc.prefix(800))
            return "\(ctx)\n\n\(trimmed)"
        }
        return trimmed
    }

    /// For instruct models: explicit instruction to continue.
    private func buildInstructPrompt(context: String, screenContext: String?) -> String {
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

        while result.hasPrefix("\"") || result.hasPrefix("'") || result.hasPrefix("`") {
            result = String(result.dropFirst())
        }
        while result.hasSuffix("\"") || result.hasSuffix("'") || result.hasSuffix("`") {
            result = String(result.dropLast())
        }

        // Take up to two sentences.
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
