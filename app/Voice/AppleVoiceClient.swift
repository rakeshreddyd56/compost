//
//  AppleVoiceClient.swift
//  Compost — Apple Speech + AVFoundation implementation of VoiceClient.
//
//  TTS:  AVSpeechSynthesizer with the system default voice.
//  STT:  SFSpeechRecognizer with on-device recognition where supported,
//        falling back to network (still keyless). Audio is captured by
//        AudioRecorder into a temp file and recognized in one shot.
//

import AVFoundation
import Speech

final class AppleVoiceClient: NSObject, VoiceClient {
    private let synthesizer = AVSpeechSynthesizer()
    private var speakContinuation: CheckedContinuation<Void, Error>?
    private let recorder = AudioRecorder()

    var isSpeaking: Bool { synthesizer.isSpeaking }

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - TTS

    func speak(text: String) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            self.speakContinuation = cont
            let u = AVSpeechUtterance(string: trimmed)
            u.voice = AVSpeechSynthesisVoice(language: "en-US")
            u.rate = AVSpeechUtteranceDefaultSpeechRate
            synthesizer.speak(u)
        }
    }

    func stopSpeaking() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    // MARK: - STT

    func transcribe(maxDuration: TimeInterval) async throws -> String {
        guard await AudioRecorder.ensureMicrophonePermission() else {
            throw VoiceError.microphoneDenied
        }
        try await Self.ensureSpeechAuth()

        try recorder.start()
        try? await Task.sleep(nanoseconds: UInt64(min(max(maxDuration, 0.5), 8.0) * 1_000_000_000))
        guard let url = recorder.stop() else {
            throw VoiceError.transcribeFailed("recorder produced no file")
        }
        defer { recorder.discard() }

        return try await Self.recognize(url: url)
    }

    /// Push-to-talk start. Permission checks + recorder boot. Does not block.
    func startListening() async throws {
        guard await AudioRecorder.ensureMicrophonePermission() else {
            throw VoiceError.microphoneDenied
        }
        try await Self.ensureSpeechAuth()
        try recorder.start()
    }

    /// Push-to-talk end. Stops recording, runs recognition on the captured
    /// file, returns the best transcript (or "" when nothing was heard).
    /// Cleans up the temp .m4a regardless of outcome.
    func stopAndTranscribe() async throws -> String {
        guard let url = recorder.stop() else {
            throw VoiceError.transcribeFailed("recorder produced no file")
        }
        defer { recorder.discard() }
        do {
            return try await Self.recognize(url: url)
        } catch {
            // Surface the underlying recognizer error rather than swallowing
            // it into the generic "no speech detected" UI string.
            throw error
        }
    }

    private static func recognize(url: URL) async throws -> String {
        guard let recognizer = SFSpeechRecognizer(locale: .current), recognizer.isAvailable else {
            throw VoiceError.recognizerUnavailable
        }
        let req = SFSpeechURLRecognitionRequest(url: url)
        req.shouldReportPartialResults = false
        if recognizer.supportsOnDeviceRecognition {
            req.requiresOnDeviceRecognition = true
        }
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            recognizer.recognitionTask(with: req) { result, error in
                if let error = error {
                    cont.resume(throwing: VoiceError.transcribeFailed(error.localizedDescription))
                    return
                }
                guard let result = result, result.isFinal else { return }
                cont.resume(returning: result.bestTranscription.formattedString)
            }
        }
    }

    private static func ensureSpeechAuth() async throws {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return
        case .denied, .restricted:
            throw VoiceError.speechRecognitionDenied
        case .notDetermined:
            let granted = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                SFSpeechRecognizer.requestAuthorization { status in
                    cont.resume(returning: status == .authorized)
                }
            }
            if !granted { throw VoiceError.speechRecognitionDenied }
        @unknown default:
            throw VoiceError.speechRecognitionDenied
        }
    }

    /// Best-effort live amplitude during the recorder's window. The Voice
    /// surface polls this on a TimelineView tick to drive the waveform.
    func currentAmplitude() -> Float { recorder.currentAmplitude() }
}

extension AppleVoiceClient: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didFinish utterance: AVSpeechUtterance) {
        speakContinuation?.resume()
        speakContinuation = nil
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didCancel utterance: AVSpeechUtterance) {
        speakContinuation?.resume()
        speakContinuation = nil
    }
}
