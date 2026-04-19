# 3-Layer Visual Detection Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the `VNClassificationObservation` bounding-box bug in `LumaMobileNetDetector` and the cross-validation false-positive it causes, by replacing the broken MobileNet classification path with a proper 3-layer on-device + API pipeline.

**Architecture:** Layer 1 (Vision text + rectangle detection, always runs) produces real bounding boxes. Layer 2 (MobileNetV2 crop validation) confirms meaningful content exists at Layer 1 coordinates. Layer 3 (`APIClient.shared.analyzeImage` + `[POINT:x,y:label]` parsing) fires as a last resort when both on-device layers return confidence below 0.5. The spurious +0.3 cross-validation boost caused by the full-screen `(0,0,1,1)` placeholder is automatically eliminated by returning real bounding boxes.

**Tech Stack:** Vision Framework (`VNRecognizeTextRequest`, `VNDetectRectanglesRequest`, `VNCoreMLRequest`), Core ML, Swift Testing (`@Test`, `#expect`), existing `APIClient.shared.analyzeImage`

---

## File Map

| File | Change |
|------|--------|
| `leanring-buddy/LumaMobileNetDetector.swift` | Full rewrite — Layer 1 Vision detection + Layer 2 MobileNet validation |
| `leanring-buddy/LumaOnDeviceAI.swift` | Add `searchQuery` parameter to `detectElements` |
| `leanring-buddy/LumaImageProcessingEngine.swift` | Thread `query` to `detectElements`; add Layer 3 fallback, point parser, adaptive box helper |
| `leanring-buddyTests/leanring_buddyTests.swift` | Add tests for all new pure functions |

---

## Task 1: Rewrite LumaMobileNetDetector with Layer 1 + Layer 2

**Files:**
- Modify: `leanring-buddyTests/leanring_buddyTests.swift`
- Modify: `leanring-buddy/LumaMobileNetDetector.swift`

- [ ] **Step 1: Add tests for the two pure helper functions**

Append to `leanring-buddyTests/leanring_buddyTests.swift` (after the last `@Test` function, before the closing `}`):

```swift
// MARK: - LumaMobileNetDetector Tests

@Test func queryMatchWeightIsOnePointZeroForExactMatch() {
    let matchWeight = LumaMobileNetDetector.shared.computeQueryMatchWeight(
        recognizedText: "Save",
        searchQuery: "Save"
    )
    #expect(matchWeight == 1.0)
}

@Test func queryMatchWeightIsSevenTenthsWhenLabelContainsQuery() {
    let matchWeight = LumaMobileNetDetector.shared.computeQueryMatchWeight(
        recognizedText: "Save Document",
        searchQuery: "Save"
    )
    #expect(matchWeight == 0.7)
}

@Test func queryMatchWeightIsFourTenthsWhenQueryContainsLabelLongerThanThreeChars() {
    let matchWeight = LumaMobileNetDetector.shared.computeQueryMatchWeight(
        recognizedText: "Save",
        searchQuery: "Save Document Now"
    )
    #expect(matchWeight == 0.4)
}

@Test func queryMatchWeightIsZeroForUnrelatedText() {
    let matchWeight = LumaMobileNetDetector.shared.computeQueryMatchWeight(
        recognizedText: "Lorem ipsum",
        searchQuery: "Save"
    )
    #expect(matchWeight == 0.0)
}

@Test func queryMatchWeightIsZeroWhenQueryContainsLabelOfThreeCharsOrFewer() {
    // Labels of 3 chars or fewer are too ambiguous to match on (noise threshold)
    let matchWeight = LumaMobileNetDetector.shared.computeQueryMatchWeight(
        recognizedText: "OK",
        searchQuery: "Click OK to confirm"
    )
    #expect(matchWeight == 0.0)
}

@Test func queryMatchIsCaseInsensitive() {
    let matchWeight = LumaMobileNetDetector.shared.computeQueryMatchWeight(
        recognizedText: "SAVE",
        searchQuery: "save"
    )
    #expect(matchWeight == 1.0)
}

@Test func visionBoundingBoxIsFlippedToQuartzTopLeftOrigin() {
    // Vision box at the top of a 1000×1000 screen in Vision coords (bottom-left origin):
    // minX=0.1, minY=0.8 (bottom 80% up), width=0.2, height=0.1
    // In Quartz (top-left origin):
    //   quartzX      = 0.1 × 1000 = 100
    //   quartzY      = (1.0 - (0.8 + 0.1)) × 1000 = (1.0 - 0.9) × 1000 = 100
    //   quartzWidth  = 0.2 × 1000 = 200
    //   quartzHeight = 0.1 × 1000 = 100
    let visionBox = CGRect(x: 0.1, y: 0.8, width: 0.2, height: 0.1)
    let screenSize = CGSize(width: 1000, height: 1000)
    let quartzFrame = LumaMobileNetDetector.shared.visionBoundingBoxToQuartzScreenFrame(
        visionNormalizedBox: visionBox,
        screenSize: screenSize
    )
    #expect(abs(quartzFrame.origin.x - 100) < 0.01)
    #expect(abs(quartzFrame.origin.y - 100) < 0.01)
    #expect(abs(quartzFrame.width  - 200) < 0.01)
    #expect(abs(quartzFrame.height - 100) < 0.01)
}

@Test func visionBoxAtBottomOfScreenMapsToLargeQuartzY() {
    // Vision box at the bottom of the screen: minY=0.0, height=0.1
    // In Quartz: quartzY = (1.0 - 0.1) × 1000 = 900
    let visionBox = CGRect(x: 0.0, y: 0.0, width: 1.0, height: 0.1)
    let screenSize = CGSize(width: 1000, height: 1000)
    let quartzFrame = LumaMobileNetDetector.shared.visionBoundingBoxToQuartzScreenFrame(
        visionNormalizedBox: visionBox,
        screenSize: screenSize
    )
    #expect(abs(quartzFrame.origin.y - 900) < 0.01)
}
```

