//
//  CursorGuide.swift
//  leanring-buddy
//
//  Visual guidance system that points the Luma cursor at a specific UI element
//  during a walkthrough step. Uses the macOS Accessibility API to find the
//  element's on-screen position, then posts a NotificationCenter notification
//  so OverlayWindowManager can animate the cursor to that point.
//

import AppKit
import ApplicationServices
import Foundation

// MARK: - CursorGuide

@MainActor
final class CursorGuide {
    static let shared = CursorGuide()

    // Notification name used to instruct the overlay to animate the cursor to a point.
    // OverlayWindowManager observes this notification and triggers the bezier arc animation.
    static let pointAtNotificationName = NSNotification.Name("lumaWalkthroughPointAt")

    // Notification name to clear any active pointer guidance from the overlay.
    static let clearPointerNotificationName = NSNotification.Name("lumaWalkthroughClearPointer")

    // The userInfo key for the target CGPoint wrapped in NSValue.
    static let targetPointUserInfoKey = "targetPoint"

    private init() {}

    // MARK: - Public API

    /// Searches for a UI element with the given title and points the cursor at it.
    /// If `bundleID` is provided, searches only in that app; otherwise uses the frontmost app.
    /// Does nothing (logs a warning) if the element cannot be found.
    func pointAtElement(withTitle elementTitle: String, inApp bundleID: String?) async {
        // Resolve which running application to search in
        let targetRunningApp: NSRunningApplication?

        if let bundleID = bundleID {
            // The step specifies a particular app — use the first running instance of it
            targetRunningApp = NSRunningApplication
                .runningApplications(withBundleIdentifier: bundleID)
                .first
        } else {
            // No app specified — search in whatever app is currently frontmost
            targetRunningApp = NSWorkspace.shared.frontmostApplication
        }

        guard let runningApp = targetRunningApp else {
            print("CursorGuide: target app not found for bundle ID '\(bundleID ?? "frontmost")'")
            return
        }

        let appPID = runningApp.processIdentifier

        // Create the root AXUIElement for the target app.
        // AXUIElementCreateApplication gives us the top-level accessibility object
        // for an app, from which we can walk down to any child element.
        let appAXElement = AXUIElementCreateApplication(appPID)

        // Get the app's focused window — we search within the focused window rather
        // than the entire app tree because it's much faster and users typically
        // want guidance for elements visible in their current context.
        var focusedWindowValue: CFTypeRef?
        let windowResult = AXUIElementCopyAttributeValue(
            appAXElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindowValue
        )

        let searchRootElement: AXUIElement
        if windowResult == .success, let focusedWindowCF = focusedWindowValue {
            // We have a focused window — search within it
            searchRootElement = focusedWindowCF as! AXUIElement
        } else {
            // No focused window found — fall back to the app root element.
            // This handles apps like Finder that sometimes don't report a focused window.
            searchRootElement = appAXElement
        }

        // Recursively search the element tree for the target element
        guard let foundElement = findAXElement(
            withTitleContaining: elementTitle,
            startingAt: searchRootElement,
            depthLimit: 8  // Limit recursion depth to avoid hanging on deeply nested UIs
        ) else {
            print("CursorGuide: element with title '\(elementTitle)' not found in \(runningApp.localizedName ?? "app")")
            return
        }

        // Get the element's on-screen frame from the Accessibility API.
        // AXFrame returns a CGRect in screen coordinates with top-left origin (Quartz/CG convention).
        var frameValue: CFTypeRef?
        let frameResult = AXUIElementCopyAttributeValue(
            foundElement,
            "AXFrame" as CFString,
            &frameValue
        )

        guard frameResult == .success, let frameCF = frameValue else {
            print("CursorGuide: could not read AXFrame for element '\(elementTitle)'")
            return
        }

        // Extract the CGRect from the CFTypeRef.
        // AXFrame is returned as an AXValueRef wrapping a CGRect — we must use
        // AXValueGetValue rather than a simple cast.
        var elementFrameInCGCoordinates = CGRect.zero
        let axFrameValue = frameCF as! AXValue
        AXValueGetValue(axFrameValue, .cgRect, &elementFrameInCGCoordinates)

        // CG/Quartz screen coordinates have their origin at the top-left of the main screen.
        // AppKit/NSWindow coordinates have their origin at the bottom-left.
        // We need to convert so the overlay (which uses AppKit coordinates) positions correctly.
        let targetPointInAppKitCoordinates = convertCGPointToAppKitCoordinates(
            cgPoint: CGPoint(
                x: elementFrameInCGCoordinates.midX,
                y: elementFrameInCGCoordinates.midY
            )
        )

        // Post the notification so OverlayWindowManager can animate the cursor to the target.
        // We use NotificationCenter rather than a direct method call to keep CursorGuide
        // decoupled from OverlayWindowManager — the overlay subscribes independently.
        NotificationCenter.default.post(
            name: CursorGuide.pointAtNotificationName,
            object: nil,
            userInfo: [
                CursorGuide.targetPointUserInfoKey: NSValue(point: targetPointInAppKitCoordinates)
            ]
        )
    }

