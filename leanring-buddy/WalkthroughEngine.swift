//
//  WalkthroughEngine.swift
//  leanring-buddy
//
//  Central coordinator for the guided walkthrough system. Drives the full
//  lifecycle: goal → AI step planning → user confirmation → step-by-step
//  guidance → completion. Wires together TaskPlanner, AccessibilityWatcher,
//  StepValidator, FeedbackEngine, and CursorGuide into a single state machine.
//

import AppKit
import Combine
import Foundation

// MARK: - WalkthroughEngine

@MainActor
final class WalkthroughEngine: ObservableObject {
    static let shared = WalkthroughEngine()

    @Published private(set) var state: WalkthroughState = .idle

    // MARK: - Computed Properties

    /// True when a walkthrough is in any non-idle state.
    var isActive: Bool {
        if case .idle = state { return false }
        return true
    }

    /// The zero-based index of the current step, or nil if not in an active state.
    var currentStepIndex: Int? {
        if case .active(_, _, let index) = state { return index }
        return nil
    }

    /// All steps in the current walkthrough, or nil if not in confirming/active/complete state.
    var currentSteps: [WalkthroughStep]? {
        switch state {
        case .confirming(_, let steps):
            return steps
        case .active(_, let steps, _):
            return steps
        default:
            return nil
        }
    }

    // MARK: - Dependencies

    private let taskPlanner = TaskPlanner()
    private let accessibilityWatcher = AccessibilityWatcher.shared
    private let stepValidator = StepValidator()
    private let feedbackEngine = FeedbackEngine.shared
    private let cursorGuide = CursorGuide.shared

    // MARK: - Private State

    /// The current step-timeout task. Cancelled when advancing to the next step
    /// so a new timeout can be set for the incoming step.
    private var stepTimeoutTask: Task<Void, Never>?

    private init() {
        // Wire up the AccessibilityWatcher callback so every UI event flows
        // through our validation logic automatically.
        accessibilityWatcher.onEvent = { [weak self] accessibilityEvent in
            Task { @MainActor [weak self] in
                self?.handleAccessibilityEvent(accessibilityEvent)
            }
        }
    }

    // MARK: - Public API

    /// Starts planning a walkthrough for the given user goal.
    /// Checks accessibility permission first — if denied, prompts the user
    /// to grant it in System Settings and returns without starting.
    ///
    /// State transitions: idle → planning → confirming (on success)
    ///                    idle → idle (on error or permission denial)
    func startWalkthrough(goal: String) async {
        // Accessibility is required for step validation — without it we can't
        // detect when the user completes a step.
        guard accessibilityWatcher.isAccessibilityPermissionGranted else {
            accessibilityWatcher.checkAndRequestPermission()
            print("WalkthroughEngine: accessibility permission not granted — prompting user")
            return
        }

        state = .planning(goal: goal)

        let frontmostAppName = NSWorkspace.shared.frontmostApplication?.localizedName ?? "unknown"

        do {
            let generatedSteps = try await taskPlanner.planSteps(
                goal: goal,
                frontmostAppName: frontmostAppName
            )

            // Transition to confirming so the UI can show the steps and wait for
            // the user to say "yes, begin" before we start watching for actions.
            state = .confirming(goal: goal, steps: generatedSteps)

            // Start watching for accessibility events now so we're ready the moment
            // the user confirms. There's no cost to watching before confirmation.
            accessibilityWatcher.startWatching()

        } catch {
            print("WalkthroughEngine: step planning failed — \(error.localizedDescription)")
            state = .idle
        }
    }

    /// Confirms the planned steps and begins the walkthrough.
    /// Should be called after the user reviews the step list and approves.
    ///
    /// State transitions: confirming → active(index: 0)
    func confirmAndBeginWalkthrough() {
        guard case .confirming(let goal, let steps) = state else {
            print("WalkthroughEngine: confirmAndBeginWalkthrough called while not in confirming state")
            return
        }

        state = .active(goal: goal, steps: steps, currentIndex: 0)
        advanceToStep(0)
    }

    /// Skips the current step and advances to the next one without requiring
    /// the user to perform the expected action. Useful when a step doesn't apply
    /// or the user already knows how to do it.
    func skipCurrentStep() {
        guard case .active(let goal, let steps, let currentIndex) = state else { return }

        let nextIndex = currentIndex + 1

        if nextIndex < steps.count {
            state = .active(goal: goal, steps: steps, currentIndex: nextIndex)
            advanceToStep(nextIndex)
        } else {
            completeWalkthrough()
        }
    }

    /// Cancels the walkthrough and returns to the idle state immediately.
    /// Cleans up all timers and observers.
    func cancelWalkthrough() {
        cancelStepTimeout()
        accessibilityWatcher.stopWatching()
        cursorGuide.clearGuidance()
        state = .idle
        feedbackEngine.resetNudgeCount()
    }

    // MARK: - Accessibility Event Handling

