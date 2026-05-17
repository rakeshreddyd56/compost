//
//  VoiceClient.swift
//  Compost — protocol that wraps the speech stack so we can later swap
//  Apple (default) for MiniMax/ElevenLabs without touching call sites.
//

import Foundation

protocol VoiceClient: AnyObject {
    /// Speak `text` aloud through the system's default audio output. Returns
    /// when playback finishes or `stopSpeaking()` is called. Throws on TTS
    /// failure (permission denied, voice not found, etc).
    func speak(text: String) async throws

    /// Cancel any in-flight `speak(text:)` synchronously. No-op when idle.
    func stopSpeaking()

    /// Whether the underlying synthesizer is currently producing audio.
    /// Used by the Voice surface to drive mascot mood.
    var isSpeaking: Bool { get }

    /// One-shot transcription. Records up to `maxDuration` seconds, then
    /// passes the recorded audio to the speech recognizer and returns the
    /// best transcript. Returns "" when the recognizer returned no result.
    func transcribe(maxDuration: TimeInterval) async throws -> String

    /// Push-to-talk pair. `startListening` begins recording immediately
    /// (no fixed duration); `stopAndTranscribe` stops the recorder and
    /// runs recognition on what was captured. Throws on permission denial
    /// or recognizer errors. Returns "" when no speech was recognised.
    func startListening() async throws
    func stopAndTranscribe() async throws -> String
}

enum VoiceError: LocalizedError {
    case microphoneDenied
    case speechRecognitionDenied
    case recognizerUnavailable
    case transcribeFailed(String)
    case ttsFailed(String)

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:        return "Microphone access denied. Grant in System Settings → Privacy & Security → Microphone."
        case .speechRecognitionDenied: return "Speech recognition access denied. Grant in System Settings → Privacy & Security → Speech Recognition."
        case .recognizerUnavailable:   return "Speech recognizer is unavailable for this locale."
        case .transcribeFailed(let s): return "Transcription failed: \(s)"
        case .ttsFailed(let s):        return "Read-aloud failed: \(s)"
        }
    }
}