    /// Posts the clear-pointer notification so the overlay removes any active cursor guidance.
    func clearGuidance() {
        NotificationCenter.default.post(
            name: CursorGuide.clearPointerNotificationName,
            object: nil
        )
    }

    // MARK: - AX Element Search

    /// Recursively searches an AX element tree for an element whose AXTitle or
    /// AXDescription contains the target string (case-insensitive substring match).
    /// Returns the first match found, or nil if no match exists within the depth limit.
    ///
    /// We use a depth limit rather than searching the entire tree because accessibility
    /// trees for complex apps (e.g. Xcode, browsers) can have hundreds of elements,
    /// and a deep search without a limit would be too slow to feel responsive.
    private func findAXElement(
        withTitleContaining targetTitle: String,
        startingAt rootElement: AXUIElement,
        depthLimit: Int
    ) -> AXUIElement? {
        guard depthLimit > 0 else { return nil }

        // Check the current element's AXTitle and AXDescription attributes
        let currentElementTitle = extractAttributeString(
            from: rootElement,
            attribute: kAXTitleAttribute
        )
        let currentElementDescription = extractAttributeString(
            from: rootElement,
            attribute: kAXDescriptionAttribute
        )

        let titleMatches = currentElementTitle?.localizedCaseInsensitiveContains(targetTitle) ?? false
        let descriptionMatches = currentElementDescription?.localizedCaseInsensitiveContains(targetTitle) ?? false

        if titleMatches || descriptionMatches {
            return rootElement
        }

        // This element doesn't match — recurse into its children
        var childrenValue: CFTypeRef?
        let childrenResult = AXUIElementCopyAttributeValue(
            rootElement,
            kAXChildrenAttribute as CFString,
            &childrenValue
        )

        guard childrenResult == .success,
              let childrenCF = childrenValue,
              CFGetTypeID(childrenCF) == CFArrayGetTypeID()
        else {
            return nil
        }

        let childrenArray = childrenCF as! [AXUIElement]

        for childElement in childrenArray {
            if let foundInChild = findAXElement(
                withTitleContaining: targetTitle,
                startingAt: childElement,
                depthLimit: depthLimit - 1
            ) {
                return foundInChild
            }
        }

        return nil
    }

    // MARK: - Coordinate Conversion

    /// Converts a CGPoint in Quartz screen coordinates (top-left origin on main screen)
    /// to an NSPoint in AppKit screen coordinates (bottom-left origin on main screen).
    ///
    /// This conversion is necessary because the overlay windows use AppKit coordinate space
    /// but the Accessibility API returns coordinates in Quartz (CG) space.
    private func convertCGPointToAppKitCoordinates(cgPoint: CGPoint) -> NSPoint {
        guard let mainScreenFrame = NSScreen.main?.frame else {
            // If we can't get the main screen frame, return the point unchanged
            // rather than crashing — the cursor may be misplaced but won't error.
            return cgPoint
        }

        // Quartz origin: top-left corner of the main screen
        // AppKit origin: bottom-left corner of the main screen
        // Conversion: flip the Y axis using the main screen height
        let appKitY = mainScreenFrame.maxY - cgPoint.y

        return NSPoint(x: cgPoint.x, y: appKitY)
    }

    // MARK: - AX Attribute Helpers

    /// Reads a string attribute from an AXUIElement.
    /// Returns nil if the attribute doesn't exist or is not a string type.
    private func extractAttributeString(from element: AXUIElement, attribute: String) -> String? {
        var rawValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &rawValue)
        guard result == .success, let value = rawValue else { return nil }

        if CFGetTypeID(value) == CFStringGetTypeID() {
            return (value as! CFString) as String
        }
        return nil
    }
}