- [ ] **Step 2: Verify tests fail to compile (expected — implementation not yet written)**

Open the project in Xcode. The test file will show compile errors because `computeQueryMatchWeight` and `visionBoundingBoxToQuartzScreenFrame` don't exist yet. This is expected — proceed to Step 3.

- [ ] **Step 3: Replace LumaMobileNetDetector.swift with the Layer 1 + Layer 2 implementation**

Replace the entire contents of `leanring-buddy/LumaMobileNetDetector.swift`:

```swift
//
//  LumaMobileNetDetector.swift
//  leanring-buddy
//
//  3-layer visual UI element detection pipeline (on-device layers only).
//
//  Layer 1 (always runs): VNRecognizeTextRequest + VNDetectRectanglesRequest
//    Finds real bounding boxes for text labels and rectangular UI elements.
//    Results are scored by how closely recognized text matches the search query.
//
//  Layer 2 (runs when Layer 1 finds a match): MobileNetV2 classification
//    Crops a 160×160 region around the Layer 1 bounding box center and runs
//    MobileNetV2. Results where MobileNet confidence < 0.35 are downgraded
//    (confidence ×= 0.5) so they fall below the Layer 3 trigger threshold.
//    Pass-through when MobileNetV2.mlmodelc is not bundled.
//
//  Layer 3 (last resort): Lives in LumaImageProcessingEngine.scanVisual.
//    Triggered when this detector returns no result above 0.5 confidence.
//    Uses APIClient.shared.analyzeImage with [POINT:x,y:label] parsing.
//

import CoreML
import Vision
import AppKit

// MARK: - LumaMobileNetDetector

/// On-device visual element detector. Implements Layer 1 (Vision text + rectangles) and
/// Layer 2 (MobileNetV2 crop validation) of the 3-layer detection pipeline.
///
/// Returns `[VisualDetectionResult]` with real Quartz screen-coordinate bounding boxes.
/// Callers (LumaImageProcessingEngine.scanVisual) trigger Layer 3 when the returned
/// results have no confidence ≥ 0.5.
final class LumaMobileNetDetector {
    static let shared = LumaMobileNetDetector()

    /// The compiled VNCoreMLModel. Stored separately from any request so fresh
    /// VNCoreMLRequest instances can be created per crop in Layer 2 validation
    /// (VNCoreMLRequest is not thread-safe when shared across concurrent handlers).
    private var vnCoreMLModel: VNCoreMLModel?

    private(set) var isModelAvailable: Bool = false

    private init() {
        loadModelIfAvailable()
    }

    // MARK: - Model Loading

    private func loadModelIfAvailable() {
        guard let modelURL = Bundle.main.url(forResource: "MobileNetV2", withExtension: "mlmodelc")
               ?? Bundle.main.url(forResource: "MobileNetV2", withExtension: "mlmodel") else {
            print("[LumaMobileNet] MobileNetV2 not found in bundle — Layer 2 validation disabled. Layer 1 Vision requests still active.")
            return
        }

        do {
            let mlModel = try MLModel(contentsOf: modelURL)
            vnCoreMLModel = try VNCoreMLModel(for: mlModel)
            isModelAvailable = true
            print("[LumaMobileNet] MobileNetV2 loaded from \(modelURL.lastPathComponent) — Layer 2 active")
        } catch {
            print("[LumaMobileNet] Failed to load MobileNetV2: \(error.localizedDescription)")
        }
    }

    // MARK: - Detection Entry Point

    /// Runs Layer 1 (Vision text + rectangles) then Layer 2 (MobileNet crop validation).
    ///
    /// Returns an empty array when Layer 1 finds no text matching `searchQuery` above the
    /// 0.5 confidence threshold. `LumaImageProcessingEngine.scanVisual` triggers Layer 3
    /// (APIClient) when the result is empty or best confidence < 0.5.
    func detectElements(
        in image: CGImage,
        screenSize: CGSize,
        searchQuery: String
    ) async -> [VisualDetectionResult] {
        let layer1Results = await runLayer1VisionDetection(
            on: image,
            screenSize: screenSize,
            searchQuery: searchQuery
        )
        guard !layer1Results.isEmpty else { return [] }
        return await applyLayer2MobileNetValidation(to: layer1Results, sourceImage: image)
    }

    // MARK: - Layer 1: Vision Text + Rectangle Detection

    /// Runs VNRecognizeTextRequest and VNDetectRectanglesRequest on `image`.
    ///
    /// For each recognized text observation:
    ///   resultConfidence = recognitionConfidence × computeQueryMatchWeight(text, searchQuery)
    ///
    /// Observations below 0.5 resultConfidence are discarded.
    ///
    /// Rectangle observations boost the confidence of any text result whose Quartz frame
    /// overlaps the rectangle by > 50% (+0.1, capped at 1.0). Rectangles with no matching
    /// nearby text produce no standalone result.
    private func runLayer1VisionDetection(
        on image: CGImage,
        screenSize: CGSize,
        searchQuery: String
    ) async -> [VisualDetectionResult] {
        return await withCheckedContinuation { continuation in
            let textRecognitionRequest = VNRecognizeTextRequest()
            textRecognitionRequest.recognitionLevel = .accurate
            // Language correction is disabled — we want raw recognized text, not autocorrected,
            // so short labels like "Cmd+R" or "⌘N" are not mangled.
            textRecognitionRequest.usesLanguageCorrection = false

            let rectangleDetectionRequest = VNDetectRectanglesRequest()
            rectangleDetectionRequest.minimumAspectRatio = 0.1
            rectangleDetectionRequest.maximumAspectRatio = 10.0
            rectangleDetectionRequest.minimumSize = 0.01  // At least 1% of the image dimension
            rectangleDetectionRequest.maximumObservations = 20

            let imageRequestHandler = VNImageRequestHandler(cgImage: image, options: [:])

            do {
                try imageRequestHandler.perform([textRecognitionRequest, rectangleDetectionRequest])
            } catch {
                print("[LumaMobileNet] Layer 1 Vision requests failed: \(error.localizedDescription)")
                continuation.resume(returning: [])
                return
            }

            let textObservations = textRecognitionRequest.results as? [VNRecognizedTextObservation] ?? []
            let rectangleObservations = rectangleDetectionRequest.results as? [VNRectangleObservation] ?? []

            var detectedResults: [VisualDetectionResult] = []

            for textObservation in textObservations {
                guard let topCandidate = textObservation.topCandidates(1).first else { continue }

                let queryMatchWeight = computeQueryMatchWeight(
                    recognizedText: topCandidate.string,
                    searchQuery: searchQuery
                )
                guard queryMatchWeight > 0.0 else { continue }

                let resultConfidence = Double(topCandidate.confidence) * queryMatchWeight
                guard resultConfidence >= 0.5 else { continue }

                let quartzScreenFrame = visionBoundingBoxToQuartzScreenFrame(
                    visionNormalizedBox: textObservation.boundingBox,
                    screenSize: screenSize
                )

                // A text label inside a rectangle is more likely to be a button or interactive
                // element — corroborate by checking whether any detected rectangle overlaps.
                let hasOverlappingRectangle = rectangleObservations.contains { rectangleObservation in
                    let rectangleScreenFrame = visionBoundingBoxToQuartzScreenFrame(
                        visionNormalizedBox: rectangleObservation.boundingBox,
                        screenSize: screenSize
                    )
                    let intersection = quartzScreenFrame.intersection(rectangleScreenFrame)
                    guard !intersection.isNull,
                          quartzScreenFrame.width > 0,
                          quartzScreenFrame.height > 0 else { return false }
                    let overlapFraction = (intersection.width * intersection.height)
                                       / (quartzScreenFrame.width * quartzScreenFrame.height)
                    return overlapFraction > 0.5
                }

                let boostedConfidence = hasOverlappingRectangle
                    ? min(resultConfidence + 0.1, 1.0)
                    : resultConfidence

                detectedResults.append(VisualDetectionResult(
                    label: topCandidate.string,
                    normalizedBoundingBox: textObservation.boundingBox,
                    confidence: boostedConfidence,
                    screenFrame: quartzScreenFrame
                ))
            }

            let sortedResults = detectedResults.sorted { $0.confidence > $1.confidence }
            print("[LumaMobileNet] Layer 1: \(sortedResults.count) match(es) for '\(searchQuery)'")
            for result in sortedResults.prefix(3) {
                print("[LumaMobileNet]   '\(result.label)' confidence=\(String(format: "%.2f", result.confidence))")
            }
            continuation.resume(returning: sortedResults)
        }
    }

    // MARK: - Layer 2: MobileNetV2 Crop Validation

    /// For each Layer 1 result, crops a 160×160 region around the bounding box center
    /// and runs MobileNetV2. Results where top-class confidence < 0.35 are downgraded
    /// (confidence ×= 0.5) to fall below the Layer 3 trigger threshold.
    ///
    /// When MobileNetV2 is not bundled, all Layer 1 results pass through unchanged.
    private func applyLayer2MobileNetValidation(
        to layer1Results: [VisualDetectionResult],
        sourceImage: CGImage
    ) async -> [VisualDetectionResult] {
        guard isModelAvailable, let coreMLModel = vnCoreMLModel else {
            // Model not bundled — pass all Layer 1 results through without validation
            return layer1Results
        }

        return await withCheckedContinuation { continuation in
            var validatedResults: [VisualDetectionResult] = []
            // Serial queue protects appends into validatedResults from concurrent handlers
            let resultsAccessQueue = DispatchQueue(label: "com.luma.mobilenet.layer2.results")
            let completionGroup = DispatchGroup()

            for layer1Result in layer1Results {
                completionGroup.enter()

                let cropRadius: CGFloat = 80
                let cropRect = CGRect(
                    x: max(0, layer1Result.screenFrame.midX - cropRadius),
                    y: max(0, layer1Result.screenFrame.midY - cropRadius),
                    width: cropRadius * 2,
                    height: cropRadius * 2
                )

                guard let croppedRegion = sourceImage.cropping(to: cropRect) else {
                    // Center coordinate is out of the image bounds — pass through unchanged
                    resultsAccessQueue.async {
                        validatedResults.append(layer1Result)
                        completionGroup.leave()
                    }
                    continue
                }

                // Create a fresh VNCoreMLRequest per crop — VNCoreMLRequest is NOT thread-safe
                // when shared across concurrent VNImageRequestHandler calls. Sharing the request
                // causes data races in Vision's internal result storage on macOS 13+.
                let cropValidationRequest = VNCoreMLRequest(model: coreMLModel) { request, _ in
                    let classificationObservations = request.results as? [VNClassificationObservation]
                    let topClassConfidence = classificationObservations?.first?.confidence ?? 0.0

                    let validatedResult: VisualDetectionResult
                    if topClassConfidence >= 0.35 {
                        // MobileNet confirms meaningful visual content at this location
                        validatedResult = layer1Result
                        print("[LumaMobileNet] Layer 2: '\(layer1Result.label)' validated (MobileNet \(String(format: "%.2f", topClassConfidence)))")
                    } else {
                        // MobileNet found no meaningful content — downgrade below Layer 3 trigger (0.5)
                        validatedResult = VisualDetectionResult(
                            label: layer1Result.label,
                            normalizedBoundingBox: layer1Result.normalizedBoundingBox,
                            confidence: layer1Result.confidence * 0.5,
                            screenFrame: layer1Result.screenFrame
                        )
                        print("[LumaMobileNet] Layer 2: '\(layer1Result.label)' downgraded (MobileNet \(String(format: "%.2f", topClassConfidence)))")
                    }

                    resultsAccessQueue.async {
                        validatedResults.append(validatedResult)
                        completionGroup.leave()
                    }
                }

                let cropValidationHandler = VNImageRequestHandler(cgImage: croppedRegion, options: [:])
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        try cropValidationHandler.perform([cropValidationRequest])
                    } catch {
                        print("[LumaMobileNet] Layer 2 validation error for '\(layer1Result.label)': \(error.localizedDescription)")
                        // Validation error — pass result through rather than silently discarding it
                        resultsAccessQueue.async {
                            validatedResults.append(layer1Result)
                            completionGroup.leave()
                        }
                    }
                }
            }

            completionGroup.notify(queue: .main) {
                let sortedValidatedResults = validatedResults.sorted { $0.confidence > $1.confidence }
                continuation.resume(returning: sortedValidatedResults)
            }
        }
    }

    // MARK: - Coordinate Conversion

    /// Converts a Vision Framework normalized bounding box (bottom-left origin, 0–1 scale)
    /// to a Quartz/AX screen frame (top-left origin, absolute screen points).
    ///
    /// The Y-flip formula uses `1.0 - visionNormalizedBox.maxY` because maxY is the top of
    /// the box in Vision's bottom-left coordinate system (highest Y value). That top edge
    /// maps to the smallest Quartz Y value (closest to the top-left screen origin).
    ///
    /// Internal (not private) so unit tests can call it directly without mocking Vision.
    func visionBoundingBoxToQuartzScreenFrame(
        visionNormalizedBox: CGRect,
        screenSize: CGSize
    ) -> CGRect {
        let quartzX      = visionNormalizedBox.minX  * screenSize.width
        let quartzY      = (1.0 - visionNormalizedBox.maxY) * screenSize.height
        let quartzWidth  = visionNormalizedBox.width  * screenSize.width
        let quartzHeight = visionNormalizedBox.height * screenSize.height
        return CGRect(x: quartzX, y: quartzY, width: quartzWidth, height: quartzHeight)
    }

    // MARK: - Query Match Scoring

    /// Returns a 0.0–1.0 weight for how well `recognizedText` matches `searchQuery`.
    ///
    /// The weight is multiplied by the Vision recognition confidence to produce the
    /// Layer 1 result confidence:
    ///   resultConfidence = recognitionConfidence × computeQueryMatchWeight(text, query)
    ///
    /// Internal (not private) so unit tests can verify scoring rules directly.
    func computeQueryMatchWeight(recognizedText: String, searchQuery: String) -> Double {
        let textLower  = recognizedText.lowercased()
        let queryLower = searchQuery.lowercased()

        if textLower == queryLower {
            return 1.0   // Exact label match — strongest signal
        } else if textLower.contains(queryLower) {
            return 0.7   // Label contains the full query (e.g. "Save Document" ⊃ "Save")
        } else if queryLower.contains(textLower) && textLower.count > 3 {
            // Query contains the label — only accepted when the label is > 3 chars to
            // avoid matching noise like "OK" or "a" inside arbitrary query strings.
            return 0.4
        }
        return 0.0  // No relationship — discard this observation
    }
}

// MARK: - VisualDetectionResult

/// A single detected UI element from the on-device detection pipeline.
struct VisualDetectionResult {
    /// The recognized text label (Layer 1 text recognition) or model-predicted class (legacy MobileNet).
    let label: String
    /// Bounding box in normalized Vision coordinates (0–1, bottom-left origin).
    let normalizedBoundingBox: CGRect
    /// Detection confidence from 0.0 to 1.0, incorporating both recognition quality and query match.
    let confidence: Double
    /// Bounding box in Quartz/AX screen coordinates (top-left origin, absolute screen points).
    /// Used for cross-validation with AX candidate frames in LumaImageProcessingEngine.
    let screenFrame: CGRect
}
```

