# 3-Layer Visual Detection Pipeline

**Date:** 2026-04-19
**Status:** Approved — ready for implementation

---

## Problem

`LumaMobileNetDetector.detectElements` casts Vision results to `VNClassificationObservation`, which carries no spatial data. All results receive a hardcoded `normalizedBoundingBox = CGRect(x:0, y:0, width:1, height:1)` (full screen).

In `LumaImageProcessingEngine.crossValidate`, `frameOverlapFraction(axFrame, fullScreenBox)` always returns `1.0` because the AX element frame is fully contained within the full-screen box. This gives every AX candidate a spurious +0.3 confidence boost regardless of whether the visual and AX detections actually agree. The cursor then moves to AX-derived coordinates without any genuine visual confirmation, causing misses in apps like Figma and Spotify that use custom renderers bypassing the AX API.

---

## Solution Overview

Replace the single broken MobileNet classification call with a 3-layer pipeline:

| Layer | Mechanism | Runs when |
|-------|-----------|-----------|
| 1 | Vision Framework: `VNRecognizeTextRequest` + `VNDetectRectanglesRequest` | Always (free, on-device) |
| 2 | MobileNetV2 crop validation of Layer 1 coordinates | Layer 1 returns a result ≥ 0.5 confidence |
| 3 | `APIClient.shared.analyzeImage` → `[POINT:x,y:label]` parsing | Layer 1+2 best confidence < 0.5 |

---

## Files Changed

| File | Change summary |
|------|----------------|
| `LumaMobileNetDetector.swift` | Implement Layer 1 + Layer 2; add `searchQuery` parameter |
| `LumaOnDeviceAI.swift` | Thread `searchQuery` through `detectElements` |
| `LumaImageProcessingEngine.swift` | Thread `query` into `detectElements`; add Layer 3 private method |

---

## Data Flow

```
scanVisual(query: String)
  │
  ├─ capture screenshot → jpegData + CGImage + CompanionScreenCapture metadata
  │
  ├─ LumaOnDeviceAI.detectElements(cgImage, screenSize, searchQuery: query)
  │       │
  │       └─ LumaMobileNetDetector.detectElements(cgImage, screenSize, searchQuery: query)
  │               │
  │               ├─ Layer 1a: VNRecognizeTextRequest
  │               │     → VNRecognizedTextObservation[] with real boundingBox
  │               │     → score each against searchQuery → keep ≥ 0.5
  │               │
  │               ├─ Layer 1b: VNDetectRectanglesRequest
  │               │     → boost text results that overlap a rectangle (+0.1, capped 1.0)
  │               │
  │               └─ Layer 2: MobileNetV2 crop-validates Layer 1 best center
  │                     → passes (confidence ≥ 0.35): result unchanged
  │                     → fails (confidence < 0.35): result confidence ×= 0.5
  │                     → model absent: pass-through
  │
  ├─ if best Layer 1+2 confidence < 0.5:
  │       └─ Layer 3: detectElementViaAPIClient(jpegData, screenCapture, query)
  │               → APIClient.shared.analyzeImage → [POINT:x,y:label]
  │               → adaptive bounding box (see below)
  │               → ElementCandidate confidence = 0.55
  │
  └─ crossValidate(axCandidates, visualCandidates)
         → real bounding boxes → meaningful overlap fractions
         → no more spurious +0.3 boost for every AX candidate
```

---

## Layer 1: VNRecognizeTextRequest + VNDetectRectanglesRequest

### Text Recognition (primary signal)

- Recognition level: `.accurate` (better quality; runs before any API call, worth the cost)
- `usesLanguageCorrection = false` (faster; raw text better for label matching)
- Per observation scoring:

  | Match type | `queryMatchWeight` |
  |------------|-------------------|
  | Exact match (case-insensitive) | 1.0 |
  | Label contains query | 0.7 |
  | Query contains label (label length > 3) | 0.4 |
  | No match | 0.0 (discarded) |

  `resultConfidence = recognitionConfidence × queryMatchWeight`
  Results below 0.5 are discarded from Layer 1.

- **Coordinate conversion**: Vision uses normalized coordinates with bottom-left origin. Convert to Quartz screen coordinates (top-left origin, absolute points) for AX cross-validation:
  ```
  quartzX      = boundingBox.minX  × screenWidth
  quartzY      = (1.0 - boundingBox.maxY) × screenHeight
  quartzWidth  = boundingBox.width × screenWidth
  quartzHeight = boundingBox.height × screenHeight
  ```

### Rectangle Detection (corroborating evidence)

- `minimumAspectRatio = 0.1`, `maximumAspectRatio = 10.0`
- `minimumSize = 0.01` (1% of image dimension), `maximumObservations = 20`
- A rectangle that overlaps > 50% with a passing text observation's bounding box boosts that text result's confidence by +0.1 (capped at 1.0)
- Rectangles with no nearby matching text observation are ignored — they do not produce standalone results

