//
//  VoiceClient.swift
//  Compost — voice protocol so a future TTS/STT swap (MiniMax / ElevenLabs /
//  OpenAI) doesn't require touching the call sites in NotchManager.
//

import Foundation

protocol VoiceClient {
    /// Speak `text` aloud. Returns when playback finishes. Throws on any
    /// underlying error (interruption, no-audio-device, etc.).
    func speak(text: String) async throws

    /// Stop any in-progress speech immediately.
    func stop()

    /// True while audio is actively playing.
    var isSpeaking: Bool { get }

    /// Transcribe the audio file at `audioURL` to text.
    func transcribe(audioURL: URL) async throws -> String
}