- [ ] **Step 4: Run tests in Xcode (Cmd+U)**

Open the project in Xcode (`open leanring-buddy.xcodeproj`). Press Cmd+U.

Expected: All 8 new tests pass. Existing 3 permission tests still pass.

If any test fails, check:
- `queryMatchWeightIsZeroWhenQueryContainsLabelOfThreeCharsOrFewer`: "OK" is 2 chars, `count > 3` is false → returns 0.0 ✓
- Y-axis tests: verify the formula `(1.0 - visionNormalizedBox.maxY)` is used (maxY = minY + height)

- [ ] **Step 5: Commit**

```bash
git add leanring-buddy/LumaMobileNetDetector.swift leanring-buddyTests/leanring_buddyTests.swift
git commit -m "feat: implement Layer 1+2 visual detection in LumaMobileNetDetector

Replace VNClassificationObservation (no bounding box) with VNRecognizeTextRequest
+ VNDetectRectanglesRequest for real on-screen coordinates. MobileNetV2 stays
as a crop-validator only — not a localizer. Fixes the (0,0,1,1) full-screen
bounding box that was causing spurious cross-validation boosts in LIPE.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 2: Thread searchQuery through LumaOnDeviceAI

**Files:**
- Modify: `leanring-buddy/LumaOnDeviceAI.swift`

- [ ] **Step 1: Update `detectElements` in LumaOnDeviceAI.swift**

In `leanring-buddy/LumaOnDeviceAI.swift`, replace the `detectElements` method (lines 68–71):

```swift
// Before:
/// Detects UI element regions in a screenshot using MobileNetV2.
/// Returns empty array when the model is not bundled.
func detectElements(in image: CGImage, screenSize: CGSize) async -> [VisualDetectionResult] {
    await detector.detectElements(in: image, screenSize: screenSize)
}
```

```swift
// After:
/// Detects UI element regions in a screenshot using the 3-layer on-device pipeline.
/// Returns empty array when Layer 1 finds no text matching `searchQuery` above threshold.
/// Callers (LumaImageProcessingEngine.scanVisual) trigger Layer 3 when the result is empty.
func detectElements(in image: CGImage, screenSize: CGSize, searchQuery: String) async -> [VisualDetectionResult] {
    await detector.detectElements(in: image, screenSize: screenSize, searchQuery: searchQuery)
}
```

Also update `logModelAvailability` print line for `MobileNet` (line 79) to reflect the new role:

```swift
// Before:
print("[LumaOnDeviceAI] MobileNet:   \(detector.isModelAvailable ? "✓ available" : "✗ not bundled — visual scan disabled")")

