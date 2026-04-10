//
//  LumaOnDeviceAI.swift
//  leanring-buddy
//
//  Unified manager for all on-device AI inference. Owns the Whisper transcription
//  engine, DistilBERT task classifier, and MobileNet element detector.
//
//  Models are loaded lazily — only when first needed — to keep startup fast.
//  All three models are stubs until their .mlpackage files are added to the project.
//

import AVFoundation
import AppKit
import Foundation

// MARK: - LumaOnDeviceAI

/// Single entry point for all on-device AI operations.
/// Delegates to the individual model engines; callers do not import them directly.
@MainActor
final class LumaOnDeviceAI {
    static let shared = LumaOnDeviceAI()

    // MARK: - Sub-engines (lazily initialized to keep startup fast)

    /// Whisper Tiny — on-device speech-to-text. Falls back to AssemblyAI/Apple Speech when unavailable.
    private(set) lazy var whisper = LumaWhisperEngine.shared

    /// DistilBERT-based heuristic classifier — single vs multi-step vs question detection.
    private(set) lazy var classifier = LumaTaskClassifier.shared

    /// MobileNetV3 — visual UI element detection from screenshots.
    private(set) lazy var detector = LumaMobileNetDetector.shared

    private init() {}

    // MARK: - Public API

    /// Transcribes an audio buffer using Whisper Tiny on-device.
    /// Returns nil when the model is unavailable — callers fall back to their configured provider.
    func transcribe(_ audioBuffer: AVAudioPCMBuffer) async -> String? {
        await whisper.transcribe(audioBuffer)
    }

    /// Classifies user text to determine how Luma should respond.
    func classifyTask(_ text: String) async -> TaskClassification {
        await classifier.classifyTask(text)
    }

    /// Checks whether an accessibility event matches the expected walkthrough step action.
    /// Runs entirely on-device with no API call — used during walkthrough execution for
    /// instant wrong-action feedback before the debounced AI screenshot validation fires.
    func detectWrongAction(
        expectedElementName: String,
        expectedAppBundleID: String?,
        actualEventElementTitle: String?,
        actualEventAppBundleID: String
    ) -> WrongActionResult {
        classifier.detectWrongAction(
            expectedElementName: expectedElementName,
            expectedAppBundleID: expectedAppBundleID,
            actualEventElementTitle: actualEventElementTitle,
            actualEventAppBundleID: actualEventAppBundleID
        )
    }

    /// Detects UI element regions in a screenshot using MobileNetV3.
    /// Returns empty array when the model is not bundled.
    func detectElements(in image: CGImage, screenSize: CGSize) async -> [VisualDetectionResult] {
        await detector.detectElements(in: image, screenSize: screenSize)
    }

    // MARK: - Model Availability Summary

    /// Prints a summary of which on-device models are available, useful for debugging.
    func logModelAvailability() {
        print("[LumaOnDeviceAI] Whisper:     \(whisper.isModelAvailable ? "✓ available" : "✗ not bundled — using API")")
        print("[LumaOnDeviceAI] Classifier:  \(classifier.isModelAvailable ? "✓ ML model" : "✓ heuristic fallback")")
        print("[LumaOnDeviceAI] MobileNet:   \(detector.isModelAvailable ? "✓ available" : "✗ not bundled — visual scan disabled")")
    }
}
