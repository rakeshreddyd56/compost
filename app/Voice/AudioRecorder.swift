//
//  AudioRecorder.swift
//  Compost — push-to-talk recorder writing to a temp .m4a.
//
//  Used by AppleVoiceClient.transcribe() to capture a short clip that
//  SFSpeechRecognizer then turns into text. We deliberately keep the file
//  lifecycle short: write to the system temp dir, hand it off, delete.
//  No persistent audio storage anywhere in the app.
//

import AVFoundation

final class AudioRecorder {
    private var recorder: AVAudioRecorder?
    private(set) var fileURL: URL?

    /// Request microphone permission once (cached by macOS for the app).
    /// Returns true if granted, false if denied. Safe to call repeatedly.
    static func ensureMicrophonePermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            return await withCheckedContinuation { cont in
                AVCaptureDevice.requestAccess(for: .audio) { ok in
                    cont.resume(returning: ok)
                }
            }
        @unknown default:
            return false
        }
    }

    /// Start a fresh recording at a temp .m4a path. Throws when the file
    /// cannot be created or the AV stack refuses to start.
    func start() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("compost-voice-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16_000.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]
        let r = try AVAudioRecorder(url: url, settings: settings)
        r.isMeteringEnabled = true
        guard r.prepareToRecord(), r.record() else {
            throw VoiceError.transcribeFailed("AVAudioRecorder refused to start")
        }
        self.recorder = r
        self.fileURL = url
    }

    /// Stop recording and return the captured file URL. Returns nil when no
    /// recording is in flight.
    func stop() -> URL? {
        guard let r = recorder else { return nil }
        r.stop()
        self.recorder = nil
        return fileURL
    }

    /// Real-time amplitude in [0,1] for the waveform envelope. 0 when idle.
    func currentAmplitude() -> Float {
        guard let r = recorder, r.isRecording else { return 0 }
        r.updateMeters()
        // averagePower is in dB, typically -160 (silence) to 0 (max).
        let dB = r.averagePower(forChannel: 0)
        let clamped = max(-60, min(0, dB))
        return Float((clamped + 60) / 60)
    }

    /// Best-effort delete; safe to call multiple times.
    func discard() {
        if let url = fileURL {
            try? FileManager.default.removeItem(at: url)
        }
        fileURL = nil
    }

    deinit { discard() }
}
