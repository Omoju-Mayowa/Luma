//
//  CursorGuide.swift
//  leanring-buddy
//
//  Points the OS cursor and the Luma overlay cursor at a named UI element.
//
//  Coordinate system notes (the source of the original bug):
//  ─────────────────────────────────────────────────────────
//  The macOS Accessibility API returns AXFrame values in AppKit/Cocoa
//  screen coordinates: origin at the BOTTOM-LEFT of the primary display,
//  Y increases upward.
//
//  CGDisplayMoveCursorToPoint and CGEvent use Quartz/CoreGraphics coordinates:
//  origin at the TOP-LEFT of the primary display, Y increases downward.
//
//  These must be explicitly converted before moving the cursor. Passing an
//  AX frame center directly to CGDisplayMoveCursorToPoint will place the
//  cursor at the vertically-mirrored wrong position — which was the original bug.
//

import AppKit
import ApplicationServices
import Foundation

// MARK: - CursorGuide

@MainActor
final class CursorGuide {
    static let shared = CursorGuide()

    // Notification posted so OverlayWindowManager animates the Luma cursor to the target.
    static let pointAtNotificationName = NSNotification.Name("lumaWalkthroughPointAt")

    // Notification to clear any active pointer guidance from the overlay.
    static let clearPointerNotificationName = NSNotification.Name("lumaWalkthroughClearPointer")

    // userInfo key for the target CGPoint (wrapped in NSValue, in AppKit coordinates).
    static let targetPointUserInfoKey = "targetPoint"

    private init() {}

    // MARK: - Public API

    /// Searches the accessibility tree for a UI element whose title, description,
    /// or value contains `elementTitle` and moves the cursor to its center.
    ///
    /// Search strategy:
    /// 1. If `bundleID` is given, search that app's tree first.
    /// 2. Always also search the system-wide AX tree so elements in
    ///    non-app contexts (menu bar, system UI) are reachable.
    /// 3. All candidates are collected and logged; the best match is chosen.
    func pointAtElement(withTitle elementTitle: String, inApp bundleID: String?) async {
        print("[Luma] CursorGuide.pointAt() called — target='\(elementTitle)' bundleID='\(bundleID ?? "any")'")

        guard AXIsProcessTrusted() else {
            print("[Luma] CursorGuide: aborting — Accessibility permission not granted. Enable in System Settings → Privacy → Accessibility.")
            return
        }

        // CGDisplayMoveCursorToPoint requires Post-Event access. Call once before
        // the first move attempt; subsequent calls are no-ops.
        let postEventAccessGranted = CGRequestPostEventAccess()
        print("[Luma] CursorGuide: CGRequestPostEventAccess = \(postEventAccessGranted)")

        // --- Element search ---

        var allCandidates: [AXCandidateElement] = []

        // 1. Search the target app's tree if a bundleID was provided
        if let bundleID = bundleID,
           let runningApp = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            print("[Luma] CursorGuide: searching app '\(runningApp.localizedName ?? bundleID)' (PID \(runningApp.processIdentifier))")
            let appRoot = AXUIElementCreateApplication(runningApp.processIdentifier)
            let appCandidates = collectAllMatchingElements(
                searchTitle: elementTitle,
                startingAt: appRoot,
                depthLimit: 10
            )
            allCandidates.append(contentsOf: appCandidates)
        }

        // 2. Always also search system-wide (catches menu bar items, system panels, etc.)
        let systemRoot = AXUIElementCreateSystemWide()
        let systemCandidates = collectAllMatchingElements(
            searchTitle: elementTitle,
            startingAt: systemRoot,
            depthLimit: 8  // Shallower limit for system-wide to avoid hanging
        )
        allCandidates.append(contentsOf: systemCandidates)

        // 3. If no bundleID given, also search the frontmost app explicitly
        if bundleID == nil, let frontApp = NSWorkspace.shared.frontmostApplication {
            let frontRoot = AXUIElementCreateApplication(frontApp.processIdentifier)
            let frontCandidates = collectAllMatchingElements(
                searchTitle: elementTitle,
                startingAt: frontRoot,
                depthLimit: 10
            )
            // Deduplicate — frontmost app elements may already appear in system-wide results
            for candidate in frontCandidates {
                let isDuplicate = allCandidates.contains { existing in
                    existing.axFrame == candidate.axFrame && existing.title == candidate.title
                }
                if !isDuplicate {
                    allCandidates.append(candidate)
                }
            }
        }

        // Log every candidate so we can see exactly what was found in the console
        print("[Luma] CursorGuide: found \(allCandidates.count) candidate(s) for '\(elementTitle)'")
        for (index, candidate) in allCandidates.enumerated() {
            print("[Luma] Found element[\(index)]: title='\(candidate.title)' role='\(candidate.role)' frame(AX)=\(candidate.axFrame)")
        }

