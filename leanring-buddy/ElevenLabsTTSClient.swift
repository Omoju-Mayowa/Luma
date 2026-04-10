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

    /// Shared singleton used by WalkthroughEngine and other callers that need
    /// fire-and-forget speech without owning their own synthesizer instance.
    static let shared = NativeTTSClient()

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

    /// Fire-and-forget speech. Wraps the async `speakText` in a Task so callers
    /// that don't need to await completion can use this without async/await boilerplate.
    /// Used by WalkthroughEngine for step instructions and nudge messages.
    func speak(_ text: String) {
        Task { try? await self.speakText(text) }
    }

    /// Speaks `text` using a natural macOS voice. Returns once playback starts.
    /// The caller can poll `isPlaying` to wait for completion.
    func speakText(_ text: String) async throws {
        try Task.checkCancellation()

        stopPlayback()

        let utterance = AVSpeechUtterance(string: text)
        // Higher pitch and slightly slower rate for a sassier, more expressive delivery
        utterance.rate = 0.52
        utterance.pitchMultiplier = 1.4
        utterance.volume = 1.0

        // Prefer Zoe (enhanced) → Zoe (compact) → Samantha → system default
        if let zoeEnhancedVoice = AVSpeechSynthesisVoice(identifier: "com.apple.voice.enhanced.en-US.Zoe") {
            utterance.voice = zoeEnhancedVoice
        } else if let zoeCompactVoice = AVSpeechSynthesisVoice(identifier: "com.apple.ttsbundle.Zoe-compact") {
            utterance.voice = zoeCompactVoice
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
