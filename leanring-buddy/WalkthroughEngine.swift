//
//  WalkthroughEngine.swift
//  leanring-buddy
//
//  Central coordinator for guided walkthroughs. Owns the full lifecycle:
//  AI step planning → user confirmation → step-by-step execution → completion.
//
//  Each executing step:
//    1. Speaks the instruction via TTS
//    2. Points the Luma cursor at the named UI element via CursorGuide (AI screenshot + AX fallback)
//    3. Installs a persistent AXObserver that fires on UI events in the target app
//    4a. Fast path: if the AX label matches the expected element name → immediately complete
//    4b. Slow path: debounced AI screenshot validation ("COMPLETED or INCOMPLETE?") → complete on yes
//    5. On a wrong-element focus event, speaks a gentle correction and re-points the cursor
//    6. On timeout, nudges the user and re-points; reschedules the nudge
//
//  CONCURRENCY SAFETY:
//  All state is @MainActor. Async callbacks (AXObserver C callback → Task @MainActor,
//  Timer → Task @MainActor) carry a `generation` integer that is incremented every time
//  a step ends. Any callback whose generation doesn't match `currentStepGeneration` is
//  silently dropped, preventing stale events from previous steps from affecting newer ones.
//

import AppKit
import ApplicationServices
import Combine
import Foundation

// MARK: - WalkthroughEngine

@MainActor
final class WalkthroughEngine: ObservableObject {
    static let shared = WalkthroughEngine()

    @Published private(set) var state: WalkthroughState = .idle

    // MARK: - Computed UI Properties

    /// True when the engine is in any non-idle, non-complete state.
    var isRunning: Bool {
        switch state {
        case .idle, .complete: return false
        default: return true
        }
    }

    /// The instruction for the currently active step, or empty string when not executing.
    var currentInstruction: String {
        guard case .executing(let steps, let currentIndex) = state,
              currentIndex < steps.count else { return "" }
        return steps[currentIndex].instruction
    }

    /// (currentStepNumber, totalStepCount) — 1-based, both zero when not executing.
    var progress: (currentStepNumber: Int, totalStepCount: Int) {
        guard case .executing(let steps, let currentIndex) = state else { return (0, 0) }
        return (currentIndex + 1, steps.count)
    }

    // MARK: - Dependencies

    private let taskPlanner = TaskPlanner()
    private let cursorGuide = CursorGuide.shared
    private let ttsClient = NativeTTSClient.shared

    // MARK: - Generation Counter
    //
    // Every time a step ends (via completion, skip, or cancel), `currentStepGeneration`
    // is incremented. AX callbacks and timers capture their generation at the moment they
    // are created. When they execute (possibly after a step has already ended), they compare
    // their captured generation to `currentStepGeneration` and drop themselves if they differ.
    // This makes all async callbacks automatically inert once their step has ended.
    private var currentStepGeneration: Int = 0

    // MARK: - Pointing Task

    // Stored so we can cancel an in-flight AI pointing call when the step ends.
    // Without this, a slow AI response from step N could move the cursor to step N's
    // element while the user is already working on step N+1.
    private var activePointingTask: Task<Void, Never>?

    // MARK: - AI Validation State

    private var isAIValidationInProgress: Bool = false
    private var lastAIValidationDate: Date = .distantPast

    /// Minimum seconds between consecutive AI screenshot validation calls.
    /// Each call takes 2-4 seconds, so this prevents pile-up of concurrent requests.
    private let minimumSecondsBetweenAIValidations: TimeInterval = 2.5

    // MARK: - AX Observer State

    /// The AXObserver installed for the current step's target app.
    /// Set to nil and removed from the run loop when the step ends.
    private var axObserver: AXObserver?

    // MARK: - AX Observer Context