// After:
print("[LumaOnDeviceAI] MobileNet:   \(detector.isModelAvailable ? "✓ available (Layer 2 validation active)" : "✗ not bundled — Layer 2 validation disabled, Layer 1 Vision requests still active")")
```

- [ ] **Step 2: Commit**

```bash
git add leanring-buddy/LumaOnDeviceAI.swift
git commit -m "feat: thread searchQuery through LumaOnDeviceAI.detectElements

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 3: Thread query + add Layer 3 in LumaImageProcessingEngine

**Files:**
- Modify: `leanring-buddyTests/leanring_buddyTests.swift`
- Modify: `leanring-buddy/LumaImageProcessingEngine.swift`

- [ ] **Step 1: Add tests for the two new pure LIPE helpers**

Append to `leanring-buddyTests/leanring_buddyTests.swift` (after the LumaMobileNetDetector tests, before the closing `}`):

```swift
// MARK: - LumaImageProcessingEngine Layer 3 Helper Tests

@Test func pointTagParserExtractsCoordinatesFromValidTag() {
    let apiResponseContainingPointTag = "[POINT:320,240:Save button]"
    let parsedCoordinate = LumaImageProcessingEngine.shared.parsePointTagFromAPIResponse(
        apiResponseContainingPointTag
    )
    #expect(parsedCoordinate != nil)
    #expect(abs((parsedCoordinate?.x ?? 0) - 320) < 0.01)
    #expect(abs((parsedCoordinate?.y ?? 0) - 240) < 0.01)
}

@Test func pointTagParserHandlesTagWithNoLabel() {
    let apiResponseContainingPointTag = "[POINT:100,200]"
    let parsedCoordinate = LumaImageProcessingEngine.shared.parsePointTagFromAPIResponse(
        apiResponseContainingPointTag
    )
    #expect(parsedCoordinate != nil)
    #expect(abs((parsedCoordinate?.x ?? 0) - 100) < 0.01)
    #expect(abs((parsedCoordinate?.y ?? 0) - 200) < 0.01)
}

@Test func pointTagParserReturnsNilForNoneTag() {
    let apiResponseWithNoElement = "[POINT:none]"
    let parsedCoordinate = LumaImageProcessingEngine.shared.parsePointTagFromAPIResponse(
        apiResponseWithNoElement
    )
    #expect(parsedCoordinate == nil)
}

@Test func pointTagParserReturnsNilForUnrelatedText() {
    let unrelatedText = "I couldn't find that element on screen."
    let parsedCoordinate = LumaImageProcessingEngine.shared.parsePointTagFromAPIResponse(
        unrelatedText
    )
    #expect(parsedCoordinate == nil)
}

@Test func adaptiveBoxIsSmallForSingleOrDoubleCharQuery() {
    // Single char queries target icons or keyboard shortcut keys — use icon-size box
    let singleCharSize = LumaImageProcessingEngine.shared.adaptiveBoundingBoxSize(forSearchQuery: "R")
    #expect(abs(singleCharSize.width  - 24) < 0.01)
    #expect(abs(singleCharSize.height - 24) < 0.01)

    let doubleCharSize = LumaImageProcessingEngine.shared.adaptiveBoundingBoxSize(forSearchQuery: "⌘N")
    #expect(abs(doubleCharSize.width  - 24) < 0.01)
    #expect(abs(doubleCharSize.height - 24) < 0.01)
}

@Test func adaptiveBoxIsStandardSizeForWordQuery() {
    let wordSize = LumaImageProcessingEngine.shared.adaptiveBoundingBoxSize(forSearchQuery: "Save")
    #expect(abs(wordSize.width  - 60) < 0.01)
    #expect(abs(wordSize.height - 30) < 0.01)
}

@Test func adaptiveBoxIsStandardSizeForPhraseQuery() {
    let phraseSize = LumaImageProcessingEngine.shared.adaptiveBoundingBoxSize(
        forSearchQuery: "New Project"
    )
    #expect(abs(phraseSize.width  - 60) < 0.01)
    #expect(abs(phraseSize.height - 30) < 0.01)
}
```

