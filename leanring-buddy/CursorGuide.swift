//
//  CursorGuide.swift
//  leanring-buddy
//
//  Finds UI elements by name in the AX tree and moves the OS cursor to them.
//  Used by both ad-hoc responses (auto-cursor from AI text) and the WalkthroughEngine.
//
//  Coordinate system notes:
//  ─────────────────────────────────────────────────────────
//  The macOS Accessibility API returns AXFrame values in AppKit/Cocoa
//  screen coordinates: origin at the BOTTOM-LEFT of the primary display,
//  Y increases upward.
//
//  CGDisplayMoveCursorToPoint and CGEvent use Quartz/CoreGraphics coordinates:
//  origin at the TOP-LEFT of the primary display, Y increases downward.
//
//  The correct Y-axis flip uses the maximum Y extent across all connected
//  screens: cgY = maxScreenY - axFrame.midY
//  Using only the containing screen's height gives wrong results when the
//  element is on a secondary screen positioned above or below the primary.
//

import AppKit
import ApplicationServices
import Foundation

// MARK: - CursorGuide

@MainActor
final class CursorGuide {
    static let shared = CursorGuide()

    // Notification posted so the overlay animates the Luma cursor to the target.
    static let pointAtNotificationName = NSNotification.Name("lumaWalkthroughPointAt")

    // Notification to clear any active pointer guidance from the overlay.
    static let clearPointerNotificationName = NSNotification.Name("lumaWalkthroughClearPointer")

    // userInfo key for the target CGPoint (wrapped in NSValue, in AppKit coordinates).
    static let targetPointUserInfoKey = "targetPoint"

    private init() {}

    // MARK: - Public API

    /// Finds a UI element by name and moves the OS cursor to its center.
    /// Tries the target app (if bundleID given) then the menu bar, then the frontmost app.
    func pointAtElement(withTitle elementTitle: String, inApp bundleID: String?) async {
        print("[Luma] CursorGuide.pointAt() — target='\(elementTitle)' bundleID='\(bundleID ?? "any")'")

        guard AXIsProcessTrusted() else {
            print("[Luma] CursorGuide: aborting — Accessibility permission not granted.")
            return
        }

        let postEventAccessGranted = CGRequestPostEventAccess()
        print("[Luma] CursorGuide: CGRequestPostEventAccess = \(postEventAccessGranted)")

        // --- Element search ---

        // 1. Try the specific app if a bundleID was given
        var bestElement: (element: AXUIElement, axFrame: CGRect)?

        if let bundleID = bundleID {
            bestElement = findElement(named: elementTitle, inApp: bundleID)
        }

        // 2. Try the menu bar if nothing found yet
        if bestElement == nil {
            bestElement = findMenuBarElement(named: elementTitle)
        }

        // 3. Fall back to the frontmost app
        if bestElement == nil {
            bestElement = findElement(named: elementTitle, inApp: nil)
        }

        guard let foundElement = bestElement else {
            print("[Luma] CursorGuide: no element matching '\(elementTitle)' found anywhere")
            return
        }

        moveCursorAndNotifyOverlay(to: foundElement.axFrame)
    }

    /// Posts the clear-pointer notification so the overlay removes any active cursor guidance.
    func clearGuidance() {
        NotificationCenter.default.post(
            name: CursorGuide.clearPointerNotificationName,
            object: nil
        )
    }

    // MARK: - AI-Assisted Pointing

    /// The parsed result of an AI pointing response.
    private struct AIPointingResult {
        /// Pixel coordinate in the screenshot's coordinate space (top-left origin).
        let pixelCoordinate: CGPoint
        /// Which screen capture (0-based index into the captured array) the coordinate is in.
        /// The AI tags secondary-screen elements with :screen2, :screen3, etc. (1-based).
        /// We store as 0-based here to index directly into screenCaptures.
        let screenCaptureIndex: Int
    }

