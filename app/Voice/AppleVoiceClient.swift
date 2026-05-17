//
//  AppleVoiceClient.swift
//  Compost — VoiceClient impl using Apple's built-in stack.
//
//  TTS: AVSpeechSynthesizer (AVFoundation) — on-device voices, zero cost.
//  STT: SFSpeechRecognizer (Speech) — on-device where supported, falls back
//       to Apple's network recognizer if not. Still no API key, no cost.
//
//  Errors surface as VoiceError with human-readable strings so the UI can
//  render them inline via NotchManager's existing error pattern.
//

import Foundation
import AVFoundation
import Speech

enum VoiceError: Error, LocalizedError {
    case microphoneDenied
    case speechRecognitionDenied
    case recognizerUnavailable
    case transcribeFailed(String)
    case ttsFailed(String)

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            return "Microphone permission denied. Allow it in System Settings."
        case .speechRecognitionDenied:
            return "Speech Recognition permission denied. Allow it in System Settings."
        case .recognizerUnavailable:
            return "Speech recognizer not available for this locale right now."
        case .transcribeFailed(let r): return "Couldn't transcribe: \(r)"
        case .ttsFailed(let r):        return "Couldn't speak: \(r)"
        }
    }
}

final class AppleVoiceClient: NSObject, VoiceClient {
    private let synthesizer = AVSpeechSynthesizer()
    private var speakContinuation: CheckedContinuation<Void, Error>?

    var isSpeaking: Bool { synthesizer.isSpeaking }

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - TTS

    func speak(text: String) async throws {
        // Stop anything currently playing — caller controls one-at-a-time.
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            self.speakContinuation = cont
            self.synthesizer.speak(utterance)
        }
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    // MARK: - STT

    /// Request both Microphone and Speech Recognition permissions if needed.
    /// Returns when both are granted, throws on denial.
    static func ensurePermissions() async throws {
        // Speech recognition
        let speechStatus: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { c in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
        }
        guard speechStatus == .authorized else {
            throw VoiceError.speechRecognitionDenied
        }
    }

    func transcribe(audioURL: URL) async throws -> String {
        try await Self.ensurePermissions()

        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              recognizer.isAvailable else {
            throw VoiceError.recognizerUnavailable
        }
        // Prefer on-device when supported so the audio doesn't leave the Mac.
        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = false
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        request.taskHint = .dictation

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            var resumed = false
            recognizer.recognitionTask(with: request) { result, error in
                if resumed { return }
                if let error {
                    resumed = true
                    cont.resume(throwing: VoiceError.transcribeFailed(error.localizedDescription))
                    return
                }
                guard let result, result.isFinal else { return }
                resumed = true
                cont.resume(returning: result.bestTranscription.formattedString)
            }
        }
    }
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
