//
//  AudioRecorder.swift
//  Compost — push-to-talk wrapper around AVAudioRecorder.
//
//  Records to a temporary .m4a so SFSpeechURLRecognitionRequest can read it
//  back. Caller is responsible for cleaning the temp file when done.
//

import Foundation
import AVFoundation

final class AudioRecorder: NSObject {
    private var recorder: AVAudioRecorder?
    private(set) var currentFileURL: URL?

    /// Ask for microphone permission. Returns true when granted.
    static func ensureMicrophonePermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized: return true
        case .notDetermined:
            return await withCheckedContinuation { c in
                AVCaptureDevice.requestAccess(for: .audio) { c.resume(returning: $0) }
            }
        case .denied, .restricted: return false
        @unknown default: return false
        }
    }

    /// Start recording into a fresh temp .m4a. Throws on failure.
    func start() throws {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("compost-capture-\(UUID().uuidString).m4a")
        currentFileURL = url

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]
        let r = try AVAudioRecorder(url: url, settings: settings)
        r.prepareToRecord()
        guard r.record() else {
            throw NSError(domain: "AudioRecorder", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Recorder couldn't start"])
        }
        recorder = r
    }

    /// Stop recording and return the URL of the captured audio file.
    func stop() -> URL? {
        recorder?.stop()
        let url = currentFileURL
        recorder = nil
        currentFileURL = nil
        return url
    }

    var isRecording: Bool { recorder?.isRecording ?? false }
}