    /// Captures the screen, asks the AI to visually locate `elementTitle`, converts the returned
    /// pixel coordinate to global AppKit coordinates, and moves the cursor there.
    ///
    /// Multi-screen: sends all screens to the AI, asks it to tag secondary-screen elements with
    /// :screenN, and uses the correct screen's metadata for coordinate conversion.
    ///
    /// Falls back to AX tree search if the AI call fails, the Task is cancelled, or no coordinate
    /// is returned. Using both AI vision and AX means we find elements whose AX labels differ from
    /// their visible labels (e.g. toolbar buttons with icon-only AX descriptions).
    func pointAtElementViaAIScreenshot(named elementTitle: String, inApp bundleID: String?) async {
        // Check for Task cancellation before starting expensive work
        guard !Task.isCancelled else { return }

        print("[Luma] CursorGuide.pointAtElementViaAIScreenshot() — target='\(elementTitle)'")

        guard AXIsProcessTrusted() else {
            print("[Luma] CursorGuide: aborting — Accessibility permission not granted.")
            return
        }

        do {
            let screenCaptures = try await CompanionScreenCaptureUtility.captureAllScreensAsJPEG()

            // Check again after the async capture — the Task may have been cancelled while we waited
            guard !Task.isCancelled else { return }

            // Build a screen-aware description for the AI.
            // Each image's label already says "screen 1 of 2 — cursor is here" etc.
            // The prompt instructs the AI to append :screenN for secondary screens.
            let screenCountDescription = screenCaptures.count > 1
                ? "You are shown \(screenCaptures.count) screens. Each image label identifies the screen number."
                : "You are shown 1 screen."

            let elementLocationSystemPrompt = """
            You are a macOS screen analyzer that locates UI elements.
            \(screenCountDescription)

            When asked to find a UI element, respond with ONLY a [POINT:x,y:label] tag — nothing else.
            - x and y are integer pixel coordinates in the screenshot (top-left origin, 0,0 = top-left corner)
            - label is a 1-3 word description of the element
            - If the element is on the first/cursor screen: [POINT:x,y:label]
            - If the element is on screen 2: [POINT:x,y:label:screen2]
            - If the element is on screen 3: [POINT:x,y:label:screen3]
            - If the element is not visible on any screen: [POINT:none]
            """

            let imageTuples = screenCaptures.map { capture in
                (data: capture.imageData, label: capture.label)
            }

            let (aiResponse, _) = try await APIClient.shared.analyzeImage(
                images: imageTuples,
                systemPrompt: elementLocationSystemPrompt,
                conversationHistory: [],
                userPrompt: "Find the UI element named \"\(elementTitle)\" and return its pixel coordinates."
            )

            guard !Task.isCancelled else { return }

            print("[Luma] CursorGuide AI pointing response: \(aiResponse)")

            if let pointingResult = parseAIPointingResponse(aiResponse, screenCaptureCount: screenCaptures.count) {
                let targetScreenCapture = screenCaptures[pointingResult.screenCaptureIndex]
                let appKitPoint = convertScreenshotPixelToGlobalAppKitPoint(
                    pixelPoint: pointingResult.pixelCoordinate,
                    screenCapture: targetScreenCapture
                )
                moveCursorToAppKitPoint(appKitPoint)
                return
            }
        } catch {
            if Task.isCancelled { return }
            print("[Luma] CursorGuide AI screenshot pointing failed: \(error.localizedDescription)")
        }

        // Fallback: AX tree search when AI pointing fails or the Task was cancelled before move
        guard !Task.isCancelled else { return }
        print("[Luma] CursorGuide: falling back to AX tree search for '\(elementTitle)'")
        await pointAtElement(withTitle: elementTitle, inApp: bundleID)
    }