    /// Carries the step generation and engine reference through the C callback's userData/refcon.
    /// C function pointers passed to AXObserverCreate cannot capture Swift context (they are
    /// @convention(c) and closures that capture variables don't satisfy that requirement). We
    /// work around this by heap-allocating a context object and passing its pointer as refcon
    /// to AXObserverAddNotification. The C callback reads it back with Unmanaged.fromOpaque.
    private final class WalkthroughObserverContext {
        // unowned: WalkthroughEngine is a singleton that outlives any observer
        unowned let engine: WalkthroughEngine
        let generation: Int

        init(engine: WalkthroughEngine, generation: Int) {
            self.engine = engine
            self.generation = generation
        }
    }

    /// Strong reference to the current observer context. Keeps the context alive for the
    /// duration of the observer's life. Set to nil in stopActiveStepAndCleanUp.
    private var axObserverContext: WalkthroughObserverContext?

    // MARK: - Nudge Timer State

    private var nudgeTimer: Timer?
    private var nudgeCount: Int = 0
    private let maximumInstructionNudgesBeforeSwitchingToPatientMessage: Int = 3

    // MARK: - Correction Debounce

    private var lastCorrectionDate: Date = .distantPast
    private let minimumSecondsBetweenCorrections: TimeInterval = 4.0

    private init() {}

    // MARK: - Public API

    /// Asks the AI to plan steps for `goal` then shows them to the user for confirmation.
    /// State transitions: idle → planning → confirming (on success) / idle (on failure)
    func startWalkthrough(goal: String) async {
        state = .planning

        let frontmostAppName = NSWorkspace.shared.frontmostApplication?.localizedName ?? "unknown"

        do {
            let walkthroughPlan = try await taskPlanner.planSteps(
                goal: goal,
                frontmostAppName: frontmostAppName
            )
            state = .confirming(walkthroughPlan.steps)
        } catch {
            print("[Luma] WalkthroughEngine: step planning failed — \(error.localizedDescription)")
            state = .idle
        }
    }

    /// Confirms the planned steps and starts executing from step 0.
    /// Must be called while in the `.confirming` state.
    func confirmAndBeginWalkthrough() {
        guard case .confirming(let steps) = state, !steps.isEmpty else {
            print("[Luma] WalkthroughEngine: confirmAndBeginWalkthrough called from wrong state")
            return
        }

        state = .executing(steps: steps, currentIndex: 0)
        executeStep(steps[0], allSteps: steps)
    }

    /// Skips the current step and advances without requiring the user to perform the action.
    func skipCurrentStep() {
        guard case .executing(let steps, let currentIndex) = state else { return }
        stopActiveStepAndCleanUp()
        advanceToNextStep(steps: steps, completedIndex: currentIndex)
    }

    /// Cancels the walkthrough immediately and returns to idle.
    func cancelWalkthrough() {
        stopActiveStepAndCleanUp()
        cursorGuide.clearGuidance()
        state = .idle
        print("[Luma] WalkthroughEngine: cancelled")
    }

    // MARK: - Step Lifecycle Cleanup

    /// Tears down everything associated with the current step and increments the generation counter.
    /// Must be called before starting a new step and before cancelling.
    private func stopActiveStepAndCleanUp() {
        // Increment generation: any in-flight callbacks from the current step will see their
        // captured generation no longer matches and will silently drop themselves.
        currentStepGeneration += 1

        // Cancel any in-flight AI pointing call (e.g. slow API response for a previous step's element)
        activePointingTask?.cancel()
        activePointingTask = nil

        // Remove the AX observer from the run loop so no new callbacks will fire.
        // Swift's ARC releases the AXObserver object when axObserver is set to nil.
        if let existingObserver = axObserver {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                AXObserverGetRunLoopSource(existingObserver),
                .commonModes
            )
        }
        axObserver = nil

        // Release the observer context — the C callback can no longer fire after the observer
        // was removed from the run loop above, and any in-flight Task closures captured
        // primitive values from the context (not the context itself), so this is safe.
        axObserverContext = nil

