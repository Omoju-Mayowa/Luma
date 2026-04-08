//
//  NativeTTSClient.swift
//  leanring-buddy
//
//  Speaks text using macOS native AVSpeechSynthesizer. Fully local —
//  no external API calls. Replaces the previous ElevenLabs integration.
//

import AVFoundation
import Foundation

@MainActor
final class NativeTTSClient: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()

    /// Continuation used to bridge the delegate callback into async/await.
    /// Set when speech begins, resolved when it finishes or is cancelled.
    private var speechFinishedContinuation: CheckedContinuation<Void, Never>?

    /// Tracks whether the synthesizer is actively speaking.
    private(set) var isPlaying: Bool = false

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Speaks `text` using a natural macOS voice. Returns once playback starts.
    /// The caller can poll `isPlaying` to wait for completion.
    func speakText(_ text: String) async throws {
        try Task.checkCancellation()

        stopPlayback()

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0

        // Prefer a natural-sounding English voice. Try enhanced Zoe first,
        // then Samantha compact, then fall back to the best available English voice.
        if let zoeVoice = AVSpeechSynthesisVoice(identifier: "com.apple.voice.enhanced.en-US.Zoe") {
            utterance.voice = zoeVoice
        } else if let samanthaVoice = AVSpeechSynthesisVoice(identifier: "com.apple.ttsbundle.Samantha-compact") {
            utterance.voice = samanthaVoice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        }

        isPlaying = true
        synthesizer.speak(utterance)
        print("🔊 Native TTS: speaking \(text.count) characters")
    }

    /// Stops any in-progress playback immediately.
    func stopPlayback() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isPlaying = false
        // Resolve any pending continuation so callers aren't left hanging
        speechFinishedContinuation?.resume()
        speechFinishedContinuation = nil
    }

    /// Waits until the current utterance finishes. Returns immediately if nothing is playing.
    func waitUntilFinished() async {
        guard isPlaying else { return }
        await withCheckedContinuation { continuation in
            self.speechFinishedContinuation = continuation
        }
    }

    // MARK: - AVSpeechSynthesizerDelegate

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isPlaying = false
            self.speechFinishedContinuation?.resume()
            self.speechFinishedContinuation = nil
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isPlaying = false
            self.speechFinishedContinuation?.resume()
            self.speechFinishedContinuation = nil
        }
    }
}