    /// Parses a [POINT:x,y:label] or [POINT:x,y:label:screenN] tag from the AI's response.
    /// Returns nil if the response is [POINT:none] or no valid coordinate was found.
    ///
    /// - Parameter screenCaptureCount: Total number of screen captures. Used to clamp the screen
    ///   index so an out-of-range :screenN doesn't cause an out-of-bounds array access.
    private func parseAIPointingResponse(
        _ aiResponseText: String,
        screenCaptureCount: Int
    ) -> AIPointingResult? {
        // Match [POINT:x,y] with optional :label and optional :screenN suffixes
        // Pattern groups: (1)=x, (2)=y, (3)=label (optional), (4)=screen number (optional)
        let pointingPattern = #"\[POINT:(\d+)\s*,\s*(\d+)(?::[^\]:]*)?(?::screen(\d+))?\]"#

        guard let regex = try? NSRegularExpression(pattern: pointingPattern),
              let match = regex.firstMatch(
                in: aiResponseText,
                range: NSRange(aiResponseText.startIndex..., in: aiResponseText)
              ),
              match.numberOfRanges >= 3,
              let xRange = Range(match.range(at: 1), in: aiResponseText),
              let yRange = Range(match.range(at: 2), in: aiResponseText),
              let parsedX = Double(aiResponseText[xRange]),
              let parsedY = Double(aiResponseText[yRange])
        else { return nil }

        // Parse the optional :screenN suffix (1-based from the AI → convert to 0-based index)
        var screenCaptureIndex = 0 // default: cursor screen (always first in sorted array)
        if match.numberOfRanges >= 4,
           let screenRange = Range(match.range(at: 3), in: aiResponseText),
           let oneBasedScreenNumber = Int(aiResponseText[screenRange]) {
            // Clamp to valid range: screen numbers outside what we captured fall back to screen 1
            let clampedIndex = max(0, min(oneBasedScreenNumber - 1, screenCaptureCount - 1))
            screenCaptureIndex = clampedIndex
        }

        return AIPointingResult(
            pixelCoordinate: CGPoint(x: parsedX, y: parsedY),
            screenCaptureIndex: screenCaptureIndex
        )
    }

    /// Converts a pixel coordinate in a screenshot (top-left origin) to a global AppKit
    /// coordinate (bottom-left origin of the primary display) using the screen capture metadata.
    private func convertScreenshotPixelToGlobalAppKitPoint(
        pixelPoint: CGPoint,
        screenCapture: CompanionScreenCapture
    ) -> CGPoint {
        let screenshotWidth = CGFloat(screenCapture.screenshotWidthInPixels)
        let screenshotHeight = CGFloat(screenCapture.screenshotHeightInPixels)
        let displayWidth = CGFloat(screenCapture.displayWidthInPoints)
        let displayHeight = CGFloat(screenCapture.displayHeightInPoints)
        let displayFrame = screenCapture.displayFrame

        // Clamp to the screenshot's coordinate space to handle any out-of-bounds AI responses
        let clampedX = max(0, min(pixelPoint.x, screenshotWidth))
        let clampedY = max(0, min(pixelPoint.y, screenshotHeight))

        // Scale from screenshot pixels to display points (screenshots are downscaled to 1280px max)
        let displayLocalX = clampedX * (displayWidth / screenshotWidth)
        let displayLocalY = clampedY * (displayHeight / screenshotHeight)

        // Flip Y: screenshot has top-left origin, AppKit has bottom-left origin
        let appKitLocalY = displayHeight - displayLocalY

        // Add display frame origin to get global AppKit coordinates across all monitors
        return CGPoint(
            x: displayLocalX + displayFrame.origin.x,
            y: appKitLocalY + displayFrame.origin.y
        )
    }