---

## Layer 2: MobileNetV2 Validation Gate

For each Layer 1 result that reaches ≥ 0.5 confidence:

1. Extract the center point of the result's Quartz `screenFrame`
2. Crop a 160×160 pt region centered on that point (same radius as `LumaMLEngine.validateCoordinate`)
3. Run `VNCoreMLRequest` (MobileNetV2, `VNClassificationObservation`)
4. Apply decision:

| MobileNetV2 top-class confidence | Decision |
|----------------------------------|----------|
| ≥ 0.35 | Pass — result confidence unchanged |
| < 0.35 | Downgrade — result confidence ×= 0.5 (falls below Layer 3 trigger of 0.5) |
| Model not bundled | Pass-through — all Layer 1 results pass as-is |

The 0.35 threshold is unchanged from `LumaMLEngine.validateCoordinate` (proven in production).

---

## Layer 3: APIClient [POINT:x,y:label] Fallback

Fires only when no Layer 1+2 result reaches 0.5 confidence.

### Implementation

New private method on `LumaImageProcessingEngine`:

```swift
private func detectElementViaAPIClient(
    screenshotData: Data,
    screenCapture: CompanionScreenCapture,
    searchQuery: String
) async -> ElementCandidate?
```

Steps:
1. Call `APIClient.shared.analyzeImage` with `[POINT:x,y:label]`-only system prompt (mirrors `CursorGuide.pointAtElementViaAIScreenshot`)
2. Parse response using the same `[POINT:x,y]` regex from `CursorGuide.parseAIPointingResponse`
3. Scale pixel coordinate to Quartz screen coordinates using `screenCapture` metadata:
   ```
   quartzX = pixelX × (displayWidthInPoints  / screenshotWidthInPixels)
   quartzY = pixelY × (displayHeightInPoints / screenshotHeightInPixels)
   ```
4. Build an adaptive bounding box centered on `(quartzX, quartzY)` (see Adaptive Box section)
5. Return `ElementCandidate` with `source: .visual`, `confidence: 0.55`

The Layer 3 result is prepended to the scored Layer 1+2 candidates before cross-validation so it can be merged with an overlapping AX candidate and upgraded to `.both`.

### Adaptive Bounding Box

The AI returns a point, not a box. The estimated box size depends on the query:

| Query length | Box size | Rationale |
|--------------|----------|-----------|
| ≤ 2 characters (e.g. "R", "V") | 24×24 pt | Icon or single-character keyboard shortcut target |
| > 2 characters (word or phrase) | 60×30 pt | Standard button / label |

Box is centered on the returned coordinate.

**AX override**: During `crossValidate`, if an AX candidate's frame overlaps the estimated box, the merged result uses the real AX frame. This is implicit — `crossValidate` already writes `axCandidate.frame` to the merged `ElementCandidate.frame`. No special handling needed.

---

## Confidence Thresholds (summary)

| Gate | Value |
|------|-------|
| Layer 1 text match minimum | 0.5 |
| Layer 2 MobileNet pass | ≥ 0.35 |
| Layer 2 MobileNet reject | < 0.35 → result confidence ×= 0.5 |
| Layer 3 trigger | best Layer 1+2 result < 0.5 |
| Layer 3 result confidence | 0.55 |

---

## Signature Changes

```swift
// LumaMobileNetDetector
// Before:
func detectElements(in image: CGImage, screenSize: CGSize) async -> [VisualDetectionResult]
// After:
func detectElements(in image: CGImage, screenSize: CGSize, searchQuery: String) async -> [VisualDetectionResult]

// LumaOnDeviceAI
// Before:
func detectElements(in image: CGImage, screenSize: CGSize) async -> [VisualDetectionResult]
// After:
func detectElements(in image: CGImage, screenSize: CGSize, searchQuery: String) async -> [VisualDetectionResult]

// LumaImageProcessingEngine.scanVisual — no signature change
// query is already a parameter; now threaded through to detectElements
```

---

## False-Positive Cross-Validation Fix

The `(0,0,1,1)` full-screen bounding box bug is automatically eliminated: Layer 1 returns real text-block and rectangle bounding boxes. `frameOverlapFraction` in `crossValidate` now receives meaningful frames and produces correct overlap fractions. No changes to `crossValidate` or `frameOverlapFraction` are needed.

---

## Out of Scope

- `ElementLocationDetector.swift` — not touched
- Keychain changes — none required; Layer 3 uses existing `openrouter_api_key` via `APIClient.shared`
- `CursorGuide.pointAtElementViaAIScreenshot` — not changed; Layer 3 mirrors its approach independently
- New `.mlmodel` files — Layer 2 gracefully skips if MobileNetV2 is not bundled