        guard !allCandidates.isEmpty else {
            print("[Luma] CursorGuide: no element matching '\(elementTitle)' found anywhere")
            return
        }

        // Pick the best match: exact title match preferred, otherwise highest score, then largest area
        let bestCandidate = chooseBestCandidate(from: allCandidates, searchTitle: elementTitle)
        print("[Luma] CursorGuide: selected element '\(bestCandidate.title)' role='\(bestCandidate.role)'")

        // --- Coordinate conversion ---
        //
        // AX API frames are in AppKit screen coordinates (Y=0 at bottom-left of primary screen,
        // Y increases upward). CGDisplayMoveCursorToPoint needs Quartz/CG coordinates
        // (Y=0 at top-left, Y increases downward). We must flip Y using the containing screen's height.

        let axFrame = bestCandidate.axFrame

        // Find which NSScreen contains this element (AppKit frame, bottom-left origin)
        let containingScreen = NSScreen.screens.first { screen in
            screen.frame.contains(CGPoint(x: axFrame.midX, y: axFrame.midY))
        } ?? NSScreen.main

        let screenHeightForConversion = containingScreen?.frame.height ?? NSScreen.main?.frame.height ?? 0

        // Convert AppKit frame → Quartz/CG frame (flip Y axis)
        let screenFrameInCGCoordinates = CGRect(
            x: axFrame.origin.x,
            y: screenHeightForConversion - axFrame.origin.y - axFrame.height,
            width: axFrame.width,
            height: axFrame.height
        )

        // The point we'll move the cursor to (Quartz/CG coordinates)
        let cursorTargetInCGCoordinates = CGPoint(
            x: screenFrameInCGCoordinates.midX,
            y: screenFrameInCGCoordinates.midY
        )

        // Verification logs — these let us confirm the math is correct in the console
        print("[Luma] Element frame (AX/AppKit): \(axFrame)")
        print("[Luma] Element frame (CG/Quartz): \(screenFrameInCGCoordinates)")
        print("[Luma] Moving cursor to: \(cursorTargetInCGCoordinates)")

        // --- Cursor movement ---

        // Primary: CGDisplayMoveCursorToPoint — direct and reliable on most macOS versions
        let displayID = findCGDisplayContainingPoint(cursorTargetInCGCoordinates)
        let moveResult = CGDisplayMoveCursorToPoint(displayID, cursorTargetInCGCoordinates)
        print("[Luma] CursorGuide: CGDisplayMoveCursorToPoint → \(moveResult == .success ? "success" : "error(\(moveResult.rawValue))")")

        // Fallback: CGEvent mouseMoved — works via the HID layer even when
        // CGDisplayMoveCursorToPoint is blocked on macOS 14+ due to entitlements
        if let mouseMoveEvent = CGEvent(
            mouseEventSource: nil,
            mouseType: .mouseMoved,
            mouseCursorPosition: cursorTargetInCGCoordinates,
            mouseButton: .left
        ) {
            mouseMoveEvent.post(tap: .cghidEventTap)
            print("[Luma] CursorGuide: CGEvent mouseMoved posted at \(cursorTargetInCGCoordinates)")
        } else {
            print("[Luma] CursorGuide: CGEvent creation failed")
        }

        // --- Notify the overlay ---
        //
        // The overlay uses AppKit coordinates (bottom-left origin). The AX frame is already
        // in AppKit coordinates, so we use the center directly without re-converting.
        let overlayTargetInAppKitCoordinates = CGPoint(x: axFrame.midX, y: axFrame.midY)