    /// Converts a global AppKit point (bottom-left origin) to a CG/Quartz point (top-left origin),
    /// moves the OS cursor there, and notifies the overlay to animate the Luma cursor.
    private func moveCursorToAppKitPoint(_ appKitPoint: CGPoint) {
        let maximumScreenY = NSScreen.screens.reduce(0.0) { max($0, $1.frame.maxY) }
        let cgPoint = CGPoint(x: appKitPoint.x, y: maximumScreenY - appKitPoint.y)

        print("[Luma] CursorGuide AI move — AppKit: \(appKitPoint) → CG: \(cgPoint)")

        let displayID = findCGDisplayContaining(cgPoint: cgPoint)
        CGDisplayMoveCursorToPoint(displayID, cgPoint)

        if let mouseMovedEvent = CGEvent(
            mouseEventSource: nil,
            mouseType: .mouseMoved,
            mouseCursorPosition: cgPoint,
            mouseButton: .left
        ) {
            mouseMovedEvent.post(tap: .cghidEventTap)
        }

        // Notify the overlay in AppKit coordinates so the Luma cursor animates there
        NotificationCenter.default.post(
            name: CursorGuide.pointAtNotificationName,
            object: nil,
            userInfo: [CursorGuide.targetPointUserInfoKey: NSValue(point: appKitPoint)]
        )
    }

    // MARK: - Element Search

    /// A UI element collected during AX tree traversal.
    private struct CollectedElement {
        let element: AXUIElement
        let title: String       // Best matching text attribute (title, description, or value)
        let role: String        // AXRole string (e.g. "AXButton")
        let axFrame: CGRect     // Frame in AppKit/AX coordinates (bottom-left origin)
    }

    /// Searches the given app's AX tree for the best match to `query`.
    /// Returns the matched element and its AX frame, or nil if nothing scored above zero.
    ///
    /// Scoring:
    ///   Exact title match:           100 pts
    ///   Title contains query:         50 pts
    ///   Query contains title (>3ch):  30 pts
    ///   AXButton role bonus:          10 pts
    ///   AXMenuItem role bonus:        10 pts
    ///   AXMenuBarItem role bonus:     15 pts
    func findElement(named query: String, inApp bundleID: String?) -> (element: AXUIElement, axFrame: CGRect)? {
        let rootElement: AXUIElement

        if let bundleID = bundleID,
           let runningApp = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            rootElement = AXUIElementCreateApplication(runningApp.processIdentifier)
        } else if let frontmostApp = NSWorkspace.shared.frontmostApplication {
            rootElement = AXUIElementCreateApplication(frontmostApp.processIdentifier)
        } else {
            return nil
        }

        var collectedElements: [CollectedElement] = []
        collectElements(from: rootElement, into: &collectedElements, depth: 0)

        let scoredElements = collectedElements
            .map { (collected: $0, score: scoreElement($0, query: query)) }
            .filter { $0.score > 0 }
            .sorted { $0.score > $1.score }

        print("[Luma] Element search '\(query)': \(scoredElements.count) candidate(s)")
        for candidate in scoredElements.prefix(3) {
            print("[Luma]   '\(candidate.collected.title)' role=\(candidate.collected.role) score=\(candidate.score)")
        }

