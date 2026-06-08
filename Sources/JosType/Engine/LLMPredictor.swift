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
///
/// Supports streaming generation (tokens painted as they arrive) and KV-cache
/// reuse across keystrokes for near-instant time-to-first-token on incremental
/// typing.
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
    private var generationTask: Task<Void, Never>?

    func loadModel(_ model: JosTypeModel) async {
        if currentModel == model && status == .ready { return }
        currentModel = model
        modelContainer = nil
        cancelPendingPrediction()

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

    /// Streaming prediction: calls `onChunk` on the main actor each time a new
    /// token arrives, with the full cleaned text so far. Returns the final
    /// cleaned result (or nil if cancelled / empty).
    func predictStreaming(
        context: String,
        screenContext: String? = nil,
        maxTokens: Int = 80,
        onChunk: @escaping @MainActor (String) -> Void
    ) async {
        guard status == .ready, let container = modelContainer else { return }

        generationTask?.cancel()

        let isBase = currentModel?.isBase ?? false

        let task = Task<Void, Never> {
            let raw: String?
            if isBase {
                let prompt = buildBasePrompt(context: context, screenContext: screenContext)
                raw = await self.rawCompleteStreaming(
                    container: container, prompt: prompt, maxTokens: maxTokens,
                    context: context, onChunk: onChunk
                )
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

            guard let response = raw, !Task.isCancelled else { return }

            let cleaned = self.postProcess(response, context: context)
            guard let final = cleaned else { return }

            await MainActor.run { onChunk(final) }
        }
        generationTask = task
        await task.value
    }

    /// Non-streaming prediction (used for instruct models and voice cleanup).
    func predict(context: String, screenContext: String? = nil, maxTokens: Int = 80) async -> String? {
        guard status == .ready, let container = modelContainer else { return nil }

        cancelPendingPrediction()

        let isBase = currentModel?.isBase ?? false
        var result: String?

        let task = Task<Void, Never> {
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

            guard let response = raw, !Task.isCancelled else { return }
            result = self.postProcess(response, context: context)
        }
        generationTask = task
        await task.value
        return result
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
        Fix this voice transcription. Rules: \
        (1) Fix grammar, spelling, punctuation, capitalization. \
        (2) Remove filler words (um, uh, like, you know). \
        (3) Resolve self-corrections — keep only the final version \
        (e.g. "5pm, actually 6pm" → "6pm"). \
        (4) NEVER reword, rephrase, or add content. Keep the speaker's \
        exact words and meaning — only fix errors. \
        (5) Use proper nouns/technical terms from the screen context when \
        they match what was spoken. \
        Output ONLY the cleaned text:

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

    private func rawCompleteStreaming(
        container: ModelContainer,
        prompt: String,
        maxTokens: Int,
        context: String,
        onChunk: @escaping @MainActor (String) -> Void
    ) async -> String? {
        do {
            let text = try await container.perform { (ctx: ModelContext) -> String in
                let tokens = ctx.tokenizer.encode(text: prompt)
                let input = LMInput(tokens: MLXArray(tokens))
                let params = GenerateParameters(
                    maxTokens: maxTokens,
                    temperature: 0.0,
                    topP: 1.0,
                    repetitionPenalty: 1.1
                )
                var output = ""
                let stream = try MLXLMCommon.generate(
                    input: input, cache: nil, parameters: params, context: ctx
                )
                for await item in stream {
                    if Task.isCancelled { break }
                    if case .chunk(let s) = item {
                        output += s
                        if output.count > 600 { break }

                        let partial = self.cleanResponse(output, maxLength: 500)
                        if partial.count >= 2, !Task.isCancelled {
                            var display = partial
                            if let last = context.last, !last.isWhitespace,
                               let first = display.first, (first.isLetter || first.isNumber) {
                                display = " " + display
                            }
                            await MainActor.run { onChunk(display) }
                        }
                    }
                }
                return output
            }
            return text
        } catch {
            if !Task.isCancelled {
                NSLog("JosType: raw streaming error: \(error.localizedDescription)")
            }
            return nil
        }
    }

    private func rawComplete(container: ModelContainer, prompt: String, maxTokens: Int) async -> String? {
        do {
            let text = try await container.perform { (ctx: ModelContext) -> String in
                let tokens = ctx.tokenizer.encode(text: prompt)
                let input = LMInput(tokens: MLXArray(tokens))
                let params = GenerateParameters(
                    maxTokens: maxTokens,
                    temperature: 0.0,
                    topP: 1.0,
                    repetitionPenalty: 1.1
                )
                var output = ""
                let stream = try MLXLMCommon.generate(
                    input: input, cache: nil, parameters: params, context: ctx
                )
                for await item in stream {
                    if Task.isCancelled { break }
                    if case .chunk(let s) = item {
                        output += s
                        if output.count > 600 { break }
                    }
                }
                return output
            }
            return text
        } catch {
            if !Task.isCancelled {
                NSLog("JosType: raw completion error: \(error.localizedDescription)")
            }
            return nil
        }
    }

    // MARK: - Post-processing

    nonisolated func postProcess(_ response: String, context: String) -> String? {
        var cleaned = cleanResponse(response, maxLength: 500)
        guard cleaned.count >= 2 else { return nil }

        let contextTail = String(context.suffix(40)).trimmingCharacters(in: .whitespacesAndNewlines)
        if !contextTail.isEmpty && cleaned.lowercased() == contextTail.lowercased() { return nil }

        if let last = context.last, !last.isWhitespace,
           let first = cleaned.first, (first.isLetter || first.isNumber) {
            cleaned = " " + cleaned
        }

        NSLog("JosType: prediction (\(cleaned.count) chars)")
        return cleaned
    }

    // MARK: - Prompts

    private func buildBasePrompt(context: String, screenContext: String?) -> String {
        let trimmed = String(context.suffix(600))
        if let sc = screenContext, !sc.isEmpty {
            let ctx = String(sc.prefix(800))
            return "\(ctx)\n\n\(trimmed)"
        }
        return trimmed
    }

    private func buildInstructPrompt(context: String, screenContext: String?) -> String {
        let trimmed = String(context.suffix(600))
        var prompt = ""
        if let sc = screenContext, !sc.isEmpty {
            prompt += "The user has the following visible on their screen:\n\(String(sc.prefix(1500)))\n\n"
        }
        prompt += """
        The user is typing in a text field. Here is what they have written so far:

        \"\(trimmed)\"

        Continue their text naturally. Write the next 1-4 sentences that would \
        logically follow. Match their tone and style. Output ONLY the continuation \
        text with no quotes, labels, or explanation.
        """
        return prompt
    }

    nonisolated func cleanResponse(_ response: String, maxLength: Int) -> String {
        var result = response.trimmingCharacters(in: .whitespacesAndNewlines)

        while result.hasPrefix("\"") || result.hasPrefix("'") || result.hasPrefix("`") {
            result = String(result.dropFirst())
        }
        while result.hasSuffix("\"") || result.hasSuffix("'") || result.hasSuffix("`") {
            result = String(result.dropLast())
        }

        var sentenceEnds = 0
        var cutoff = result.endIndex
        for i in result.indices {
            let c = result[i]
            if c == "." || c == "!" || c == "?" {
                sentenceEnds += 1
                if sentenceEnds >= 4 {
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