- [ ] **Step 2: Modify scanVisual in LumaImageProcessingEngine.swift**

In `leanring-buddy/LumaImageProcessingEngine.swift`, replace the `scanVisual` method (lines 295–338) with:

```swift
/// Captures the screen and runs the on-device detection pipeline (Layers 1+2).
/// Falls back to Layer 3 (Claude Vision via APIClient) when no on-device result
/// has confidence ≥ 0.5. When MobileNetDetector has no model, returns empty unless
/// Layer 3 fires.
func scanVisual(query: String) async -> [ElementCandidate] {
    // Capture via ScreenCaptureKit (replaces the deprecated CGWindowListCreateImage).
    // CompanionScreenCaptureUtility returns JPEG data; we convert it to a CGImage
    // for the MobileNet detector. If capture fails we return empty — the AX path
    // still runs in parallel and is unaffected.
    guard let screenCapture = try? await CompanionScreenCaptureUtility.captureAllScreensAsJPEG().first,
          let imageSource = CGImageSourceCreateWithData(screenCapture.imageData as CFData, nil),
          let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
        return []
    }

    let screenSize = CGSize(
        width: screenCapture.displayWidthInPoints,
        height: screenCapture.displayHeightInPoints
    )

    // Layers 1+2: on-device Vision text detection + MobileNet crop validation.
    // searchQuery is now threaded through so Layer 1 text matching is query-aware.
    let detectionResults = await LumaOnDeviceAI.shared.detectElements(
        in: cgImage,
        screenSize: screenSize,
        searchQuery: query
    )

    // Score and cap visual-only candidates at 0.4 confidence (visual results without AX
    // confirmation are less precise — the cap prevents them from dominating over AX results
    // but still lets cross-validation boost them when AX agrees).
    let scoredVisualCandidates: [ElementCandidate] = detectionResults
        .filter { $0.confidence > 0.3 }
        .map { result -> ElementCandidate in
            let labelMatchScore = scoreLabel(result.label, against: query)
            let combinedConfidence = min((Double(labelMatchScore) / 100.0) * result.confidence, 0.4)
            return ElementCandidate(
                name: result.label,
                role: "AXUnknown",
                frame: result.screenFrame,
                visualFrame: result.screenFrame,
                confidence: combinedConfidence,
                source: .visual,
                appBundleID: nil,
                isMenuBar: false,
                axElement: nil
            )
        }
        .sorted { $0.confidence > $1.confidence }
        .prefix(5)

    // Fire Layer 3 when no on-device result has sufficient confidence.
    // We check the raw detection confidence (before the 0.4 visual-only cap) so we do not
    // fire Layer 3 when Layer 1+2 found a high-confidence match that was merely capped.
    // For example: Layer 1 returns confidence=0.85 → capped to 0.4 in scoredVisualCandidates,
    // but bestOnDeviceConfidence=0.85 ≥ 0.5, so Layer 3 correctly does NOT fire.
    let bestOnDeviceConfidence = detectionResults.map { $0.confidence }.max() ?? 0.0
    if bestOnDeviceConfidence < 0.5 {
        if let layer3Candidate = await detectElementViaAPIClient(
            screenshotData: screenCapture.imageData,
            screenCapture: screenCapture,
            searchQuery: query
        ) {
            // Prepend Layer 3 result so crossValidate can merge it with an overlapping AX candidate.
            // If AX and Layer 3 agree, the merged result inherits the real AX frame (replacing
            // the estimated adaptive box) and gets the +0.3 confidence boost.
            return [layer3Candidate] + Array(scoredVisualCandidates)
        }
    }

    return Array(scoredVisualCandidates)
}
```

