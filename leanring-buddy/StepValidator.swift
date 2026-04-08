//
//  StepValidator.swift
//  leanring-buddy
//
//  Validates whether an accessibility event matches what the current
//  walkthrough step expected. Returns a typed result so WalkthroughEngine
//  can decide whether to advance, give corrective feedback, or ignore.
//

import Foundation

// MARK: - StepValidator

/// Validates a single AccessibilityEvent against the current WalkthroughStep.
/// Called by WalkthroughEngine every time AccessibilityWatcher fires an event.
@MainActor
final class StepValidator {

    enum ValidationResult {
        /// The event matches what the step expected — advance to the next step.
        case correct

        /// The wrong thing happened in the right app. Provide corrective feedback.
        case incorrect(reason: String)

        /// The event has nothing to do with this step. Silently ignore it.
        case unrelated
    }

    // MARK: - Validation Entry Point

    /// Compares an accessibility event against the expected state for a walkthrough step.
    /// The logic works in layers: app → action type → element name, from broadest to most specific.
    func validate(event: AccessibilityEvent, step: WalkthroughStep) -> ValidationResult {

        // --- App bundle ID check ---
        // If the step specifies an app, the event must come from that app.
        // Events from other apps are always unrelated — the user may be switching
        // windows or doing something else entirely.
        if let expectedBundleID = step.appBundleID {
            guard event.appBundleID == expectedBundleID else {
                return .unrelated
            }
        }

        // --- Steps with no expected element or action ---
        // These are "do anything in this app" steps (e.g. "Open the app").
        // Any event from the correct app counts as completing the step.
        let stepHasNoExpectedElement = step.expectedElement == nil
        let stepHasNoExpectedAction = step.expectedAction == nil

        if stepHasNoExpectedElement && stepHasNoExpectedAction {
            // If no app was specified either, any meaningful event counts as correct.
            // We consider all events meaningful — unrelated noise is filtered upstream.
            return .correct
        }

        // --- Action type check ---
        // Map the step's expectedAction string to the AccessibilityEvent.EventType(s)
        // that would satisfy it.
        let actionMatches: Bool
        if let expectedAction = step.expectedAction {
            actionMatches = eventTypeMatches(
                eventType: event.type,
                expectedActionString: expectedAction
            )
        } else {
            // No expected action specified — any action type is acceptable
            actionMatches = true
        }

        // --- Element name check ---
        // Check whether the event's element title or role contains the expected
        // element string. We use case-insensitive substring matching because:
        // 1. AXTitle values vary slightly across macOS versions ("Save" vs "Save As…")
        // 2. We want "Save" to match "Save As" and vice versa for robustness
        let elementMatches: Bool
        if let expectedElement = step.expectedElement {
            let titleMatches = event.elementTitle?.localizedCaseInsensitiveContains(expectedElement) ?? false
            let roleMatches = event.elementRole?.localizedCaseInsensitiveContains(expectedElement) ?? false
            elementMatches = titleMatches || roleMatches
        } else {
            // No expected element specified — any element is acceptable
            elementMatches = true
        }

        // --- Final decision ---
        if actionMatches && elementMatches {
            return .correct
        }

        // The event came from the right app but didn't match expectations.
        // This is only "incorrect" (not "unrelated") when we have an app bundle ID
        // constraint — otherwise we can't know whether the event is relevant.
        if step.appBundleID != nil {
            let expectedDescription = step.expectedElement ?? step.expectedAction ?? "expected action"
            let actualDescription = event.elementTitle ?? event.elementRole ?? "unknown"
            return .incorrect(
                reason: "Expected \(expectedDescription), but got \(actualDescription)"
            )
        }

        return .unrelated
    }

    // MARK: - Action Mapping

    /// Maps an expectedAction string (from the AI-generated step) to the
    /// AccessibilityEvent.EventType values that would satisfy it.
    /// Returns true if the given eventType is a valid match for the action string.
    private func eventTypeMatches(
        eventType: AccessibilityEvent.EventType,
        expectedActionString: String
    ) -> Bool {
        // Normalise to lowercase so the AI can return "Click" or "CLICK" without breaking this
        let normalisedAction = expectedActionString.lowercased()

        switch normalisedAction {
        case "click":
            // A click is modelled as a focus change — the user clicked a new element
            return eventType == .focusChanged

        case "focus":
            // Explicit focus change (tab or click)
            return eventType == .focusChanged

        case "valuechange", "valuechanged":
            // The user typed into a field or changed a control's value
            return eventType == .valueChanged

        case "open":
            // A new window appeared, or the user switched to an app
            return eventType == .windowCreated || eventType == .appActivated

        default:
            // Unknown action string — treat any event as a match rather than
            // blocking the user forever on an unrecognisable action type
            return true
        }
    }
}
