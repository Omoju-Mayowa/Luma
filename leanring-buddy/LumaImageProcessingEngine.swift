//
//  LumaImageProcessingEngine.swift
//  leanring-buddy
//
//  Combines Accessibility API + screenshot analysis to locate UI elements with
//  high confidence. Both sources run in parallel and their results are cross-validated:
//  when they agree (frames overlap), confidence is boosted and source is .both.
//
//  This is the single authority for "find element X on screen" in the walkthrough
//  system. CursorGuide.pointAtElement remains available for one-shot pointing from
//  the CompanionManager voice flow.
//

import AppKit
import ApplicationServices
import Foundation
import ImageIO

// MARK: - SourceType

/// Which detection path(s) found a given element candidate.
enum SourceType: Equatable {
    /// Found only through the Accessibility API.
    case accessibility
    /// Found only through screenshot/visual analysis (MobileNet or AI).
    case visual
    /// Confirmed by both Accessibility API and visual analysis — highest reliability.
    case both
}

// MARK: - ElementCandidate

/// A UI element candidate returned by LumaImageProcessingEngine.
struct ElementCandidate: Identifiable {
    let id: UUID = UUID()
    let name: String
    let role: String
    /// Frame in Quartz/AX coordinates (top-left origin, Y↓). From Accessibility API.
    /// Use LumaImageProcessingEngine.toScreenPoint(_:) to convert to AppKit before using.
    let frame: CGRect
    /// Frame from screenshot analysis in Quartz/AX coordinates, if available.
    let visualFrame: CGRect?
    /// 0.0–1.0 confidence in this candidate being the correct element.
    let confidence: Double
    /// Which source(s) found this candidate.
    let source: SourceType
    let appBundleID: String?
    let isMenuBar: Bool
}

// MARK: - LumaImageProcessingEngine

/// Central element-finding authority for the walkthrough system.
/// Runs AX scan and visual scan in parallel, cross-validates results, and
/// returns the highest-confidence candidate above a minimum threshold.
@MainActor
final class LumaImageProcessingEngine {
    static let shared = LumaImageProcessingEngine()
    private init() {}

    /// Minimum confidence required to return a candidate. Below this, nil is returned.
    private let minimumConfidenceThreshold: Double = 0.3

    /// Frame overlap fraction required to merge an AX candidate with a visual candidate.
    private let crossValidationOverlapThreshold: Double = 0.6

    // MARK: - Public API

    /// Finds the best matching element for `query` using both AX and visual scanning.
    ///
    /// - Parameters:
    ///   - query: The visible label or name of the target UI element.
    ///   - appBundleID: The app the element lives in, or nil for the frontmost app.
    ///   - isMenuBar: True if the element is expected to be in the macOS menu bar.
    /// - Returns: The highest-confidence candidate, or nil if nothing meets the threshold.
    func findElement(
        query: String,
        appBundleID: String?,
        isMenuBar: Bool
    ) async -> ElementCandidate? {

        // Run both scans in parallel — AX is fast, visual takes a screenshot + optional ML
        async let axCandidates = scanAccessibilityTree(query: query, appBundleID: appBundleID, isMenuBar: isMenuBar)
        async let visualCandidates = scanVisual(query: query)

        let (axResults, visualResults) = await (axCandidates, visualCandidates)

        let mergedCandidates = crossValidate(axCandidates: axResults, visualCandidates: visualResults)

        let bestCandidate = mergedCandidates
            .sorted { $0.confidence > $1.confidence }
            .first(where: { $0.confidence >= minimumConfidenceThreshold })

        if let best = bestCandidate {
            print("[LIPE] Best match: '\(best.name)' confidence: \(String(format: "%.2f", best.confidence)) source: \(best.source)")
        } else {
            print("[LIPE] No candidate above threshold \(minimumConfidenceThreshold) for query '\(query)'")
        }

        return bestCandidate
    }