    /// Called whenever AccessibilityWatcher fires an event.
    /// Delegates to StepValidator to determine whether to advance, correct, or ignore.
    private func handleAccessibilityEvent(_ accessibilityEvent: AccessibilityEvent) {
        // Only process events while a step is actively in progress
        guard case .active(let goal, let steps, let currentIndex) = state else { return }
        guard currentIndex < steps.count else { return }

        let currentStep = steps[currentIndex]
        let validationResult = stepValidator.validate(event: accessibilityEvent, step: currentStep)

        switch validationResult {
        case .correct:
            // The user completed this step — announce success and advance.
            // "Good." is spoken here; the next step's instruction is spoken by
            // announceStepStarted inside advanceToStep so there's no gap between them.
            let nextStepIndex = currentIndex + 1

            Task {
                await feedbackEngine.announceStepCorrect()
            }

            if nextStepIndex < steps.count {
                state = .active(goal: goal, steps: steps, currentIndex: nextStepIndex)
                advanceToStep(nextStepIndex)
            } else {
                completeWalkthrough()
            }

        case .incorrect(let reason):
            // The user did something in the right app but it wasn't the right action.
            // Re-state the instruction to guide them back on track.
            Task {
                await feedbackEngine.announceStepIncorrect(
                    reason: reason,
                    currentInstruction: currentStep.instruction
                )
            }

            // Re-point the cursor at the target element in case the user lost track of it
            if let expectedElementTitle = currentStep.expectedElement {
                Task {
                    await cursorGuide.pointAtElement(
                        withTitle: expectedElementTitle,
                        inApp: currentStep.appBundleID
                    )
                }
            }

        case .unrelated:
            // The event has nothing to do with the current step — ignore it silently
            break
        }
    }

    // MARK: - Step Advancement

    /// Prepares everything needed for the user to start working on the given step:
    /// cancels the previous timeout, resets nudge tracking, speaks the instruction,
    /// points the cursor, and starts a new timeout timer.
    private func advanceToStep(_ stepIndex: Int) {
        guard case .active(_, let steps, _) = state else { return }
        guard stepIndex < steps.count else { return }

        cancelStepTimeout()
        feedbackEngine.resetNudgeCount()

        let stepToActivate = steps[stepIndex]

        // Speak the step instruction immediately so the user knows what to do
        // without waiting for the 30-second timeout nudge to fire. The step number
        // is 1-based in the announcement so it matches how humans count steps.
        let humanReadableStepNumber = stepToActivate.stepIndex + 1
        Task {
            await feedbackEngine.announceStepStarted(
                instruction: stepToActivate.instruction,
                humanReadableStepNumber: humanReadableStepNumber
            )
        }

        // Point the cursor at the expected element if the step specifies one.
        // We fire this as a background task so it doesn't block the state transition.
        if let expectedElementTitle = stepToActivate.expectedElement {
            Task {
                await cursorGuide.pointAtElement(
                    withTitle: expectedElementTitle,
                    inApp: stepToActivate.appBundleID
                )
            }
        } else {
            // No specific element to point at — clear any previous cursor guidance
            cursorGuide.clearGuidance()
        }

        startStepTimeout(for: stepToActivate)
    }

    // MARK: - Step Completion

    /// Called when the last step in the walkthrough is completed.
    /// Announces completion via TTS, then returns to idle after a short delay.
    private func completeWalkthrough() {
        cancelStepTimeout()

        // Extract the goal before transitioning state so we can pass it to the TTS call
        let walkthroughGoal: String
        if case .active(let goal, _, _) = state {
            walkthroughGoal = goal
        } else {
            walkthroughGoal = ""
        }

        state = .complete(goal: walkthroughGoal)
        cursorGuide.clearGuidance()
        accessibilityWatcher.stopWatching()

        Task {
            await feedbackEngine.announceWalkthroughComplete(goal: walkthroughGoal)

            // Give the user a moment to read/hear the completion message before
            // the UI snaps back to idle state — 2 seconds feels natural.
            try? await Task.sleep(nanoseconds: 2_000_000_000)

            self.state = .idle
        }
    }

    // MARK: - Step Timeout

    /// Starts an async timeout task for the given step. When it fires, the
    /// FeedbackEngine speaks a nudge and the timeout re-schedules itself,
    /// so the user continues receiving nudges until they complete the step.
    private func startStepTimeout(for step: WalkthroughStep) {
        // Convert the step timeout from seconds to nanoseconds for Task.sleep
        let timeoutDurationNanoseconds: UInt64 = UInt64(step.timeoutSeconds) * 1_000_000_000

        stepTimeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: timeoutDurationNanoseconds)
            } catch {
                // Task was cancelled (step advanced or walkthrough cancelled) — exit cleanly
                return
            }

            guard let self = self else { return }

            // Guard: only fire the nudge if we're still on the same step
            guard case .active(_, let steps, let currentIndex) = self.state,
                  currentIndex < steps.count,
                  steps[currentIndex].id == step.id
            else {
                return
            }

            let currentNudgeCount = self.feedbackEngine.currentNudgeCount

            await self.feedbackEngine.announceStepTimeout(
                currentInstruction: step.instruction,
                stepNumber: step.stepIndex,
                nudgesSoFar: currentNudgeCount
            )

            // Re-point the cursor in case the user has lost track of the target element
            if let expectedElementTitle = step.expectedElement {
                await self.cursorGuide.pointAtElement(
                    withTitle: expectedElementTitle,
                    inApp: step.appBundleID
                )
            }

            // Reschedule so the nudge fires again if the user still hasn't acted.
            // We start a new timeout (not recurse) to avoid stack growth.
            self.startStepTimeout(for: step)
        }
    }

    /// Cancels the current step timeout task if one is running.
    /// Called before advancing to a new step or cancelling the walkthrough.
    private func cancelStepTimeout() {
        stepTimeoutTask?.cancel()
        stepTimeoutTask = nil
    }
}
