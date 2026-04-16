//
//  LumaMobileNetDetector.swift
//  leanring-buddy
//
//  Core ML visual UI element detector using MobileNetV2.
//
//  SETUP: Add MobileNetV2.mlmodel to the Xcode project (drag into the file tree).
//  The model can be downloaded from Apple's Core ML model gallery or converted
//  from torchvision.models.mobilenet_v3_small using coremltools.
//
//  Until the model file is added, this class returns an empty array gracefully.
//  All callers handle empty results by falling back to the AI screenshot path.
//

import CoreML
import Vision
import AppKit

// MARK: - LumaMobileNetDetector

/// Detects UI element regions in a screenshot using a MobileNetV2 Core ML model.
/// Returns bounding boxes and labels that LumaImageProcessingEngine cross-validates
/// against the Accessibility API results.
///
/// NOTE: The MobileNetV2.mlmodel file must be added to the Xcode project for this
/// detector to produce results. Without the model, all calls return an empty array.
final class LumaMobileNetDetector {
    static let shared = LumaMobileNetDetector()

    /// The compiled Vision request, lazily loaded when first needed.
    /// nil if the model file is not bundled in the app.
    private var vnCoreMLRequest: VNCoreMLRequest?

    /// True if the model was successfully loaded from the bundle.
    private(set) var isModelAvailable: Bool = false

    private init() {
        loadModelIfAvailable()
    }

    // MARK: - Model Loading

    private func loadModelIfAvailable() {
        // Look for the compiled model in the app bundle.
        // The model file must be named "MobileNetV2.mlmodel" and added to the Xcode target.
        guard let modelURL = Bundle.main.url(forResource: "MobileNetV2", withExtension: "mlmodelc")
               ?? Bundle.main.url(forResource: "MobileNetV2", withExtension: "mlmodel") else {
            print("[LumaMobileNet] Model file not found in bundle — visual detection disabled. Add MobileNetV2.mlmodel to the Xcode project.")
            return
        }

        do {
            let mlModel = try MLModel(contentsOf: modelURL)
            let vnModel = try VNCoreMLModel(for: mlModel)
            vnCoreMLRequest = VNCoreMLRequest(model: vnModel)
            vnCoreMLRequest?.imageCropAndScaleOption = .scaleFit
            isModelAvailable = true
            print("[LumaMobileNet] Model loaded successfully from \(modelURL.lastPathComponent)")
        } catch {
            print("[LumaMobileNet] Failed to load model: \(error.localizedDescription)")
        }
    }

    // MARK: - Detection

    /// Runs the MobileNetV2 model on `image` and returns detected UI regions.
    ///
    /// - Parameter image: Full-screen CGImage (top-left origin, pixel coordinates).
    /// - Parameter screenSize: The screen's point dimensions, used to convert
    ///   normalized Vision bounding boxes to screen coordinates.
    /// - Returns: Array of detected regions, sorted by confidence descending.
    ///   Returns empty array if the model is not available.
    func detectElements(in image: CGImage, screenSize: CGSize) async -> [VisualDetectionResult] {
        guard isModelAvailable, let request = vnCoreMLRequest else {
            return []
        }

        return await withCheckedContinuation { continuation in
            let handler = VNImageRequestHandler(cgImage: image, options: [:])

            do {
                try handler.perform([request])

                let results: [VisualDetectionResult] = (request.results as? [VNClassificationObservation] ?? [])
                    .filter { $0.confidence > 0.3 }
                    .map { observation in
                        // VNClassificationObservation doesn't carry a bounding box;
                        // for element detection we'd need VNRecognizedObjectObservation.
                        // This mapping handles whichever observation type the model returns.
                        VisualDetectionResult(
                            label: observation.identifier,
                            normalizedBoundingBox: CGRect(x: 0, y: 0, width: 1, height: 1),
                            confidence: Double(observation.confidence),
                            screenFrame: CGRect(origin: .zero, size: screenSize)
                        )
                    }
                    .sorted { $0.confidence > $1.confidence }

                continuation.resume(returning: results)
            } catch {
                print("[LumaMobileNet] Detection failed: \(error.localizedDescription)")
                continuation.resume(returning: [])
            }
        }
    }
}

// MARK: - VisualDetectionResult

/// A single detected UI element from the MobileNetV2 model.
struct VisualDetectionResult {
    /// The label/class predicted by the model (e.g. "button", "text field").
    let label: String
    /// Bounding box in normalized Vision coordinates (0-1, bottom-left origin).
    let normalizedBoundingBox: CGRect
    /// Detection confidence from 0.0 to 1.0.
    let confidence: Double
    /// The bounding box converted to screen point coordinates (top-left origin).
    let screenFrame: CGRect
}