    /// Notifies the overlay to animate the Luma cursor to `candidate.frame`.
    /// Luma NEVER moves the OS cursor — only the blue overlay cursor animates.
    /// `bubbleText` is shown in the small speech bubble next to the cursor when it arrives.
    func pointCursor(at candidate: ElementCandidate, bubbleText: String? = nil) {
        let screenPoint = toScreenPoint(candidate.frame)
        print("[LIPE] Pointing Luma cursor to \(screenPoint) for '\(candidate.name)'")

        var userInfo: [String: Any] = [
            CursorGuide.targetPointUserInfoKey: NSValue(point: screenPoint)
        ]
        if let text = bubbleText {
            userInfo[CursorGuide.bubbleTextUserInfoKey] = text
        }
        NotificationCenter.default.post(
            name: CursorGuide.pointAtNotificationName,
            object: nil,
            userInfo: userInfo
        )
    }

    // MARK: - Step 1: Accessibility API Scan

    /// Scans the target app's AX tree (or menu bar) and returns the top 5 scored candidates.
    func scanAccessibilityTree(
        query: String,
        appBundleID: String?,
        isMenuBar: Bool
    ) async -> [ElementCandidate] {
        var collectedElements: [CollectedAXElement] = []

        if isMenuBar {
            // Menu bar scan: frontmost app menu bar + ControlCenter + SystemUIServer
            collectMenuBarElements(into: &collectedElements)
        } else {
            // App scan: specific app or frontmost
            let rootPID: pid_t?
            if let bundleID = appBundleID,
               let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
                rootPID = app.processIdentifier
            } else {
                rootPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
            }

            if let pid = rootPID {
                let appElement = AXUIElementCreateApplication(pid)
                collectAXElements(from: appElement, into: &collectedElements, depth: 0, maxDepth: 12)
            }
        }

        let scored = collectedElements
            .map { element -> (element: CollectedAXElement, score: Int) in
                (element: element, score: scoreElement(element, query: query))
            }
            .filter { $0.score > 0 }
            .sorted { $0.score > $1.score }
            .prefix(5)

        print("[LIPE] AX scan '\(query)': \(scored.count) candidate(s) of \(collectedElements.count) total")
        for candidate in scored {
            print("[LIPE]   AX '\(candidate.element.title)' role=\(candidate.element.role) score=\(candidate.score)")
        }