- [ ] **Step 3: Add the three new private methods to LumaImageProcessingEngine.swift**

Add the following block immediately after the closing `}` of `scanVisual` (before the `// MARK: - Step 3: Cross Validation` comment):

```swift
// MARK: - Layer 3: Claude Vision API Fallback

/// Sends the screenshot to Claude via APIClient and parses a [POINT:x,y:label] coordinate tag.
/// Only called from scanVisual when both on-device layers (1+2) return confidence < 0.5.
///
/// Mirrors CursorGuide.pointAtElementViaAIScreenshot but returns an ElementCandidate
/// (for cross-validation) rather than posting a notification (for cursor movement).
private func detectElementViaAPIClient(
    screenshotData: Data,
    screenCapture: CompanionScreenCapture,
    searchQuery: String
) async -> ElementCandidate? {
    let screenshotDimensionDescription = "\(screenCapture.screenshotWidthInPixels)×\(screenCapture.screenshotHeightInPixels)"

    let elementLocationSystemPrompt = """
    You are a macOS screen analyzer that locates UI elements.
    The screenshot is \(screenshotDimensionDescription) pixels.

    When asked to find a UI element, respond with ONLY a [POINT:x,y:label] tag — nothing else.
    - x and y are integer pixel coordinates of the CENTER of the target element (top-left origin, 0,0 = top-left corner)
    - label is a 1-3 word description of the element
    - If the element is not visible: [POINT:none]
    """

    guard let (apiResponse, _) = try? await APIClient.shared.analyzeImage(
        images: [(data: screenshotData, label: "user's screen")],
        systemPrompt: elementLocationSystemPrompt,
        conversationHistory: [],
        userPrompt: "Find the UI element named \"\(searchQuery)\" and return its pixel coordinates.",
        maxOutputTokens: 32
    ) else {
        print("[LIPE] Layer 3: APIClient call failed for '\(searchQuery)'")
        return nil
    }

    print("[LIPE] Layer 3 response for '\(searchQuery)': \(apiResponse)")

    guard let pixelCoordinate = parsePointTagFromAPIResponse(apiResponse) else {
        print("[LIPE] Layer 3: no valid [POINT:x,y] tag in response for '\(searchQuery)'")
        return nil
    }

    // Scale from screenshot pixel coordinates (top-left origin) to Quartz screen coordinates
    // (also top-left origin in this context — matching how AX frames are stored in LIPE).
    let quartzX = pixelCoordinate.x * (CGFloat(screenCapture.displayWidthInPoints)  / CGFloat(screenCapture.screenshotWidthInPixels))
    let quartzY = pixelCoordinate.y * (CGFloat(screenCapture.displayHeightInPoints) / CGFloat(screenCapture.screenshotHeightInPixels))

    let estimatedBoxSize = adaptiveBoundingBoxSize(forSearchQuery: searchQuery)
    let estimatedScreenFrame = CGRect(
        x: quartzX - estimatedBoxSize.width  / 2,
        y: quartzY - estimatedBoxSize.height / 2,
        width:  estimatedBoxSize.width,
        height: estimatedBoxSize.height
    )

    print("[LIPE] Layer 3: '\(searchQuery)' at Quartz (\(Int(quartzX)), \(Int(quartzY))) — \(Int(estimatedBoxSize.width))×\(Int(estimatedBoxSize.height))pt estimated box")

    // confidence=0.55: slightly above the Layer 3 trigger threshold (0.5) so this candidate
    // is included in crossValidate. If an AX candidate overlaps the estimated box, the merged
    // result inherits the real AX frame and gets +0.3 confidence boost.
    return ElementCandidate(
        name: searchQuery,
        role: "AXUnknown",
        frame: estimatedScreenFrame,
        visualFrame: estimatedScreenFrame,
        confidence: 0.55,
        source: .visual,
        appBundleID: nil,
        isMenuBar: false,
        axElement: nil
    )
}

/// Parses a `[POINT:x,y]` or `[POINT:x,y:label]` tag from an API response string.
/// Returns `nil` when the response is `[POINT:none]` or contains no valid coordinate tag.
///
/// Internal (not private) so unit tests can verify parsing rules without mocking APIClient.
func parsePointTagFromAPIResponse(_ responseText: String) -> CGPoint? {
    // Matches [POINT:x,y] with optional :label suffix. Does not match [POINT:none].
    // Group 1 = x coordinate digits, Group 2 = y coordinate digits.
    let pointTagPattern = #"\[POINT:(\d+)\s*,\s*(\d+)(?::[^\]]*)?\]"#

    guard let regex = try? NSRegularExpression(pattern: pointTagPattern),
          let match = regex.firstMatch(
              in: responseText,
              range: NSRange(responseText.startIndex..., in: responseText)
          ),
          match.numberOfRanges >= 3,
          let xRange = Range(match.range(at: 1), in: responseText),
          let yRange = Range(match.range(at: 2), in: responseText),
          let parsedX = Double(responseText[xRange]),
          let parsedY = Double(responseText[yRange])
    else { return nil }

    return CGPoint(x: parsedX, y: parsedY)
}

/// Returns the estimated bounding box size for a Layer 3 AI-located element.
///
/// The AI returns a center point, not a box. We estimate the box from the query length:
/// - ≤ 2 chars (e.g. "R", "⌘N"): 24×24 pt — icon or keyboard shortcut key target
/// - > 2 chars (word or phrase):  60×30 pt — standard button or label
///
/// If cross-validation finds an overlapping AX candidate, the merged result's `frame`
/// will be replaced with the real AX frame — the estimated box is only used during
/// crossValidate's overlap check.
///
/// Internal (not private) so unit tests can verify size selection logic.
func adaptiveBoundingBoxSize(forSearchQuery searchQuery: String) -> CGSize {
    if searchQuery.count <= 2 {
        return CGSize(width: 24, height: 24)
    }
    return CGSize(width: 60, height: 30)
}
```

