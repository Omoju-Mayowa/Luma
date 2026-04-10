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

    // MARK: - Mouse Event Monitor

    // Global monitor for left-click and right-click events. The AX observer and AX polling
    // only fire on keyboard-focus changes — sidebar clicks, right-clicks, and most direct
    // mouse interactions don't change kAXFocusedUIElementAttribute and are therefore missed.
    // This monitor catches those interactions and immediately triggers AX + AI validation.
    private var mouseEventMonitor: Any?

    // MARK: - AI Validation State

    private var isAIValidationInProgress: Bool = false
    private var lastAIValidationDate: Date = .distantPast

    /// Minimum seconds between consecutive AI screenshot validation calls.
    private let minimumSecondsBetweenAIValidations: TimeInterval = 1.5

    /// Tracks the last time the user visibly interacted (mouse click or AX event).
    /// The periodic validation timer only fires AI validation when this is recent —
    /// prevents the AI from marking a step complete just because 3 seconds passed
    /// with nothing happening (idle screen → permissive prompt → false COMPLETED).
    private var lastUserInteractionDate: Date = .distantPast

    /// Seconds of inactivity after which the periodic timer skips AI validation.
    /// If the user hasn't clicked or triggered an AX event in this window, there's
    /// no visual state change to validate and we'd risk a false positive.
    private let maximumSecondsToValidateAfterLastInteraction: TimeInterval = 6.0

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

    // MARK: - AX Polling State

    /// 0.3-second repeating timer that reads the system-wide focused element and checks
    /// it against the expected step element. This catches interactions (button clicks, menu
    /// selections) that don't reliably emit AXObserver notifications in every app.
    private var axPollingTimer: Timer?

    // MARK: - Periodic AI Validation State

    /// 3-second repeating timer that triggers AI screenshot validation independently of AX events.
    /// Many interactions (context menu picks, drag-and-drop, keyboard shortcuts) don't emit any
    /// AX focus notification. Without this timer, validateStepCompletionViaAIScreenshot would
    /// only fire when the AXObserver happens to deliver an event — which is unreliable for those cases.
    private var periodicValidationTimer: Timer?

    // MARK: - Nudge Timer State

    private var nudgeTimer: Timer?
    private var nudgeCount: Int = 0
    private let maximumInstructionNudgesBeforeSwitchingToPatientMessage: Int = 3
    /// After this many nudges, Luma disengages rather than continuing to repeat.
    /// Nudge-count-based (not time-based) so it scales correctly with any timeoutSeconds value.
    private let maximumTotalNudgesBeforeDisengaging: Int = 5

    // MARK: - Correction Debounce

    private var lastCorrectionDate: Date = .distantPast
    private let minimumSecondsBetweenCorrections: TimeInterval = 2.0

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

    /// Plans steps for `goal` via AI and immediately starts executing — no confirmation dialog.
    /// Used when LumaTaskClassifier routes a transcript to the multi-step path. The user
    /// hears the first instruction as soon as planning succeeds.
    ///
    /// Returns `true` if planning succeeded and execution started, `false` if planning failed.
    /// CompanionManager uses the return value to fall back to the voice response path when
    /// this returns false — so the user always gets SOME response even if planning fails.
    ///
    /// State transitions: idle → planning → executing (skips confirming entirely)
    func startWalkthroughSilently(goal: String) async -> Bool {
        guard !isRunning else {
            print("[Luma] WalkthroughEngine: startWalkthroughSilently ignored — engine already running")
            return false
        }

        state = .planning
        let frontmostAppName = NSWorkspace.shared.frontmostApplication?.localizedName ?? "unknown"

        do {
            let walkthroughPlan = try await taskPlanner.planSteps(
                goal: goal,
                frontmostAppName: frontmostAppName
            )

            guard !walkthroughPlan.steps.isEmpty else {
                print("[Luma] WalkthroughEngine: plan returned 0 steps — returning to idle")
                state = .idle
                return false
            }

            print("[Luma] WalkthroughEngine: silent start — \(walkthroughPlan.steps.count) step(s) planned")
            state = .executing(steps: walkthroughPlan.steps, currentIndex: 0)
            executeStep(walkthroughPlan.steps[0], allSteps: walkthroughPlan.steps)
            return true
        } catch {
            print("[Luma] WalkthroughEngine: silent planning failed — \(error.localizedDescription)")
            state = .idle
            return false
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

    /// Directly starts executing a pre-built list of steps without AI planning or user confirmation.
    /// Used by OfflineGuideManager to run offline guides that don't need an API call.
    func executeSteps(_ steps: [WalkthroughStep]) {
        guard !steps.isEmpty else {
            print("[Luma] WalkthroughEngine: executeSteps called with empty array — ignored")
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

        // Remove the global mouse event monitor — no further clicks should trigger validation
        if let existingMonitor = mouseEventMonitor {
            NSEvent.removeMonitor(existingMonitor)
            mouseEventMonitor = nil
        }

        // Cancel the AX polling timer
        axPollingTimer?.invalidate()
        axPollingTimer = nil

        // Cancel the periodic AI validation timer
        periodicValidationTimer?.invalidate()
        periodicValidationTimer = nil

        // Cancel the nudge timer
        nudgeTimer?.invalidate()
        nudgeTimer = nil

        // Reset all per-step mutable state
        nudgeCount = 0
        isAIValidationInProgress = false
        lastCorrectionDate = .distantPast
        lastAIValidationDate = .distantPast
        lastUserInteractionDate = .distantPast
    }

    // MARK: - Element Pointing

    /// Points the Luma cursor at `elementName` using LumaImageProcessingEngine (AX + visual fusion).
    /// Falls back to CursorGuide's AI screenshot path if LIPE finds nothing above its
    /// confidence threshold. `bubbleText` is shown in the small speech bubble when the cursor arrives.
    private func pointAtStepElement(
        elementName: String,
        appBundleID: String?,
        isMenuBar: Bool,
        bubbleText: String?
    ) async {
        guard !elementName.isEmpty else { return }

        let candidate = await LumaImageProcessingEngine.shared.findElement(
            query: elementName,
            appBundleID: isMenuBar ? nil : appBundleID,
            isMenuBar: isMenuBar
        )

        if let confirmedCandidate = candidate {
            LumaImageProcessingEngine.shared.pointCursor(at: confirmedCandidate, bubbleText: bubbleText)
        } else {
            // LIPE confidence too low — fall back to the AI screenshot path which asks
            // the model to visually locate the element when AX and on-device vision fail.
            await cursorGuide.pointAtElementViaAIScreenshot(
                named: elementName,
                inApp: isMenuBar ? nil : appBundleID,
                bubbleText: bubbleText
            )
        }
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

        // Bubble text for the small speech bubble shown next to the Luma cursor.
        // Kept short so it fits the bubble — the full instruction plays via TTS.
        let stepBubbleText = step.elementName.isEmpty ? "here!" : "→ \(step.elementName)"

        // 2. Point the cursor. Stored as a cancellable Task so we can abort it if the step
        //    ends before the element is found (e.g. user completes the step quickly).
        //    Uses LIPE (AX + visual fusion) with CursorGuide AI as fallback.
        activePointingTask = Task {
            await self.pointAtStepElement(
                elementName: step.elementName,
                appBundleID: step.appBundleID,
                isMenuBar: step.isMenuBar,
                bubbleText: stepBubbleText
            )
        }

        // 3. Install the AX observer to detect when the user interacts with the target
        startWatching(for: step, allSteps: allSteps, generation: stepGeneration)

        // 4. Start AX polling (0.5s) to catch keyboard-driven interactions the observer misses
        startAXPolling(for: step, allSteps: allSteps, generation: stepGeneration)

        // 5. Start the nudge timer in case the user doesn't act within timeoutSeconds
        startNudgeTimer(for: step, allSteps: allSteps, generation: stepGeneration)

        // 6. Start periodic AI validation to catch completions the AX observer misses.
        //    Context menu picks, keyboard shortcuts, and drag-and-drop don't emit AX focus
        //    events, so the AXObserver slow path never fires for those interactions.
        startPeriodicValidationTimer()

        // 7. Start global mouse event monitoring.
        //    Sidebar clicks, right-clicks, and direct mouse interactions don't change
        //    AX keyboard focus, so the AXObserver and polling timer miss them entirely.
        //    This monitor fires immediately on any click and triggers fast AI validation.
        startMouseEventMonitoring(for: step, allSteps: allSteps, generation: stepGeneration)
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

        // Register for AX notifications. More notification types means fewer interactions slip
        // through to the slower AI validation path.
        // Note: AXMenuOpened/AXMenuClosed must be registered on the system-wide element to fire
        // reliably — they silently fail on an app-level element. Menu interactions are caught by
        // the AX polling timer instead.
        let notificationsToRegister: [String] = [
            kAXFocusedUIElementChangedNotification,     // keyboard nav, most button clicks
            kAXValueChangedNotification,                // text field edits, checkbox toggles
            kAXWindowCreatedNotification,               // new windows / dialogs opening
            kAXSelectedTextChangedNotification,         // text selection in documents
            kAXUIElementDestroyedNotification,          // element removed (e.g. popover closed)
            kAXFocusedWindowChangedNotification,        // window focus switched
            kAXSelectedChildrenChangedNotification,     // list/outline selection changed
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

    // MARK: - Mouse Event Monitoring

    /// Installs a global NSEvent monitor for left-click and right-click events.
    ///
    /// Why this is needed: the AXObserver and AX polling timer only detect changes in
    /// keyboard focus (kAXFocusedUIElementAttribute). Most mouse-driven interactions —
    /// Finder sidebar clicks, right-clicks opening context menus, System Settings category
    /// selection — do NOT change keyboard focus and are therefore invisible to those paths.
    ///
    /// This monitor fires on any mouse click, immediately runs the AX check in case focus
    /// did change, then schedules an AI screenshot validation 0.6s later so the UI has
    /// time to visually settle (context menu to appear, sidebar to update, etc.) before
    /// the screenshot is taken.
    private func startMouseEventMonitoring(for step: WalkthroughStep, allSteps: [WalkthroughStep], generation: Int) {
        if let existingMonitor = mouseEventMonitor {
            NSEvent.removeMonitor(existingMonitor)
        }

        mouseEventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseUp, .rightMouseDown]
        ) { [weak self] clickedEvent in
            Task { @MainActor [weak self] in
                guard let self = self,
                      generation == self.currentStepGeneration else { return }

                // Use AX hit-testing to identify exactly which element was clicked.
                // This gives us ground-truth label data without taking a screenshot,
                // so we can reject wrong-element clicks immediately without any AI call.
                let clickLocationInAppKitCoords = NSEvent.mouseLocation
                let clickedElementLabel = self.getAXElementLabel(atAppKitPoint: clickLocationInAppKitCoords)

                if let label = clickedElementLabel, !label.isEmpty {
                    // We have an AX label — compare directly against the expected element name.
                    // Accept if the label contains the target OR the target contains the label
                    // (handles cases like label="Downloads" when target="Downloads Folder").
                    let labelLowercased = label.lowercased()
                    let targetLowercased = step.elementName.lowercased()
                    let isCorrectElement = labelLowercased == targetLowercased
                        || labelLowercased.contains(targetLowercased)
                        || (targetLowercased.contains(labelLowercased) && label.count > 3)

                    if isCorrectElement {
                        // Exact match — complete the step without any AI call.
                        self.lastUserInteractionDate = Date()
                        if case .executing(let currentSteps, let currentIndex) = self.state {
                            self.completeCurrentStep(steps: currentSteps, currentIndex: currentIndex)
                        }
                    }
                    // Wrong element — silently ignore. No interaction stamp, no AI validation.
                    return
                }

                // No AX label available (some elements don't expose one, e.g. canvas areas).
                // Fall back to timed AI screenshot validation as a last resort.
                self.lastUserInteractionDate = Date()
                try? await Task.sleep(nanoseconds: 600_000_000)
                guard generation == self.currentStepGeneration else { return }
                self.triggerPeriodicAIValidationIfNeeded()
            }
        }
    }

    /// Returns the AX accessibility label of the UI element at the given AppKit screen point.
    /// AppKit uses bottom-left origin (Y increases upward); AX/Quartz uses top-left origin
    /// (Y increases downward), so we flip Y relative to the main screen height before querying.
    /// Tries kAXTitleAttribute, then kAXDescriptionAttribute, then kAXValueAttribute in order.
    private func getAXElementLabel(atAppKitPoint appKitPoint: CGPoint) -> String? {
        let mainScreenHeight = NSScreen.screens.first?.frame.height ?? 0
        let axX = Float(appKitPoint.x)
        let axY = Float(mainScreenHeight - appKitPoint.y)

        let systemWideElement = AXUIElementCreateSystemWide()
        var axElement: AXUIElement?
        guard AXUIElementCopyElementAtPosition(systemWideElement, axX, axY, &axElement) == .success,
              let axElement = axElement else { return nil }

        var titleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(axElement, kAXTitleAttribute as CFString, &titleRef)
        if let title = titleRef as? String, !title.isEmpty { return title }

        var descriptionRef: CFTypeRef?
        AXUIElementCopyAttributeValue(axElement, kAXDescriptionAttribute as CFString, &descriptionRef)
        if let description = descriptionRef as? String, !description.isEmpty { return description }

        var valueRef: CFTypeRef?
        AXUIElementCopyAttributeValue(axElement, kAXValueAttribute as CFString, &valueRef)
        if let value = valueRef as? String, !value.isEmpty { return value }

        return nil
    }

    // MARK: - AX Polling

    /// Starts a 0.5-second repeating timer that reads the system-wide focused element and
    /// compares it to the expected step element. This catches button clicks and menu selections
    /// that don't always emit AXObserver focus-changed notifications.
    private func startAXPolling(for step: WalkthroughStep, allSteps: [WalkthroughStep], generation: Int) {
        axPollingTimer?.invalidate()
        // 0.5s interval instead of 0.3s — the mouse event monitor now handles real-time
        // click detection, so the polling timer is a secondary fallback for keyboard-driven
        // interactions. Reducing frequency cuts synchronous AXUIElementCopyAttributeValue
        // calls on the main thread, which was causing perceptible lag when the target app
        // (e.g. System Settings, Finder under memory pressure) was slow to respond.
        axPollingTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkFocusedElementForStepCompletion(step: step, allSteps: allSteps, generation: generation)
            }
        }
    }

    /// Reads the system-wide focused element via AX and checks whether it matches the current step's
    /// expected element. If it does, marks the step complete. This runs every 0.3 seconds as a
    /// fast supplement to the AXObserver — it catches interactions (clicks, menu picks) that don't
    /// always emit a focus-changed notification.
    private func checkFocusedElementForStepCompletion(
        step: WalkthroughStep,
        allSteps: [WalkthroughStep],
        generation: Int
    ) {
        guard generation == currentStepGeneration,
              case .executing(let steps, let currentIndex) = state,
              currentIndex < steps.count else { return }

        let currentStep = steps[currentIndex]
        guard !currentStep.elementName.isEmpty else { return }

        // Read the currently focused element from the system-wide AX tree.
        // kAXFocusedUIElementAttribute on the system-wide element returns whatever
        // element currently has keyboard focus across all running apps.
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedElementRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElementRef
        ) == .success,
              let focusedElement = focusedElementRef else { return }

        let axElement = focusedElement as! AXUIElement

        var titleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(axElement, kAXTitleAttribute as CFString, &titleRef)
        let elementTitle = (titleRef as? String) ?? ""

        var descriptionRef: CFTypeRef?
        AXUIElementCopyAttributeValue(axElement, kAXDescriptionAttribute as CFString, &descriptionRef)
        let elementDescription = (descriptionRef as? String) ?? ""

        let elementLabel = elementTitle.isEmpty ? elementDescription : elementTitle
        guard !elementLabel.isEmpty else { return }

        let labelLower = elementLabel.lowercased()
        let expectedLower = currentStep.elementName.lowercased()

        let isMatch = labelLower == expectedLower
            || labelLower.contains(expectedLower)
            || (expectedLower.contains(labelLower) && labelLower.count > 3)

        if isMatch {
            print("[Luma] WalkthroughEngine: AX poll match on '\(elementLabel)' — step complete")
            completeCurrentStep(steps: steps, currentIndex: currentIndex)
        }
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

        // Any AX notification means the user did something — stamp interaction time so the
        // periodic validation timer knows real activity occurred and is allowed to validate.
        lastUserInteractionDate = Date()

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
        // Three conditions (in order of precision):
        //   1. Exact match
        //   2. Label contains the expected name (e.g. "Save As..." matches "Save")
        //   3. Expected name contains the label, but only for labels > 3 chars
        //      (e.g. "File" label matches step element "File menu")
        if !elementLabel.isEmpty {
            let labelLower = elementLabel.lowercased()
            let expectedLower = currentStep.elementName.lowercased()

            let isMatch = labelLower == expectedLower
                || labelLower.contains(expectedLower)
                || (expectedLower.contains(labelLower) && labelLower.count > 3)

            if isMatch {
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
                    let correctionBubbleText = "→ \(currentStep.elementName)"
                    activePointingTask?.cancel()
                    activePointingTask = Task {
                        await self.pointAtStepElement(
                            elementName: currentStep.elementName,
                            appBundleID: currentStep.appBundleID,
                            isMenuBar: currentStep.isMenuBar,
                            bubbleText: correctionBubbleText
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

            let targetElementDescription = step.elementName.isEmpty
                ? "(no specific element — any relevant action counts)"
                : "\"\(step.elementName)\""

            let validationSystemPrompt = """
            You are validating whether a macOS user completed a specific walkthrough step.

            Instruction given to the user: "\(step.instruction)"
            Target UI element: \(targetElementDescription)

            Look at the screenshot and answer: has this specific step been completed?

            Answer COMPLETED only if there is clear visual evidence the action was taken:
            - A context menu is currently open (proves a right-click happened)
            - A new dialog, sheet, alert, or window has appeared as a direct result of the action
            - The main content area now shows content that would only appear after interacting with the target (e.g. a folder's contents are visible after clicking that folder)
            - A sidebar item or list row matching the target is clearly highlighted/selected AND the content area reflects that selection
            - The target element shows a clear activated or pressed state that it would not have in its idle state

            Answer INCOMPLETE if:
            - No context menu, dialog, or new content is visible
            - The screen looks like a normal idle state — elements are visible but not interacted with
            - The target element is present on screen but shows no sign of having been clicked
            - You are not certain that the action described in the instruction has actually occurred

            Do not answer COMPLETED just because the target element is visible. It must show evidence of being actively interacted with.

            Reply with one word only: COMPLETED or INCOMPLETE
            """

            // Validation only needs 1 word ("COMPLETED" or "INCOMPLETE") — keep token budget tiny
            // so this call returns fast and doesn't waste quota.
            let (aiResponse, _) = try await APIClient.shared.analyzeImage(
                images: imageTuples,
                systemPrompt: validationSystemPrompt,
                conversationHistory: [],
                userPrompt: "Has the user completed the step?",
                maxOutputTokens: 16
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
            try? await Task.sleep(nanoseconds: 400_000_000) // 0.4 seconds — halved from 0.8s
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

    // MARK: - Periodic AI Validation

    /// Starts a 3-second repeating timer that calls `triggerPeriodicAIValidationIfNeeded`.
    /// The generation is NOT captured at timer creation — it is read fresh on each fire
    /// so the check always compares against whichever step is currently live.
    private func startPeriodicValidationTimer() {
        periodicValidationTimer?.invalidate()
        periodicValidationTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.triggerPeriodicAIValidationIfNeeded()
            }
        }
    }

    /// Reads the current engine state and fires an AI screenshot validation if the debounce
    /// guards allow it. Called every 3 seconds by the periodic validation timer.
    private func triggerPeriodicAIValidationIfNeeded() {
        // Read the live generation at fire time — never captured at timer creation.
        // This guarantees we validate the step that is actually running right now.
        let generationAtFireTime = currentStepGeneration

        guard case .executing(let steps, let currentIndex) = state,
              currentIndex < steps.count else { return }

        let currentStep = steps[currentIndex]

        // Only validate if the user has recently interacted (clicked or triggered an AX event).
        // Without this gate, the timer fires every 3s on an idle screen and the AI marks the
        // step complete despite no visible state change — causing false positive completions.
        let timeSinceLastInteraction = Date().timeIntervalSince(lastUserInteractionDate)
        guard timeSinceLastInteraction <= maximumSecondsToValidateAfterLastInteraction else { return }

        // Respect the same debounce guards as the AX-triggered validation path
        let timeSinceLastValidation = Date().timeIntervalSince(lastAIValidationDate)
        guard !isAIValidationInProgress,
              timeSinceLastValidation >= minimumSecondsBetweenAIValidations else { return }

        isAIValidationInProgress = true
        lastAIValidationDate = Date()

        Task {
            await self.validateStepCompletionViaAIScreenshot(
                step: currentStep,
                steps: steps,
                currentIndex: currentIndex,
                generation: generationAtFireTime
            )
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
    /// After maximumTotalNudgesBeforeDisengaging nudges, disengages so the user isn't pestered.
    private func fireNudge(for step: WalkthroughStep, allSteps: [WalkthroughStep], generation: Int) {
        // Drop nudges from previous steps using the generation counter
        guard generation == currentStepGeneration,
              case .executing = state else { return }

        nudgeCount += 1

        // Disengage after too many nudges — nudge-count-based so it works correctly with
        // any timeoutSeconds value (time-based logic broke when timeoutSeconds dropped to 15).
        if nudgeCount > maximumTotalNudgesBeforeDisengaging {
            ttsClient.speak("Disengaging — call me back when you need help.")
            cancelWalkthrough()
            return
        }

        if nudgeCount >= maximumInstructionNudgesBeforeSwitchingToPatientMessage {
            ttsClient.speak("Take your time, I'm here when you're ready.")
        } else {
            ttsClient.speak("Still on step \(step.index + 1). \(step.instruction)")
        }

        // Re-point the cursor so the user can find the target element
        if !step.elementName.isEmpty {
            let nudgeBubbleText = "→ \(step.elementName)"
            activePointingTask?.cancel()
            activePointingTask = Task {
                await self.pointAtStepElement(
                    elementName: step.elementName,
                    appBundleID: step.appBundleID,
                    isMenuBar: step.isMenuBar,
                    bubbleText: nudgeBubbleText
                )
            }
        }

        // Reschedule — nudges keep firing until the step ends
        startNudgeTimer(for: step, allSteps: allSteps, generation: generation)
    }
}