        guard let bestMatch = scoredElements.first else { return nil }
        return (bestMatch.collected.element, bestMatch.collected.axFrame)
    }

    /// Searches the menu bar hierarchy (including system status bar items in ControlCenter
    /// and SystemUIServer) for the best match to `query`. Menu bar items live in a
    /// separate AX subtree and need special handling.
    func findMenuBarElement(named query: String) -> (element: AXUIElement, axFrame: CGRect)? {
        var collectedElements: [CollectedElement] = []

        // 1. App menu bar — the frontmost app's AXMenuBar subtree
        if let frontmostApp = NSWorkspace.shared.frontmostApplication {
            let appElement = AXUIElementCreateApplication(frontmostApp.processIdentifier)
            var menuBarRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(appElement, kAXMenuBarAttribute as CFString, &menuBarRef) == .success,
               let menuBarElement = menuBarRef {
                collectElements(from: menuBarElement as! AXUIElement, into: &collectedElements, depth: 0)
            }
        }

        // 2. System status bar — ControlCenter and SystemUIServer hold battery, wifi,
        //    clock, and other status items that live outside of app menu bars
        let systemStatusBarBundleIDs = [
            "com.apple.controlcenter",
            "com.apple.systemuiserver"
        ]

        for statusBarBundleID in systemStatusBarBundleIDs {
            if let statusBarApp = NSRunningApplication.runningApplications(withBundleIdentifier: statusBarBundleID).first {
                let statusBarElement = AXUIElementCreateApplication(statusBarApp.processIdentifier)
                collectElements(from: statusBarElement, into: &collectedElements, depth: 0)
            }
        }

        let scoredElements = collectedElements
            .map { (collected: $0, score: scoreElement($0, query: query)) }
            .filter { $0.score > 0 }
            .sorted { $0.score > $1.score }

        print("[Luma] Menu bar search '\(query)': \(scoredElements.count) candidate(s)")

        guard let bestMatch = scoredElements.first else { return nil }
        return (bestMatch.collected.element, bestMatch.collected.axFrame)
    }

    // MARK: - AX Tree Traversal

    /// Recursively walks an AX element tree and collects all elements that have
    /// a non-empty title/description/value AND a valid non-zero frame.
    /// Stops at `depth` == 10 to prevent infinite recursion on degenerate trees.
    private func collectElements(
        from element: AXUIElement,
        into array: inout [CollectedElement],
        depth: Int
    ) {
        guard depth < 10 else { return }

        // Read the three text attributes that might carry a visible label
        let titleValue       = readStringAttribute(kAXTitleAttribute, from: element)
        let descriptionValue = readStringAttribute(kAXDescriptionAttribute, from: element)
        let valueString      = readStringAttribute(kAXValueAttribute, from: element)
        let roleValue        = readStringAttribute(kAXRoleAttribute, from: element) ?? "AXUnknown"

        // Pick the first non-empty text attribute — that's what we'll match against
        let bestTitle = [titleValue, descriptionValue, valueString]
            .compactMap { $0 }
            .first(where: { !$0.isEmpty })

        if let elementTitle = bestTitle {
            // Only include elements with a real on-screen frame (invisible/zero-size elements
            // can't be pointed at and tend to produce false matches)
            var axFrameRect = CGRect.zero
            var frameValueRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, "AXFrame" as CFString, &frameValueRef) == .success,
               let frameRef = frameValueRef {
                AXValueGetValue(frameRef as! AXValue, .cgRect, &axFrameRect)
            }

            if axFrameRect.width > 0 && axFrameRect.height > 0 {
                array.append(CollectedElement(
                    element: element,
                    title: elementTitle,
                    role: roleValue,
                    axFrame: axFrameRect
                ))
            }
        }

        // Recurse into children
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let childrenValue = childrenRef,
              CFGetTypeID(childrenValue) == CFArrayGetTypeID()
        else { return }

        for child in (childrenValue as! [AXUIElement]) {
            collectElements(from: child, into: &array, depth: depth + 1)
        }
    }

    // MARK: - Scoring

    /// Returns a relevance score for how well `collected.title` matches `query`.
    /// Returns 0.0 if there is no match at all (caller should filter these out).
    private func scoreElement(_ collected: CollectedElement, query: String) -> Double {
        let titleLower = collected.title.lowercased()
        let queryLower = query.lowercased()

        var score = 0.0

        if titleLower == queryLower {
            score += 100.0  // Exact match — best possible
        } else if titleLower.contains(queryLower) {
            score += 50.0   // Title contains the query string
        } else if queryLower.contains(titleLower) && titleLower.count > 3 {
            score += 30.0   // Query contains the title (only if title is meaningful length)
        }

        guard score > 0 else { return 0.0 }

        // Role bonuses — prefer interactive elements when scores are otherwise tied
        switch collected.role {
        case "AXMenuBarItem": score += 15.0   // Top-level menu bar items (File, Edit…)
        case "AXButton":      score += 10.0   // Buttons are usually the primary action targets
        case "AXMenuItem":    score += 10.0   // Menu items are often exactly what we want
        default: break
        }

        return score
    }

    // MARK: - Cursor Movement

    /// Converts the AX frame center to a CG/Quartz coordinate point, moves the OS
    /// cursor there, and posts an overlay notification so the Luma cursor animates to match.
    private func moveCursorAndNotifyOverlay(to axFrame: CGRect) {
        let cgTargetPoint = axCenterToCGPoint(axFrame)

        print("[Luma] AX frame (AppKit):   \(axFrame)")
        print("[Luma] Cursor target (CG):  \(cgTargetPoint)")

        // Primary: direct cursor warp — fast and reliable on most macOS versions
        let displayID = findCGDisplayContaining(cgPoint: cgTargetPoint)
        let moveResult = CGDisplayMoveCursorToPoint(displayID, cgTargetPoint)
        print("[Luma] CGDisplayMoveCursorToPoint → \(moveResult == .success ? "success" : "error(\(moveResult.rawValue))")")

        // Fallback: CGEvent HID tap — works even when the direct warp is blocked by
        // macOS 14+ entitlement restrictions
        if let mouseMoveEvent = CGEvent(
            mouseEventSource: nil,
            mouseType: .mouseMoved,
            mouseCursorPosition: cgTargetPoint,
            mouseButton: .left
        ) {
            mouseMoveEvent.post(tap: .cghidEventTap)
            print("[Luma] CGEvent mouseMoved posted at \(cgTargetPoint)")
        }

        // Notify the overlay in AppKit coordinates (no conversion needed — the
        // AX frame is already in AppKit space, and the overlay renders in AppKit space)
        let overlayTarget = CGPoint(x: axFrame.midX, y: axFrame.midY)
        NotificationCenter.default.post(
            name: CursorGuide.pointAtNotificationName,
            object: nil,
            userInfo: [CursorGuide.targetPointUserInfoKey: NSValue(point: overlayTarget)]
        )
        print("[Luma] Overlay notified at AppKit point \(overlayTarget)")
    }

    // MARK: - Coordinate Conversion

    /// Converts the center of an AX frame (AppKit/bottom-left origin) to a
    /// Quartz/CG coordinate point (top-left origin).
    ///
    /// Uses the maximum Y extent across ALL connected screens as the flip height.
    /// This correctly handles elements on secondary screens positioned above, below,
    /// or beside the primary display in a multi-monitor setup.
    private func axCenterToCGPoint(_ axFrame: CGRect) -> CGPoint {
        // The maximum Y of any screen in AppKit coordinates equals the total vertical
        // height of the desktop space from the bottom-left of the primary display upward.
        let maximumScreenY = NSScreen.screens.reduce(0.0) { max($0, $1.frame.maxY) }

        let cgX = axFrame.midX
        let cgY = maximumScreenY - axFrame.midY

        return CGPoint(x: cgX, y: cgY)
    }

    // MARK: - Display Helpers

    /// Returns the CGDirectDisplayID of the display containing `cgPoint`
    /// (in Quartz/CG coordinates). Falls back to the main display.
    private func findCGDisplayContaining(cgPoint: CGPoint) -> CGDirectDisplayID {
        var displayCount: UInt32 = 0
        CGGetDisplaysWithPoint(cgPoint, 0, nil, &displayCount)
        guard displayCount > 0 else { return CGMainDisplayID() }

        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        CGGetDisplaysWithPoint(cgPoint, displayCount, &displayIDs, nil)
        return displayIDs.first ?? CGMainDisplayID()
    }

    // MARK: - AX Attribute Helpers

    /// Reads a string attribute from an AXUIElement. Returns nil if absent or not a string.
    private func readStringAttribute(_ attribute: String, from element: AXUIElement) -> String? {
        var rawValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &rawValue)
        guard result == .success, let value = rawValue else { return nil }
        guard CFGetTypeID(value) == CFStringGetTypeID() else { return nil }
        return (value as! CFString) as String
    }
}