        // Cancel the nudge timer
        nudgeTimer?.invalidate()
        nudgeTimer = nil

        // Reset all per-step mutable state
        nudgeCount = 0
        isAIValidationInProgress = false
        lastCorrectionDate = .distantPast
        lastAIValidationDate = .distantPast
    }

    // MARK: - Step Execution

    /// Sets up everything needed for the user to work on `step`.
    private func executeStep(_ step: WalkthroughStep, allSteps: [WalkthroughStep]) {
        // stopActiveStepAndCleanUp increments the generation counter.
        // Capture the NEW value immediately so this step's callbacks carry the right generation.
        stopActiveStepAndCleanUp()
        let stepGeneration = currentStepGeneration

        let humanReadableStepNumber = step.index + 1
        print("[Luma] WalkthroughEngine: step \(humanReadableStepNumber)/\(allSteps.count) — '\(step.instruction)' (gen \(stepGeneration))")

        // 1. Speak the instruction so the user knows what to do
        ttsClient.speak("Step \(humanReadableStepNumber). \(step.instruction)")

        // 2. Point the cursor. Stored as a cancellable Task so we can abort it if the step
        //    ends before the AI response comes back (e.g. user completes the step quickly).
        activePointingTask = Task {
            await cursorGuide.pointAtElementViaAIScreenshot(
                named: step.elementName,
                inApp: step.isMenuBar ? nil : step.appBundleID
            )
        }

        // 3. Install the AX observer to detect when the user interacts with the target
        startWatching(for: step, allSteps: allSteps, generation: stepGeneration)

        // 4. Start the nudge timer in case the user doesn't act within timeoutSeconds
        startNudgeTimer(for: step, allSteps: allSteps, generation: stepGeneration)
    }

    // MARK: - AX Observer Management

    /// Creates and installs an AXObserver on the target app.
    /// Passes `generation` as context so stale callbacks from a previous step's observer
    /// are silently ignored even if they arrive after the step has ended.
    private func startWatching(for step: WalkthroughStep, allSteps: [WalkthroughStep], generation: Int) {
        // Determine which process to watch
        let targetPID: pid_t
        if let bundleID = step.appBundleID,
           let targetApp = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            targetPID = targetApp.processIdentifier
        } else if let frontmostApp = NSWorkspace.shared.frontmostApplication {
            targetPID = frontmostApp.processIdentifier
        } else {
            print("[Luma] WalkthroughEngine: cannot start watching — no target app found")
            return
        }

        // Allocate the context that carries both the engine reference and the step generation.
        // axObserverContext holds a strong reference, keeping the object alive for the observer's lifetime.
        let observerContext = WalkthroughObserverContext(engine: self, generation: generation)
        axObserverContext = observerContext
        // passUnretained is safe here — axObserverContext (the property above) is the owning reference.
        let contextPointer = Unmanaged.passUnretained(observerContext).toOpaque()

        var newObserver: AXObserver?

        // The C callback must be a non-capturing closure (@convention(c)).
        // We pass `generation` and `engine` through the userData/refcon pointer (contextPointer)
        // rather than capturing them, which would require a context-capturing closure and fail to compile.
        let createResult = AXObserverCreate(targetPID, { _, element, notification, userData in
            guard let userData = userData else { return }
            let context = Unmanaged<WalkthroughObserverContext>.fromOpaque(userData).takeUnretainedValue()

            // Extract values from the context synchronously here in the C callback.
            // The Task closure captures these scalars/references — not the context object itself —
            // so releasing axObserverContext later in stopActiveStepAndCleanUp is safe.
            let capturedEngine = context.engine
            let capturedGeneration = context.generation
            let capturedNotification = notification as String

            Task { @MainActor in
                capturedEngine.handleAccessibilityNotification(
                    element: element,
                    notification: capturedNotification,
                    generation: capturedGeneration
                )
            }
        }, &newObserver)

        guard createResult == .success, let createdObserver = newObserver else {
            print("[Luma] WalkthroughEngine: AXObserverCreate failed (error \(createResult.rawValue)) for PID \(targetPID)")
            return
        }

        let appElement = AXUIElementCreateApplication(targetPID)

        // Register for the four standard kAX notifications. We deliberately omit "AXMenuOpened" /
        // "AXMenuClosed" because those are private notifications that must be registered on the
        // system-wide AXUIElement to fire reliably — they silently fail on an app-level element.
        // Menu interactions are detected instead by the AI screenshot validator.
        let notificationsToRegister: [String] = [
            kAXFocusedUIElementChangedNotification,  // keyboard nav, most button clicks
            kAXValueChangedNotification,             // text field edits, checkbox toggles
            kAXWindowCreatedNotification,            // new windows / dialogs opening
            kAXSelectedTextChangedNotification,      // text selection in documents
        ]

        for notificationName in notificationsToRegister {
            AXObserverAddNotification(createdObserver, appElement, notificationName as CFString, contextPointer)
        }

        // .commonModes ensures callbacks fire even during menu tracking (NSEventTrackingRunLoopMode).
        // .defaultMode pauses during menu tracking, which is exactly when we need to detect completions.
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(createdObserver), .commonModes)
        axObserver = createdObserver

        print("[Luma] WalkthroughEngine: watching PID \(targetPID) for '\(step.elementName)'")
    }

    // MARK: - AX Event Handling

    /// Called by the AXObserver C callback (via Task @MainActor) on every UI event in the target app.
    ///
    /// Two-path validation:
    ///   Fast path — AX label matches expected element name → complete immediately
    ///   Slow path — debounced AI screenshot validation for events that AX can't label (button
    ///               clicks, context menu selections, dialog openings, etc.)
    private func handleAccessibilityNotification(element: AXUIElement, notification: String, generation: Int) {
        // Drop any callback whose generation doesn't match the current step.
        // This eliminates all races from stale observers and in-flight Task closures.
        guard generation == currentStepGeneration else { return }

        guard case .executing(let steps, let currentIndex) = state,
              currentIndex < steps.count else { return }

        let currentStep = steps[currentIndex]

        // If the step has no specific element requirement, any action in the right app counts
        if currentStep.elementName.isEmpty {
            completeCurrentStep(steps: steps, currentIndex: currentIndex)
            return
        }

        // --- Read the element's accessible label ---
        var titleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef)
        let rawTitle = (titleRef as? String) ?? ""

        var descriptionRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descriptionRef)
        let rawDescription = (descriptionRef as? String) ?? ""

        // Prefer title; fall back to description for elements that only have one
        let elementLabel = rawTitle.isEmpty ? rawDescription : rawTitle

        print("[Luma] AX event: \(notification) on '\(elementLabel)'")

        // --- Fast path: AX label matches ---
        // Exact match or the label contains the expected name as a substring.
        // We do NOT check "expected contains label" — that's too broad (e.g. "load" matching "Downloads").
        if !elementLabel.isEmpty {
            let labelLower = elementLabel.lowercased()
            let expectedLower = currentStep.elementName.lowercased()

            if labelLower == expectedLower || labelLower.contains(expectedLower) {
                print("[Luma] WalkthroughEngine: fast-path match on '\(elementLabel)'")
                completeCurrentStep(steps: steps, currentIndex: currentIndex)
                return
            }

            // Known label but not the target — speak a gentle correction.
            // Only for focus events (not value/window events which are less user-intentional).
            // Not while an AI validation is in progress (avoids contradictory feedback).
            if notification == kAXFocusedUIElementChangedNotification && !isAIValidationInProgress {
                let timeSinceLastCorrection = Date().timeIntervalSince(lastCorrectionDate)
                if timeSinceLastCorrection >= minimumSecondsBetweenCorrections {
                    lastCorrectionDate = Date()
                    ttsClient.speak("We need \(currentStep.elementName). \(currentStep.instruction)")
                    activePointingTask?.cancel()
                    activePointingTask = Task {
                        await cursorGuide.pointAtElementViaAIScreenshot(
                            named: currentStep.elementName,
                            inApp: currentStep.appBundleID
                        )
                    }
                }
            }
        }

        // --- Slow path: AI screenshot validation ---
        // Fires on ANY AX event (not just focus changes) so it catches button clicks, menu
        // selections, dialog opens — things that don't always emit a labelled focus event.
        // Debounced: at most one AI call every minimumSecondsBetweenAIValidations seconds.
        let timeSinceLastValidation = Date().timeIntervalSince(lastAIValidationDate)
        guard !isAIValidationInProgress && timeSinceLastValidation >= minimumSecondsBetweenAIValidations else { return }

        isAIValidationInProgress = true
        lastAIValidationDate = Date()

        Task {
            await self.validateStepCompletionViaAIScreenshot(
                step: currentStep,
                steps: steps,
                currentIndex: currentIndex,
                generation: generation
            )
        }
    }

    // MARK: - AI Screenshot Validation

    /// Captures the screen and asks the AI whether the user has completed the current step.
    /// Advances the walkthrough if the AI confirms completion.
    ///
    /// Checks `generation == currentStepGeneration` three times:
    ///   1. Before capturing the screenshot (early exit if already advanced)
    ///   2. After the capture (step may have been skipped/cancelled during the await)
    ///   3. After the API call returns (same reason)
    private func validateStepCompletionViaAIScreenshot(
        step: WalkthroughStep,
        steps: [WalkthroughStep],
        currentIndex: Int,
        generation: Int
    ) async {
        defer {
            // Always clear the in-progress flag, even on early return or error
            isAIValidationInProgress = false
        }

        // Pre-check before expensive work
        guard generation == currentStepGeneration,
              case .executing(_, let activeIndex) = state,
              activeIndex == currentIndex else { return }

        do {
            let screenCaptures = try await CompanionScreenCaptureUtility.captureAllScreensAsJPEG()

            // Post-capture check — the user may have skipped or cancelled during the async await
            guard generation == currentStepGeneration,
                  case .executing(_, let activeIndex) = state,
                  activeIndex == currentIndex else { return }

            let imageTuples = screenCaptures.map { (data: $0.imageData, label: $0.label) }

            let validationSystemPrompt = """
            You are a walkthrough step completion validator.
            The user was guided to: "\(step.instruction)"
            The target UI element was: "\(step.elementName)"

            Look at the screenshot and determine if the user has COMPLETED this step.

            COMPLETED signs:
            - A context menu or menu is now open on screen
            - A dialog, sheet, popover, or new window appeared
            - The app's visual state clearly changed to reflect the action (e.g., file moved, window opened)
            - The target element has been activated and something visibly changed

            INCOMPLETE signs:
            - The screen looks the same as before (no menus, no dialogs, no state change)
            - The target element is still idle

            Reply with exactly one word: COMPLETED or INCOMPLETE
            """

            let (aiResponse, _) = try await APIClient.shared.analyzeImage(
                images: imageTuples,
                systemPrompt: validationSystemPrompt,
                conversationHistory: [],
                userPrompt: "Has the user completed the step?"
            )

            let trimmedResponse = aiResponse.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            print("[Luma] WalkthroughEngine AI validation: '\(trimmedResponse)'")

            // Post-API check — avoid acting on a result for a step that's already gone
            guard generation == currentStepGeneration,
                  case .executing(_, let activeIndex) = state,
                  activeIndex == currentIndex else { return }

            if trimmedResponse.hasPrefix("COMPLETED") {
                completeCurrentStep(steps: steps, currentIndex: currentIndex)
            }
        } catch {
            print("[Luma] WalkthroughEngine AI validation failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Step Completion

    /// Marks the current step as done, speaks the confirmation, then advances after a short pause.
    private func completeCurrentStep(steps: [WalkthroughStep], currentIndex: Int) {
        stopActiveStepAndCleanUp()
        ttsClient.speak("Got it.")

        // Use Task @MainActor + sleep instead of DispatchQueue.main.asyncAfter.
        // This keeps us inside Swift's structured concurrency and actor model, avoiding the
        // actor-isolation gap that asyncAfter creates between dispatch and execution.
        let capturedSteps = steps
        let capturedIndex = currentIndex

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000) // 0.8 seconds
            self.advanceToNextStep(steps: capturedSteps, completedIndex: capturedIndex)
        }
    }

    // MARK: - Step Advancement

    /// Moves to the step after `completedIndex`, or completes the walkthrough if that was the last.
    ///
    /// Guards on both the state AND the index to prevent double-advancement.
    /// Without the index guard, a stale Task from a previous completion can call advanceToNextStep
    /// on a step that's already been advanced (e.g., after a quick skip), skipping an extra step.
    private func advanceToNextStep(steps: [WalkthroughStep], completedIndex: Int) {
        // Only advance if the engine is still executing the step we think it is.
        // This guard catches races where completeCurrentStep fires twice or where
        // skipCurrentStep was called during the 0.8s sleep.
        guard case .executing(let currentSteps, let currentIndex) = state,
              currentIndex == completedIndex else {
            print("[Luma] WalkthroughEngine: advanceToNextStep dropped (state changed before advancing)")
            return
        }

        let nextIndex = completedIndex + 1

        if nextIndex >= currentSteps.count {
            finishWalkthrough()
            return
        }

        state = .executing(steps: currentSteps, currentIndex: nextIndex)
        executeStep(currentSteps[nextIndex], allSteps: currentSteps)
    }

    // MARK: - Completion

    private func finishWalkthrough() {
        stopActiveStepAndCleanUp()
        cursorGuide.clearGuidance()
        state = .complete
        ttsClient.speak("You did it! Task complete.")

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000) // 2.5 seconds
            if case .complete = self.state {
                self.state = .idle
            }
        }
    }

    // MARK: - Nudge Timer

    /// Schedules a one-shot timer that fires `fireNudge` after `step.timeoutSeconds`.
    /// The timer reschedules itself after each nudge so nudges keep repeating until the step ends.
    private func startNudgeTimer(for step: WalkthroughStep, allSteps: [WalkthroughStep], generation: Int) {
        nudgeTimer?.invalidate()
        nudgeTimer = Timer.scheduledTimer(
            withTimeInterval: TimeInterval(step.timeoutSeconds),
            repeats: false
        ) { [weak self] _ in
            // Dispatch to main actor via Task to stay within Swift's actor model
            Task { @MainActor [weak self] in
                self?.fireNudge(for: step, allSteps: allSteps, generation: generation)
            }
        }
    }

    /// Speaks a reminder and re-points the cursor, then reschedules the nudge timer.
    private func fireNudge(for step: WalkthroughStep, allSteps: [WalkthroughStep], generation: Int) {
        // Drop nudges from previous steps using the generation counter
        guard generation == currentStepGeneration,
              case .executing = state else { return }

        nudgeCount += 1

        if nudgeCount >= maximumInstructionNudgesBeforeSwitchingToPatientMessage {
            ttsClient.speak("Take your time, I'm here when you're ready.")
        } else {
            ttsClient.speak("Still on step \(step.index + 1). \(step.instruction)")
        }

        // Re-point the cursor so the user can find the target element
        if !step.elementName.isEmpty {
            activePointingTask?.cancel()
            activePointingTask = Task {
                await cursorGuide.pointAtElementViaAIScreenshot(
                    named: step.elementName,
                    inApp: step.isMenuBar ? nil : step.appBundleID
                )
            }
        }

        // Reschedule — nudges keep firing until the step ends
        startNudgeTimer(for: step, allSteps: allSteps, generation: generation)
    }
}
