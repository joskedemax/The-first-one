import Foundation
import Speech
import AVFoundation

@MainActor
final class SpeechTranscriber {

    enum State { case idle, listening, processing }

    private(set) var state: State = .idle
    var onTranscription: ((String) -> Void)?
    var onPartialResult: ((String) -> Void)?

    /// Words/phrases from the screen context that bias recognition accuracy.
    var contextualStrings: [String] = []

    private let audioEngine = AVAudioEngine()
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var silenceTimer: Timer?
    private let silenceTimeout: TimeInterval = 2.0
    private var lastTranscript = ""

    func startListening() {
        guard state == .idle else { return }

        let recognizer = SFSpeechRecognizer()
        guard let recognizer, recognizer.isAvailable else {
            NSLog("JosType: speech recognizer unavailable.")
            onTranscription?("")
            return
        }

        SFSpeechRecognizer.requestAuthorization { [weak self] authStatus in
            DispatchQueue.main.async {
                guard let self else { return }
                switch authStatus {
                case .authorized:
                    self.beginRecording(recognizer: recognizer)
                default:
                    NSLog("JosType: speech recognition not authorized (status: \(authStatus.rawValue)).")
                    self.onTranscription?("")
                }
            }
        }
    }

    func cancelListening() {
        stopRecording()
        state = .idle
        lastTranscript = ""
    }

    private func beginRecording(recognizer: SFSpeechRecognizer) {
        state = .listening
        lastTranscript = ""

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true

        if !contextualStrings.isEmpty {
            request.contextualStrings = contextualStrings
        }

        self.recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        do {
            try audioEngine.start()
        } catch {
            NSLog("JosType: audio engine failed to start: \(error.localizedDescription)")
            cleanup()
            onTranscription?("")
            return
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let result {
                    self.lastTranscript = result.bestTranscription.formattedString
                    self.onPartialResult?(self.lastTranscript)
                    self.resetSilenceTimer()
                }
                if error != nil || (result?.isFinal == true) {
                    self.finishRecording()
                }
            }
        }

        resetSilenceTimer()
    }

    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceTimeout, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.finishRecording()
            }
        }
    }

    private func finishRecording() {
        guard state == .listening else { return }
        state = .processing
        stopRecording()

        let cleaned = cleanTranscript(lastTranscript)
        state = .idle
        onTranscription?(cleaned)
    }

    private func stopRecording() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
    }

    private func cleanup() {
        stopRecording()
        state = .idle
        lastTranscript = ""
    }

    private func cleanTranscript(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return text }
        let first = text.removeFirst()
        text = String(first).uppercased() + text
        if !text.hasSuffix(".") && !text.hasSuffix("!") && !text.hasSuffix("?") {
            text += "."
        }
        return text
    }
}