        NotificationCenter.default.post(
            name: CursorGuide.pointAtNotificationName,
            object: nil,
            userInfo: [
                CursorGuide.targetPointUserInfoKey: NSValue(point: overlayTargetInAppKitCoordinates)
            ]
        )
        print("[Luma] CursorGuide: overlay notified at AppKit point \(overlayTargetInAppKitCoordinates)")
    }

    /// Posts the clear-pointer notification so the overlay removes any active cursor guidance.
    func clearGuidance() {
        NotificationCenter.default.post(
            name: CursorGuide.clearPointerNotificationName,
            object: nil
        )
    }

    // MARK: - Element Search

    /// A candidate element found during AX tree search.
    private struct AXCandidateElement {
        let element: AXUIElement
        let title: String       // The matched attribute value (title, description, or value)
        let role: String        // AXRole for logging
        let axFrame: CGRect     // Frame in AppKit/AX coordinates (bottom-left origin)
        let matchScore: Int     // Higher = better match (exact > prefix > substring)
    }

    /// Recursively walks an AX element tree and collects all elements whose
    /// AXTitle, AXDescription, or AXValue contains `searchTitle` (case-insensitive).
    /// Returns all matches found within `depthLimit` levels.
    private func collectAllMatchingElements(
        searchTitle: String,
        startingAt rootElement: AXUIElement,
        depthLimit: Int
    ) -> [AXCandidateElement] {
        var foundCandidates: [AXCandidateElement] = []
        collectMatchingElementsRecursive(
            searchTitle: searchTitle,
            element: rootElement,
            depthRemaining: depthLimit,
            results: &foundCandidates
        )
        return foundCandidates
    }

    private func collectMatchingElementsRecursive(
        searchTitle: String,
        element: AXUIElement,
        depthRemaining: Int,
        results: inout [AXCandidateElement]
    ) {
        guard depthRemaining > 0 else { return }

        // Check AXTitle, AXDescription, and AXValue — any of them may contain the target string
        let titleValue       = extractAttributeString(from: element, attribute: kAXTitleAttribute)
        let descriptionValue = extractAttributeString(from: element, attribute: kAXDescriptionAttribute)
        let valueString      = extractAttributeString(from: element, attribute: kAXValueAttribute)
        let roleValue        = extractAttributeString(from: element, attribute: kAXRoleAttribute) ?? "unknown"

        // The best matching string among the three attributes
        let matchedString = [titleValue, descriptionValue, valueString]
            .compactMap { $0 }
            .first { $0.localizedCaseInsensitiveContains(searchTitle) }

        if let matchedText = matchedString {
            // Read the element's AX frame (in AppKit/bottom-left-origin coordinates)
            var axFrameRect = CGRect.zero
            var frameValueRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, "AXFrame" as CFString, &frameValueRef) == .success,
               let frameRef = frameValueRef {
                AXValueGetValue(frameRef as! AXValue, .cgRect, &axFrameRect)
            }

            // Only include elements with a valid, non-zero frame (invisible/zero-size elements can't be pointed at)
            if axFrameRect != .zero && !axFrameRect.isNull && axFrameRect.width > 0 && axFrameRect.height > 0 {
                let score = matchScore(matchedText: matchedText, searchTitle: searchTitle)
                let candidate = AXCandidateElement(
                    element: element,
                    title: matchedText,
                    role: roleValue,
                    axFrame: axFrameRect,
                    matchScore: score
                )
                results.append(candidate)
            }
        }

        // Recurse into children
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let childrenCF = childrenRef,
              CFGetTypeID(childrenCF) == CFArrayGetTypeID()
        else { return }

        let childrenArray = childrenCF as! [AXUIElement]
        for child in childrenArray {
            collectMatchingElementsRecursive(
                searchTitle: searchTitle,
                element: child,
                depthRemaining: depthRemaining - 1,
                results: &results
            )
        }
    }

    /// Scores how well `matchedText` matches `searchTitle`.
    /// Exact match scores highest, then starts-with, then contains.
    private func matchScore(matchedText: String, searchTitle: String) -> Int {
        let lowerMatched = matchedText.lowercased()
        let lowerSearch  = searchTitle.lowercased()
        if lowerMatched == lowerSearch            { return 3 }  // Exact
        if lowerMatched.hasPrefix(lowerSearch)   { return 2 }  // Starts with
        return 1                                                // Substring
    }

    /// Picks the best candidate from a list: highest match score wins,
    /// ties broken by largest frame area (most prominent visible element).
    private func chooseBestCandidate(
        from candidates: [AXCandidateElement],
        searchTitle: String
    ) -> AXCandidateElement {
        return candidates.max { leftCandidate, rightCandidate in
            if leftCandidate.matchScore != rightCandidate.matchScore {
                return leftCandidate.matchScore < rightCandidate.matchScore
            }
            // Same score — prefer the larger (more prominent) element
            let leftArea  = leftCandidate.axFrame.width  * leftCandidate.axFrame.height
            let rightArea = rightCandidate.axFrame.width * rightCandidate.axFrame.height
            return leftArea < rightArea
        }!
    }

    // MARK: - Display Helpers

    /// Returns the CGDirectDisplayID of the display that contains `cgPoint`
    /// (in Quartz/CG coordinates). Falls back to the main display.
    private func findCGDisplayContainingPoint(_ cgPoint: CGPoint) -> CGDirectDisplayID {
        var displayCount: UInt32 = 0
        CGGetDisplaysWithPoint(cgPoint, 0, nil, &displayCount)
        guard displayCount > 0 else { return CGMainDisplayID() }

        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        CGGetDisplaysWithPoint(cgPoint, displayCount, &displayIDs, nil)
        return displayIDs.first ?? CGMainDisplayID()
    }

    // MARK: - AX Attribute Helpers

    /// Reads a string attribute from an AXUIElement. Returns nil if absent or not a string.
    private func extractAttributeString(from element: AXUIElement, attribute: String) -> String? {
        var rawValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &rawValue)
        guard result == .success, let value = rawValue else { return nil }
        guard CFGetTypeID(value) == CFStringGetTypeID() else { return nil }
        return (value as! CFString) as String
    }
}