        return scored.map { item in
            ElementCandidate(
                name: item.element.title,
                role: item.element.role,
                frame: item.element.axFrame,
                visualFrame: nil,
                confidence: Double(item.score) / 100.0,
                source: .accessibility,
                appBundleID: appBundleID,
                isMenuBar: isMenuBar
            )
        }
    }

    // MARK: - Step 2: Visual / Screenshot Scan

    /// Captures the screen and attempts visual element detection.
    /// When MobileNetDetector has no model, falls back to returning empty (the AI screenshot
    /// path in CursorGuide handles actual visual pointing separately).
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
        let detectionResults = await LumaOnDeviceAI.shared.detectElements(
            in: cgImage,
            screenSize: screenSize
        )

        // Score detection results against the query
        let scored = detectionResults
            .filter { $0.confidence > 0.3 }
            .map { result -> ElementCandidate in
                let labelMatchScore = scoreLabel(result.label, against: query)
                let combinedConfidence = min((Double(labelMatchScore) / 100.0) * result.confidence, 0.4)
                // Visual-only results are capped at 0.4 — they're less precise without AX confirmation
                return ElementCandidate(
                    name: result.label,
                    role: "AXUnknown",
                    frame: result.screenFrame,
                    visualFrame: result.screenFrame,
                    confidence: combinedConfidence,
                    source: .visual,
                    appBundleID: nil,
                    isMenuBar: false
                )
            }
            .sorted { $0.confidence > $1.confidence }
            .prefix(5)

        return Array(scored)
    }

    // MARK: - Step 3: Cross Validation

    /// Merges AX candidates with visual candidates. When an AX frame and visual frame
    /// overlap by more than `crossValidationOverlapThreshold`, they are merged into a
    /// single .both candidate with a 0.3 confidence bonus.
    private func crossValidate(
        axCandidates: [ElementCandidate],
        visualCandidates: [ElementCandidate]
    ) -> [ElementCandidate] {
        var results: [ElementCandidate] = []
        var matchedVisualIndices: Set<Int> = []

        for axCandidate in axCandidates {
            var bestVisualMatch: (index: Int, overlap: Double)?

            for (visualIndex, visualCandidate) in visualCandidates.enumerated() {
                let overlap = frameOverlapFraction(axCandidate.frame, visualCandidate.frame)
                if overlap > crossValidationOverlapThreshold {
                    if bestVisualMatch == nil || overlap > bestVisualMatch!.overlap {
                        bestVisualMatch = (index: visualIndex, overlap: overlap)
                    }
                }
            }

            if let match = bestVisualMatch {
                // Both sources agree — merge and boost confidence
                matchedVisualIndices.insert(match.index)
                let mergedConfidence = min(axCandidate.confidence + 0.3, 1.0)
                let merged = ElementCandidate(
                    name: axCandidate.name,
                    role: axCandidate.role,
                    frame: axCandidate.frame,
                    visualFrame: visualCandidates[match.index].visualFrame,
                    confidence: mergedConfidence,
                    source: .both,
                    appBundleID: axCandidate.appBundleID,
                    isMenuBar: axCandidate.isMenuBar
                )
                results.append(merged)
            } else {
                // AX only — use as-is
                results.append(axCandidate)
            }
        }

        // Add unmatched visual candidates (they remain visual-only)
        for (index, visualCandidate) in visualCandidates.enumerated() {
            if !matchedVisualIndices.contains(index) {
                results.append(visualCandidate)
            }
        }

        return results
    }

    // MARK: - Step 4: Coordinate Conversion

    /// Converts an AX frame (Quartz coordinates, top-left origin, Y↓) to an AppKit screen
    /// point (bottom-left origin, Y↑) at the element's center. Ready to pass to pointCursor(at:).
    func toScreenPoint(_ axFrame: CGRect) -> CGPoint {
        // AX/Quartz coordinate system: origin at the top-left of the MAIN display, Y increases downward.
        // AppKit coordinate system: origin at the bottom-left of the MAIN display, Y increases upward.
        //
        // The correct Y-flip uses the MAIN screen's height (not the max across all screens):
        //   appKitY = NSScreen.main.frame.height - quartzY
        //
        // Using max($0, $1.frame.maxY) across all screens gives wrong results when a secondary
        // screen is taller than the primary — elements on the primary display get shifted upward
        // by the height difference. Using just mainH is always correct because Quartz Y=0 always
        // corresponds to AppKit Y=mainH regardless of how other monitors are arranged.
        let mainScreenHeight = NSScreen.main?.frame.height ?? 0
        return CGPoint(x: axFrame.midX, y: mainScreenHeight - axFrame.midY)
    }

    // MARK: - Step 5: Menu Bar Scan

    /// Scans the menu bar hierarchy (frontmost app menu bar + ControlCenter + SystemUIServer).
    func scanMenuBar(query: String) async -> [ElementCandidate] {
        var collectedElements: [CollectedAXElement] = []
        collectMenuBarElements(into: &collectedElements)

        let scored = collectedElements
            .map { (element: $0, score: scoreElement($0, query: query)) }
            .filter { $0.score > 0 }
            .sorted { $0.score > $1.score }
            .prefix(5)

        return scored.map { item in
            ElementCandidate(
                name: item.element.title,
                role: item.element.role,
                frame: item.element.axFrame,
                visualFrame: nil,
                confidence: Double(item.score) / 100.0,
                source: .accessibility,
                appBundleID: nil,
                isMenuBar: true
            )
        }
    }

    // MARK: - AX Tree Traversal

    private struct CollectedAXElement {
        let element: AXUIElement
        let title: String
        let role: String
        let axFrame: CGRect
    }

    private func collectAXElements(
        from element: AXUIElement,
        into array: inout [CollectedAXElement],
        depth: Int,
        maxDepth: Int
    ) {
        guard depth < maxDepth else { return }

        let title       = readStringAttribute(kAXTitleAttribute, from: element)
        let description = readStringAttribute(kAXDescriptionAttribute, from: element)
        let value       = readStringAttribute(kAXValueAttribute, from: element)
        let role        = readStringAttribute(kAXRoleAttribute, from: element) ?? "AXUnknown"

        let bestTitle = [title, description, value]
            .compactMap { $0 }
            .first(where: { !$0.isEmpty })

        if let elementTitle = bestTitle {
            var frameRect = CGRect.zero
            var frameRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, "AXFrame" as CFString, &frameRef) == .success,
               let frameValue = frameRef {
                AXValueGetValue(frameValue as! AXValue, .cgRect, &frameRect)
            }

            if frameRect.width > 0 && frameRect.height > 0 {
                array.append(CollectedAXElement(
                    element: element,
                    title: elementTitle,
                    role: role,
                    axFrame: frameRect
                ))
            }
        }

        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else { return }

        for child in children {
            collectAXElements(from: child, into: &array, depth: depth + 1, maxDepth: maxDepth)
        }
    }

    private func collectMenuBarElements(into array: inout [CollectedAXElement]) {
        if let frontmostApp = NSWorkspace.shared.frontmostApplication {
            let appElement = AXUIElementCreateApplication(frontmostApp.processIdentifier)
            var menuBarRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(appElement, kAXMenuBarAttribute as CFString, &menuBarRef) == .success,
               let menuBarElement = menuBarRef {
                collectAXElements(from: menuBarElement as! AXUIElement, into: &array, depth: 0, maxDepth: 12)
            }
        }

        let systemProcessBundleIDs = ["com.apple.controlcenter", "com.apple.systemuiserver"]
        for bundleID in systemProcessBundleIDs {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
                let appElement = AXUIElementCreateApplication(app.processIdentifier)
                collectAXElements(from: appElement, into: &array, depth: 0, maxDepth: 12)
            }
        }
    }

    // MARK: - Scoring

    private func scoreElement(_ element: CollectedAXElement, query: String) -> Int {
        var score = scoreLabel(element.title, against: query, role: element.role)
        guard score > 0 else { return 0 }

        // Penalize large elements — they are almost always container windows/groups,
        // not the clickable target. A Finder window titled "Downloads" would otherwise
        // beat the actual folder icon with the same exact-match score, causing the
        // cursor to fly to the window's center rather than the icon.
        //
        // We use max(1, ...) rather than allowing negative scores so that a container
        // is still included in results (with low priority) when it's the ONLY match
        // for a query — preventing an unnecessary fallback to AI screenshot pointing.
        let elementArea = element.axFrame.width * element.axFrame.height
        if elementArea > 200_000 {
            // Very large: likely a window, dialog, or full-pane content area
            score = max(1, score - 50)
        } else if elementArea > 60_000 {
            // Medium-large: likely a group, scroll area, or sidebar section
            score = max(1, score - 25)
        }

        // Penalize non-interactive container roles
        switch element.role {
        case "AXWindow", "AXSheet", "AXDrawer":
            score = max(1, score - 40)
        case "AXGroup", "AXScrollArea", "AXList", "AXTable", "AXOutline":
            score = max(1, score - 20)
        case "AXStaticText", "AXImage":
            // Text labels and images are rarely the action target
            score = max(1, score - 8)
        default:
            break
        }

        return score
    }

    private func scoreLabel(_ label: String, against query: String, role: String = "AXUnknown") -> Int {
        var score = 0
        let labelLower = label.lowercased()
        let queryLower = query.lowercased()

        if labelLower == queryLower {
            score += 100
        } else if labelLower.contains(queryLower) {
            score += 50
        } else if queryLower.contains(labelLower) && labelLower.count > 3 {
            score += 30
        }

        // Role bonuses — applied in scoreElement after size adjustments
        switch role {
        case "AXMenuBarItem": score += 15
        case "AXButton", "AXMenuItem": score += 10
        default: break
        }

        return score
    }

    // MARK: - Frame Overlap

    /// Returns the fraction of `frame1` that overlaps with `frame2`.
    private func frameOverlapFraction(_ frame1: CGRect, _ frame2: CGRect) -> Double {
        let intersection = frame1.intersection(frame2)
        guard !intersection.isNull && frame1.area > 0 else { return 0.0 }
        return Double(intersection.area / frame1.area)
    }

    // MARK: - AX Attribute Helpers

    private func readStringAttribute(_ attribute: String, from element: AXUIElement) -> String? {
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &valueRef) == .success,
              let stringValue = valueRef as? String,
              !stringValue.isEmpty else { return nil }
        return stringValue
    }
}

// MARK: - CGRect Area

private extension CGRect {
    var area: CGFloat { width * height }
}