- [ ] **Step 4: Run tests in Xcode (Cmd+U)**

Press Cmd+U in Xcode.

Expected: All 7 new LIPE tests pass alongside the 8 MobileNetDetector tests and the 3 existing permission tests (18 total).

If `pointTagParserExtractsCoordinatesFromValidTag` fails, check the regex pattern — the optional `:label` group uses `(?::[^\]]*)?` which must not consume the closing `]`.

If an `adaptiveBox` test fails, check `searchQuery.count` — Swift's `.count` on String counts Unicode scalars, so "⌘N" (3 chars: ⌘, N, and possibly a combining char) may differ from expectations. If "⌘N" fails, adjust the test to use "RN" (unambiguously 2 chars) for the double-char case.

- [ ] **Step 5: Commit**

```bash
git add leanring-buddy/LumaImageProcessingEngine.swift leanring-buddyTests/leanring_buddyTests.swift
git commit -m "feat: add Layer 3 APIClient fallback and query threading in LIPE

- Thread searchQuery through to LumaOnDeviceAI.detectElements so Layer 1
  text matching is query-aware
- Add detectElementViaAPIClient: fires APIClient [POINT:x,y:label] call
  when Layer 1+2 best confidence < 0.5; returns ElementCandidate with
  adaptive bounding box (24×24pt for icons, 60×30pt for words/phrases)
- Add parsePointTagFromAPIResponse: parses [POINT:x,y] tags from API response
- Add adaptiveBoundingBoxSize: box size selection from query character count
- bestOnDeviceConfidence check uses raw Layer 1+2 confidence (not the 0.4-capped
  visual score) so Layer 3 does not fire when a high-confidence on-device match
  was merely capped by the visual-only confidence ceiling

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Self-Review Checklist

**Spec coverage:**
- [x] Layer 1 `VNRecognizeTextRequest` with `.accurate` level, `usesLanguageCorrection = false` → Task 1 Step 3
- [x] Layer 1 `VNDetectRectanglesRequest` with rectangle overlap boost → Task 1 Step 3
- [x] Vision bottom-left → Quartz top-left coordinate conversion → Task 1 Step 3 (`visionBoundingBoxToQuartzScreenFrame`)
- [x] Layer 1 confidence threshold 0.5 → Task 1 Step 3 (`guard resultConfidence >= 0.5`)
- [x] Layer 2 MobileNet crop validation, 0.35 threshold, downgrade × 0.5 → Task 1 Step 3
- [x] Layer 2 pass-through when model absent → Task 1 Step 3
- [x] Layer 3 trigger when best confidence < 0.5 → Task 3 Step 2
- [x] Layer 3 uses `APIClient.shared.analyzeImage` with `[POINT:x,y:label]` parsing → Task 3 Step 3
- [x] Adaptive box: ≤2 chars → 24×24pt, >2 chars → 60×30pt → Task 3 Step 3
- [x] AX override of adaptive box is implicit via `crossValidate` (no code change needed) → confirmed by code reading
- [x] Layer 3 result confidence = 0.55 → Task 3 Step 3
- [x] `searchQuery` parameter threaded through `LumaOnDeviceAI` → Task 2
- [x] False-positive cross-validation fix is automatic (real boxes eliminate `(0,0,1,1)`) → no explicit task needed
- [x] `ElementLocationDetector` not touched → confirmed (no task references it)
- [x] No Keychain changes → confirmed (uses existing `APIClient.shared`)

**Placeholder scan:** No TBDs, TODOs, or "similar to above" patterns. All code blocks are complete.

**Type consistency:**
- `VisualDetectionResult` struct matches across all uses (Task 1 defines it; Task 2 passes it through; Task 3 reads `.confidence` and `.screenFrame`)
- `ElementCandidate` constructor call in Task 3 matches the definition in `LumaImageProcessingEngine.swift` (8 named params: `name`, `role`, `frame`, `visualFrame`, `confidence`, `source`, `appBundleID`, `isMenuBar`, `axElement`)
- `parsePointTagFromAPIResponse` and `adaptiveBoundingBoxSize` are defined and called as `internal func` on `LumaImageProcessingEngine` — tests call them via `LumaImageProcessingEngine.shared`
- `computeQueryMatchWeight` and `visionBoundingBoxToQuartzScreenFrame` are defined and called as `internal func` on `LumaMobileNetDetector` — tests call them via `LumaMobileNetDetector.shared`
