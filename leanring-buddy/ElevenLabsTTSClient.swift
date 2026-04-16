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

    /// Strips coordinate tokens and related technical patterns from `text` before speaking.
    /// Prevents the synthesizer from reading out things like "point 400 comma 200" or
    /// "x colon 150 y colon 300" that Claude occasionally includes in its responses.
    private func sanitizeSpeech(_ text: String) -> String {
        var cleaned = text

        // Each pattern targets a different coordinate format Claude might embed in a response.
        let coordinatePatterns: [String] = [
            #"point\s*\(\s*\d+\s*,\s*\d+\s*\)"#,        // point(400, 200)
            #"\(\s*\d{2,4}\s*,\s*\d{2,4}\s*\)"#,          // (400, 200)
            #"\[\s*\d{2,4}\s*,\s*\d{2,4}\s*\]"#,          // [400, 200]
            #"\{\s*x\s*:\s*\d+\s*,\s*y\s*:\s*\d+\s*\}"#,  // {x: 400, y: 200}
            #"at coordinates \d+,?\s*\d+"#,                 // at coordinates 400, 200
            #"position \d+,?\s*\d+"#,                       // position 400, 200
            #"\bx:\s*\d+,?\s*y:\s*\d+"#,                   // x: 400, y: 200
        ]

        for pattern in coordinatePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let fullRange = NSRange(cleaned.startIndex..., in: cleaned)
                cleaned = regex.stringByReplacingMatches(in: cleaned, range: fullRange, withTemplate: "")
            }
        }

        return cleaned
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    /// Speaks `text` using a natural macOS voice. Returns once playback starts.
    /// The caller can poll `isPlaying` to wait for completion.
    func speakText(_ text: String) async throws {
        try Task.checkCancellation()

        stopPlayback()

        let utterance = AVSpeechUtterance(string: sanitizeSpeech(text))
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
