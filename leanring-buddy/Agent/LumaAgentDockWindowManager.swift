//
//  LumaAgentDockWindowManager.swift
//  leanring-buddy
//
//  One floating NSPanel per agent session. The coordinator diffs the session
//  list on each update, creates/destroys panels as sessions appear/disappear,
//  and drives a 25 Hz physics timer for idle drift and working shake.
//

import AppKit
import Combine
import SwiftUI

// MARK: - Layout Constants
// Shared between AgentBubbleWindow (hit rects, panel size) and MorphingAgentBubbleView (sizing).

private let kOrbCollapsedSize: CGFloat = 40        // Diameter of the collapsed orb
/// Icon font size inside the collapsed orb. Modify via UserDefaults key
/// "luma.agentBubble.iconSize" or change this constant directly.
private let kOrbIconSize: CGFloat = 10             // Icon pt size inside the orb
private let kCardExpandedWidth: CGFloat = 280      // Width of the expanded card
private let kCardExpandedHeight: CGFloat = 230     // Height with recommended follow-ups visible
private let kCardExpandedHeightCompact: CGFloat = 155  // Height without recommended follow-ups
private let kPanelWidth: CGFloat = 300             // Fixed NSPanel width
private let kPanelHeight: CGFloat = 250            // Fixed NSPanel height (fits tallest expanded state)
private let kOrbTrailingPadding: CGFloat = 12      // Right padding from panel edge to orb right edge

// MARK: - Physics Constants

private let kPhysicsTickInterval: Double = 1.0 / 25.0  // 25 Hz timer
/// Distance between orb centers (pixels) at which repulsion force begins.
/// Large enough to start pushing well before orbs can visually overlap.
private let kPhysicsRepulsionRadius: CGFloat = 160.0
/// Controls how hard bubbles push each other and bounce from edges.
/// Higher = more instant separation; lower = softer drifting.
private let kPhysicsRepulsionStrength: CGFloat = 2800.0
/// Hard minimum center-to-center gap. If two orbs are closer than this
/// (e.g., after spawning stacked), they are pushed apart every tick until clear.
/// Set to orb diameter + 6 pt breathing room so they never visually touch.
private let kMinBubbleSeparation: CGFloat = kOrbCollapsedSize + 6  // 46 pt
/// Screen-edge inset (pixels) that triggers edge repulsion.
private let kPhysicsEdgeMargin: CGFloat = 20.0
/// Per-tick velocity multiplier — simulates air resistance / friction.
/// Closer to 1.0 = less friction, bubbles travel further after a bounce.
private let kPhysicsVelocityDamping: CGFloat = 0.93
/// Hard velocity cap (pixels per tick) prevents runaway after dense stacking.
private let kPhysicsMaxSpeed: CGFloat = 22.0
/// Energy retained after a hard bounce off a screen edge (0–1).
/// 0.70 = 70% energy kept, so bubbles travel a good distance after bouncing.
private let kPhysicsBounceRestitution: CGFloat = 0.70
/// Seconds after mouse leaves an expanded card before it collapses.
/// Increase for a more forgiving interaction window.
private let kCollapseDelaySeconds: Double = 5

// MARK: - Screen-clamping helper (file-private so both AgentBubbleWindow and coordinator can use it)

private func clampWindowOriginToScreen(origin: NSPoint, windowSize: NSSize) -> NSPoint {
    guard let screen = NSScreen.main else { return origin }
    let visibleFrame = screen.visibleFrame
    let clampedX = max(visibleFrame.minX, min(origin.x, visibleFrame.maxX - windowSize.width))
    let clampedY = max(visibleFrame.minY, min(origin.y, visibleFrame.maxY - windowSize.height))
    return NSPoint(x: clampedX, y: clampedY)
}

// MARK: - AgentIconShape (unchanged — also used by AgentSession)

enum AgentIconShape: String, CaseIterable, Codable {
    case triangle, diamond, hexagon, star, circle, square

    var systemImageName: String {
        switch self {
        case .triangle: return "triangle.fill"
        case .diamond:  return "diamond.fill"
        case .hexagon:  return "hexagon.fill"
        case .star:     return "star.fill"
        case .circle:   return "circle.fill"
        case .square:   return "square.fill"
        }
    }

    static var random: AgentIconShape {
        allCases.randomElement() ?? .hexagon
    }
}

// MARK: - AgentBubblePhysicsState

/// Per-bubble observable state for physics animation, voice recording, and hover.
/// Updated at 25 Hz by the coordinator's physics timer.
@MainActor
final class AgentBubblePhysicsState: ObservableObject {
    /// Current pixel offset applied to the orb for physics effects.
    @Published var physicsOffset: CGSize = .zero
    /// Set by coordinator when the user is voice-recording into this agent.
    @Published var isVoiceRecording: Bool = false
    /// Set by coordinator based on exact mouse-vs-orb-rect hit testing (replaces SwiftUI
    /// onHover to prevent NSTrackingArea interference between adjacent bubble panels).
    @Published var isOrbHovered: Bool = false

    /// Phase offset (radians) randomized at init so all idle bubbles drift out of sync.
    let idlePhaseOffset: Double = Double.random(in: 0 ..< Double.pi * 2)
    /// Set by the coordinator based on distance to nearest running bubble (0–1).
    var proximityShakeFactor: Double = 0.0

    /// Called by the coordinator on each physics tick.
    func updatePhysics(sessionIsRunning: Bool, currentTime: TimeInterval) {
        if sessionIsRunning {
            // Violent shake: 12 pt in a random direction, updated at 25 Hz.
            let angle = Double.random(in: 0 ..< Double.pi * 2)
            let shakeRadius = 3.6
            physicsOffset = CGSize(
                width: shakeRadius * cos(angle),
                height: shakeRadius * sin(angle)
            )
        } else {
            // Idle: gentle vertical sine drift (5 pt amplitude, ~3 s period).
            let sinePhase = currentTime * (Double.pi * 2 / 3.0) + idlePhaseOffset
            let idleVerticalOffset = sin(sinePhase) * 5.0

            // Proximity shake: up to 35 % of working amplitude, all directions.
            var proximityDx = 0.0
            var proximityDy = 0.0
            if proximityShakeFactor > 0 {
                let angle = Double.random(in: 0 ..< Double.pi * 2)
                let proximityRadius = proximityShakeFactor * 12.0 * 0.35
                proximityDx = proximityRadius * cos(angle)
                proximityDy = proximityRadius * sin(angle)
            }

            physicsOffset = CGSize(
                width: proximityDx,
                height: idleVerticalOffset + proximityDy
            )
        }
    }
}

// MARK: - KeyAcceptingPanel

/// NSPanel subclass that accepts key focus so embedded SwiftUI TextFields work.
private final class KeyAcceptingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// NSHostingView subclass that accepts the very first mouse click even when
/// the app is not the key application. Without this override, the first tap
/// on the bubble is silently consumed as a "bring window forward" event and
/// never reaches the SwiftUI gesture recognizer.
private final class FirstMouseHostingView<T: View>: NSHostingView<T> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - AgentBubbleWindow

/// Wraps a single floating NSPanel for one agent session.
/// Owns drag handling (with screen clamping) and the AgentBubblePhysicsState
/// used by the SwiftUI view inside. Panel size is fixed — no resize on hover.
@MainActor
final class AgentBubbleWindow {
    let sessionID: UUID
    private(set) var physicsState: AgentBubblePhysicsState

    private let panel: NSPanel
    /// Weak reference — AgentSession lifetime is managed by CompanionManager.
    private weak var session: AgentSession?

    private var dragStartMouseScreenLocation: NSPoint = .zero
    private var dragStartWindowOrigin: NSPoint = .zero
    private var isDragging = false

    /// Current physics velocity in screen-coordinate pixels per tick.
    /// Zeroed when the user starts dragging so drag and physics don't fight.
    fileprivate var physicsVelocity: CGPoint = .zero
    /// True while the user is actively dragging. Physics position updates are
    /// suspended during drag so the panel doesn't fight the user's cursor.
    fileprivate private(set) var isBeingDragged: Bool = false

    private var positionUserDefaultsKey: String {
        "luma.agentBubble.\(sessionID.uuidString).origin"
    }

    /// The screen-space center of the orb in this bubble's panel.
    var screenCenter: NSPoint {
        let orbCenterX = panel.frame.maxX - kOrbTrailingPadding - kOrbCollapsedSize / 2
        return NSPoint(x: orbCenterX, y: panel.frame.midY)
    }

    /// Hit rect for the collapsed orb, in screen coordinates.
    /// Used by the physics timer to drive hover-to-expand without SwiftUI onHover.
    var orbHitRect: NSRect {
        let halfOrb = kOrbCollapsedSize / 2
        let centerX = panel.frame.maxX - kOrbTrailingPadding - halfOrb
        let centerY = panel.frame.midY
        return NSRect(x: centerX - halfOrb, y: centerY - halfOrb,
                      width: kOrbCollapsedSize, height: kOrbCollapsedSize)
    }

    /// Hit rect for the expanded card, in screen coordinates.
    /// Height matches the card's actual rendered height (compact when no follow-ups, full otherwise).
    var expandedCardHitRect: NSRect {
        let hasSuggestions = !(session?.latestResponseCard?.suggestedActions ?? []).isEmpty
        let activeCardHeight = hasSuggestions ? kCardExpandedHeight : kCardExpandedHeightCompact
        let cardRight = panel.frame.maxX - kOrbTrailingPadding
        let cardLeft = cardRight - kCardExpandedWidth
        let halfCardHeight = activeCardHeight / 2
        let centerY = panel.frame.midY
        return NSRect(x: cardLeft, y: centerY - halfCardHeight,
                      width: kCardExpandedWidth, height: activeCardHeight)
    }

    /// Whether the session attached to this window is actively running.
    var sessionIsRunning: Bool {
        guard let session else { return false }
        return session.status == .running || session.status == .starting
    }

    init(
        session: AgentSession,
        initialOrigin: NSPoint,
        onDismiss: @escaping () -> Void,
        onRunSuggestedAction: @escaping (String) -> Void,
        onSubmitText: @escaping (String) -> Void,
        onVoiceFollowUp: @escaping () -> Void,
        onVoiceToggle: @escaping () -> Void
    ) {
        self.sessionID = session.id
        self.session = session
        self.physicsState = AgentBubblePhysicsState()

        // Panel is fixed — the morphing view expands from kOrbCollapsedSize orb
        // to kCardExpandedWidth × kCardExpandedHeight card within this fixed rect.
        let panel = KeyAcceptingPanel(
            contentRect: NSRect(x: 0, y: 0, width: kPanelWidth, height: kPanelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.panel = panel

        let bubbleView = AgentBubbleRootView(
            session: session,
            physicsState: physicsState,
            onDragStarted: { [weak self] in self?.handleDragStarted() },
            onDragUpdated: { [weak self] in self?.handleDragUpdated() },
            onDragEnded:   { [weak self] in self?.handleDragEnded() },
            onDismiss: onDismiss,
            onRunSuggestedAction: onRunSuggestedAction,
            onSubmitText: onSubmitText,
            onVoiceFollowUp: onVoiceFollowUp,
            onVoiceToggle: onVoiceToggle,
            onBringToFront: { [weak self] in self?.panel.orderFrontRegardless() }
        )
        panel.contentView = FirstMouseHostingView(rootView: bubbleView)

        let clampedOrigin = clampWindowOriginToScreen(origin: initialOrigin, windowSize: panel.frame.size)
        panel.setFrameOrigin(clampedOrigin)
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel.close()
    }

    /// Restores the last-saved drag position from UserDefaults, if one exists.
    func restorePersistedPosition() {
        guard let values = UserDefaults.standard.array(forKey: positionUserDefaultsKey) as? [Double],
              values.count == 2 else { return }
        let savedOrigin = NSPoint(x: values[0], y: values[1])
        let clampedOrigin = clampWindowOriginToScreen(origin: savedOrigin, windowSize: panel.frame.size)
        panel.setFrameOrigin(clampedOrigin)
    }

    // MARK: Drag callbacks (invoked by SwiftUI DragGesture in AgentBubbleRootView)

    private func handleDragStarted() {
        dragStartMouseScreenLocation = NSEvent.mouseLocation
        dragStartWindowOrigin = panel.frame.origin
        isDragging = true
        isBeingDragged = true
        physicsVelocity = .zero   // cancel any physics momentum so drag is smooth
    }

    private func handleDragUpdated() {
        let currentMouse = NSEvent.mouseLocation
        let deltaX = currentMouse.x - dragStartMouseScreenLocation.x
        let deltaY = currentMouse.y - dragStartMouseScreenLocation.y
        let proposedOrigin = NSPoint(
            x: dragStartWindowOrigin.x + deltaX,
            y: dragStartWindowOrigin.y + deltaY
        )
        let clampedOrigin = clampWindowOriginToScreen(origin: proposedOrigin, windowSize: panel.frame.size)
        panel.setFrameOrigin(clampedOrigin)
    }

    private func handleDragEnded() {
        isDragging = false
        isBeingDragged = false
        let origin = panel.frame.origin
        UserDefaults.standard.set([origin.x, origin.y], forKey: positionUserDefaultsKey)
    }

    // MARK: Physics position (called by coordinator physics tick, not user drag)

    /// Current screen-space origin of the NSPanel (bottom-left corner in macOS coords).
    fileprivate var currentPanelOrigin: NSPoint { panel.frame.origin }

    /// Moves the panel to `proposedOrigin`, clamped to screen bounds.
    /// Returns whether clamping occurred on each axis — used by the coordinator
    /// to reflect the velocity component (hard edge bounce).
    /// Does NOT persist to UserDefaults (drag saves position; physics doesn't).
    @discardableResult
    fileprivate func applyPhysicsOrigin(_ proposedOrigin: NSPoint) -> (bouncedX: Bool, bouncedY: Bool) {
        let clampedOrigin = clampWindowOriginToScreen(origin: proposedOrigin, windowSize: panel.frame.size)
        panel.setFrameOrigin(clampedOrigin)
        let bouncedX = abs(clampedOrigin.x - proposedOrigin.x) > 0.5
        let bouncedY = abs(clampedOrigin.y - proposedOrigin.y) > 0.5
        return (bouncedX: bouncedX, bouncedY: bouncedY)
    }
}

// MARK: - Coordinator

@MainActor
final class LumaAgentDockWindowManager {
    private var bubbleWindows: [UUID: AgentBubbleWindow] = [:]
    private var physicsTimer: Timer?
    /// Tracks when the mouse left each expanded bubble. After kCollapseDelaySeconds
    /// the card collapses. Cleared immediately when the mouse re-enters.
    private var collapseTimestamps: [UUID: Date] = [:]

    /// Global NSEvent monitor that collapses any open expanded card when the
    /// user clicks outside all expanded-card rects. Installed while the dock
    /// is visible and removed when it is hidden.
    private var tapOutsideExpandedCardMonitor: Any?

    // Callbacks stored so syncSessions can wire new windows after first show()
    private var onDismissAgent: ((UUID) -> Void)?
    private var onRunSuggestedAction: ((UUID, String) -> Void)?
    private var onVoiceFollowUp: ((UUID) -> Void)?
    private var onSubmitTextFromDock: ((UUID, String) -> Void)?
    private var onVoiceToggle: ((UUID) -> Void)?

    func show(
        sessions: [AgentSession],
        onDismissAgent: @escaping (UUID) -> Void,
        onRunSuggestedAction: @escaping (UUID, String) -> Void,
        onVoiceFollowUp: @escaping (UUID) -> Void,
        onSubmitTextFromDock: @escaping (UUID, String) -> Void,
        onVoiceToggle: @escaping (UUID) -> Void
    ) {
        self.onDismissAgent = onDismissAgent
        self.onRunSuggestedAction = onRunSuggestedAction
        self.onVoiceFollowUp = onVoiceFollowUp
        self.onSubmitTextFromDock = onSubmitTextFromDock
        self.onVoiceToggle = onVoiceToggle

        syncSessions(sessions)
        startPhysicsTimerIfNeeded()
        installTapOutsideMonitorIfNeeded()
    }

    func hide() {
        for (_, window) in bubbleWindows { window.close() }
        bubbleWindows.removeAll()
        stopPhysicsTimer()
        removeTapOutsideMonitor()
    }

    func setVoiceRecordingAgent(_ agentID: UUID?) {
        for (id, window) in bubbleWindows {
            window.physicsState.isVoiceRecording = (agentID == id)
        }
    }

    /// Kept for API compatibility with CompanionManager persistence code (no-op).
    var dragPositions: [UUID: CGSize] { [:] }

    /// Kept for API compatibility with CompanionManager persistence code (no-op).
    func restoreDragPositions(_ positions: [UUID: CGSize]) {}

    // MARK: Session sync

    private func syncSessions(_ sessions: [AgentSession]) {
        let incomingSessionIDs = Set(sessions.map { $0.id })

        // Close windows for sessions that are gone
        for id in bubbleWindows.keys where !incomingSessionIDs.contains(id) {
            bubbleWindows[id]?.close()
            bubbleWindows.removeValue(forKey: id)
            collapseTimestamps.removeValue(forKey: id)
        }

        // Open windows for sessions that are new
        for session in sessions where bubbleWindows[session.id] == nil {
            guard let onDismissAgent, let onRunSuggestedAction,
                  let onVoiceFollowUp, let onSubmitTextFromDock, let onVoiceToggle else { continue }

            let initialOrigin = defaultSpawnOriginForNewBubble(existingCount: bubbleWindows.count)
            let window = AgentBubbleWindow(
                session: session,
                initialOrigin: initialOrigin,
                onDismiss: {
                    onDismissAgent(session.id)
                },
                onRunSuggestedAction: { action in
                    onRunSuggestedAction(session.id, action)
                },
                onSubmitText: { text in
                    onSubmitTextFromDock(session.id, text)
                },
                onVoiceFollowUp: {
                    onVoiceFollowUp(session.id)
                },
                onVoiceToggle: {
                    onVoiceToggle(session.id)
                }
            )
            window.restorePersistedPosition()
            bubbleWindows[session.id] = window
        }
    }

    /// Computes a default spawn origin staggered from the top-right corner.
    /// The panel right edge is flush with the screen's right edge. The first orb
    /// spawns just below the menu-bar area; each subsequent orb stacks 10 pt below.
    private func defaultSpawnOriginForNewBubble(existingCount: Int) -> NSPoint {
        guard let screen = NSScreen.main else { return .zero }
        let visibleFrame = screen.visibleFrame
        let originX = visibleFrame.maxX - kPanelWidth
        // Position orb center exactly at the physics repulsion boundary so it
        // doesn't drift downward on spawn. orbCenter.y must equal orbEdgeMaxY,
        // i.e. visibleFrame.maxY - halfOrb - kPhysicsEdgeMargin, minus one full
        // repulsion radius so topGap == kPhysicsRepulsionRadius at rest.
        // orbCenter = panelOrigin.y + kPanelHeight/2, so:
        //   panelOrigin.y = orbCenter - kPanelHeight/2
        let topEdgeY = visibleFrame.maxY - kPanelHeight / 2 - (kPhysicsEdgeMargin + kOrbCollapsedSize / 2 + kPhysicsRepulsionRadius)
        let stackedY = topEdgeY - CGFloat(existingCount) * (kOrbCollapsedSize + 10)
        return NSPoint(x: originX, y: stackedY)
    }

    // MARK: Physics timer

    private func startPhysicsTimerIfNeeded() {
        guard physicsTimer == nil else { return }
        physicsTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 25.0, repeats: true) { [weak self] _ in
            self?.tickPhysics()
        }
    }

    private func stopPhysicsTimer() {
        physicsTimer?.invalidate()
        physicsTimer = nil
    }

    // MARK: Tap-outside-to-collapse monitor

    private func installTapOutsideMonitorIfNeeded() {
        guard tapOutsideExpandedCardMonitor == nil else { return }

        tapOutsideExpandedCardMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.collapseExpandedCardsIfClickedOutside(clickLocation: NSEvent.mouseLocation)
            }
        }
    }

    private func removeTapOutsideMonitor() {
        if let monitor = tapOutsideExpandedCardMonitor {
            NSEvent.removeMonitor(monitor)
            tapOutsideExpandedCardMonitor = nil
        }
    }

    /// Collapses any expanded bubble whose card rect does not contain the click point.
    private func collapseExpandedCardsIfClickedOutside(clickLocation: NSPoint) {
        for (_, window) in bubbleWindows {
            guard window.physicsState.isOrbHovered else { continue }
            let isInsideExpandedCard = window.expandedCardHitRect.contains(clickLocation)
            let isInsideOrb = window.orbHitRect.contains(clickLocation)
            if !isInsideExpandedCard && !isInsideOrb {
                window.physicsState.isOrbHovered = false
                collapseTimestamps.removeValue(forKey: window.sessionID)
            }
        }
    }

    private func tickPhysics() {
        let currentTime = Date.timeIntervalSinceReferenceDate
        let mouseLocation = NSEvent.mouseLocation

        // ── Auto-collapse when mouse leaves an expanded card ───────────────────────
        // ── Delayed auto-collapse when mouse leaves an expanded card ────────────────
        // Expand is triggered by tap (TapGesture in MorphingAgentBubbleView).
        // When mouse leaves both the orb rect and the card rect, record the
        // departure time. After kCollapseDelaySeconds the card collapses.
        // Returning the mouse before the delay fires cancels the countdown.
        let now = Date()
        for (sessionID, window) in bubbleWindows {
            guard window.physicsState.isOrbHovered else {
                // Not expanded — no countdown needed.
                collapseTimestamps.removeValue(forKey: sessionID)
                continue
            }
            let mouseOverCard = window.expandedCardHitRect.contains(mouseLocation)
            let mouseOverOrb  = window.orbHitRect.contains(mouseLocation)
            if mouseOverCard || mouseOverOrb {
                // Mouse is over the bubble — reset any pending collapse countdown.
                collapseTimestamps.removeValue(forKey: sessionID)
            } else {
                // Mouse has left — start the countdown if not already running.
                if collapseTimestamps[sessionID] == nil {
                    collapseTimestamps[sessionID] = now
                } else if let departureTime = collapseTimestamps[sessionID],
                          now.timeIntervalSince(departureTime) >= kCollapseDelaySeconds {
                    // Delay elapsed — collapse the card.
                    window.physicsState.isOrbHovered = false
                    collapseTimestamps.removeValue(forKey: sessionID)
                }
            }
        }

        // ── Position physics: repulsion + edge bounce (Euler integration) ──────────
        guard let screen = NSScreen.main else { return }
        let visibleFrame = screen.visibleFrame
        let halfOrb = kOrbCollapsedSize / 2
        // Soft-boundary: orb center must stay this far from each screen edge.
        let orbEdgeMinX = visibleFrame.minX + halfOrb + kPhysicsEdgeMargin
        let orbEdgeMaxX = visibleFrame.maxX - halfOrb - kPhysicsEdgeMargin
        let orbEdgeMinY = visibleFrame.minY + halfOrb + kPhysicsEdgeMargin
        let orbEdgeMaxY = visibleFrame.maxY - halfOrb - kPhysicsEdgeMargin

        let allWindows = Array(bubbleWindows.values)

        for window in allWindows {
            // Skip position physics while the user is dragging or the card is open.
            // When expanded the card is interactive — moving it would be disorienting.
            guard !window.isBeingDragged && !window.physicsState.isOrbHovered else {
                window.physicsVelocity = .zero
                continue
            }

            let center = window.screenCenter
            var forceX: CGFloat = 0
            var forceY: CGFloat = 0

            // ── Bubble-to-bubble repulsion ───────────────────────────────────────
            for other in allWindows {
                guard other.sessionID != window.sessionID else { continue }
                let dx = center.x - other.screenCenter.x
                let dy = center.y - other.screenCenter.y
                let distSquared = dx * dx + dy * dy
                let dist = sqrt(distSquared)
                guard dist > 0 && dist < kPhysicsRepulsionRadius else { continue }
                // Force magnitude grows as bubbles get closer (inverse-square law capped).
                let forceMagnitude = kPhysicsRepulsionStrength / max(distSquared, 1)
                forceX += forceMagnitude * (dx / dist)
                forceY += forceMagnitude * (dy / dist)
            }

            // ── Edge repulsion — pushes orbs away from screen boundaries ────────
            // Using the same inverse-square model so the bounce feels natural.
            let leftGap   = center.x - orbEdgeMinX
            let rightGap  = orbEdgeMaxX - center.x
            let bottomGap = center.y - orbEdgeMinY
            let topGap    = orbEdgeMaxY - center.y

            if leftGap < kPhysicsRepulsionRadius && leftGap > 0 {
                forceX += kPhysicsRepulsionStrength / max(leftGap * leftGap, 1)
            }
            if rightGap < kPhysicsRepulsionRadius && rightGap > 0 {
                forceX -= kPhysicsRepulsionStrength / max(rightGap * rightGap, 1)
            }
            if bottomGap < kPhysicsRepulsionRadius && bottomGap > 0 {
                forceY += kPhysicsRepulsionStrength / max(bottomGap * bottomGap, 1)
            }
            if topGap < kPhysicsRepulsionRadius && topGap > 0 {
                forceY -= kPhysicsRepulsionStrength / max(topGap * topGap, 1)
            }

            // ── Euler integration: F → Δvelocity → Δposition ────────────────────
            var velocity = window.physicsVelocity
            velocity.x = velocity.x * kPhysicsVelocityDamping + forceX * CGFloat(kPhysicsTickInterval)
            velocity.y = velocity.y * kPhysicsVelocityDamping + forceY * CGFloat(kPhysicsTickInterval)

            // Clamp speed so stacked bubbles don't explode on first tick.
            let speed = hypot(velocity.x, velocity.y)
            if speed > kPhysicsMaxSpeed {
                let scale = kPhysicsMaxSpeed / speed
                velocity.x *= scale
                velocity.y *= scale
            }
            window.physicsVelocity = velocity

            // Move panel if velocity is non-trivial.
            if speed > 0.05 {
                let proposedOrigin = NSPoint(
                    x: window.currentPanelOrigin.x + velocity.x,
                    y: window.currentPanelOrigin.y + velocity.y
                )
                let bounce = window.applyPhysicsOrigin(proposedOrigin)
                // Reflect the velocity component that hit a hard screen edge,
                // with 40% energy loss so it settles rather than bouncing forever.
                if bounce.bouncedX { window.physicsVelocity.x *= -kPhysicsBounceRestitution }
                if bounce.bouncedY { window.physicsVelocity.y *= -kPhysicsBounceRestitution }
            }
        }

        // ── Hard contact separation (position correction) ───────────────────────
        // After the force pass, enforce a minimum center-to-center distance so
        // orbs never visually touch regardless of how fast they were moving.
        // Process each unique pair once (upper-triangle iteration).
        for i in 0..<allWindows.count {
            for j in (i + 1)..<allWindows.count {
                let windowA = allWindows[i]
                let windowB = allWindows[j]
                let dx = windowA.screenCenter.x - windowB.screenCenter.x
                let dy = windowA.screenCenter.y - windowB.screenCenter.y
                let dist = hypot(dx, dy)
                guard dist < kMinBubbleSeparation && dist > 0 else { continue }

                // Compute how much each orb must move to restore the minimum gap.
                let overlap = kMinBubbleSeparation - dist
                let normX = dx / dist
                let normY = dy / dist
                let halfOverlap = overlap / 2

                // Push both apart equally — only non-dragging, non-expanded orbs move.
                let aCanMove = !windowA.isBeingDragged && !windowA.physicsState.isOrbHovered
                let bCanMove = !windowB.isBeingDragged && !windowB.physicsState.isOrbHovered
                let share: CGFloat = (aCanMove && bCanMove) ? halfOverlap : overlap

                if aCanMove {
                    windowA.applyPhysicsOrigin(NSPoint(
                        x: windowA.currentPanelOrigin.x + normX * share,
                        y: windowA.currentPanelOrigin.y + normY * share
                    ))
                }
                if bCanMove {
                    windowB.applyPhysicsOrigin(NSPoint(
                        x: windowB.currentPanelOrigin.x - normX * share,
                        y: windowB.currentPanelOrigin.y - normY * share
                    ))
                }

                // Cancel any velocity component that would push the orbs back together.
                let relVelAlongNormal = (windowA.physicsVelocity.x - windowB.physicsVelocity.x) * normX
                                      + (windowA.physicsVelocity.y - windowB.physicsVelocity.y) * normY
                if relVelAlongNormal < 0 {  // approaching each other
                    if aCanMove {
                        windowA.physicsVelocity.x -= relVelAlongNormal * normX * 0.5
                        windowA.physicsVelocity.y -= relVelAlongNormal * normY * 0.5
                    }
                    if bCanMove {
                        windowB.physicsVelocity.x += relVelAlongNormal * normX * 0.5
                        windowB.physicsVelocity.y += relVelAlongNormal * normY * 0.5
                    }
                }
            }
        }

        // ── Visual shake (physicsOffset) + proximity factor ─────────────────────
        let runningBubbleCenters: [NSPoint] = bubbleWindows.values
            .filter { $0.sessionIsRunning }
            .map { $0.screenCenter }

        for (_, window) in bubbleWindows {
            if !window.sessionIsRunning && !runningBubbleCenters.isEmpty {
                let center = window.screenCenter
                let minimumDistanceToRunningBubble = runningBubbleCenters
                    .map { hypot(center.x - $0.x, center.y - $0.y) }
                    .min() ?? .infinity
                let proximityRadius: Double = 100
                window.physicsState.proximityShakeFactor = minimumDistanceToRunningBubble < proximityRadius
                    ? max(0.0, 1.0 - minimumDistanceToRunningBubble / proximityRadius)
                    : 0.0
            } else {
                window.physicsState.proximityShakeFactor = 0.0
            }

            window.physicsState.updatePhysics(
                sessionIsRunning: window.sessionIsRunning,
                currentTime: currentTime
            )
        }
    }
}

// MARK: - OrbAccentStatusDot

/// Single status-aware accent dot that floats at the top-right of the collapsed orb.
/// Idle/stopped → grey, working/starting → pulsing orange, ready → green, failed → red.
/// Fades to transparent as the orb morphs into the card.
private struct OrbAccentStatusDot: View {
    let status: AgentSessionStatus
    let isHovered: Bool
    @State private var isPulsingLarge = false

    private var dotColor: Color {
        switch status {
        case .stopped:            return Color.gray.opacity(0.55)
        case .ready:              return Color(red: 0.35, green: 0.78, blue: 0.45)
        case .starting, .running: return Color(red: 1.0, green: 0.62, blue: 0.22)
        case .failed:             return Color(red: 1.0, green: 0.30, blue: 0.30)
        }
    }

    private var isPulsing: Bool { status == .running || status == .starting }

    var body: some View {
        Circle()
            .fill(dotColor)
            .frame(width: 11, height: 11)
            .overlay(Circle().stroke(Color.white.opacity(0.22), lineWidth: 1))
            .shadow(color: dotColor.opacity(0.80), radius: 5)
            // Subtle pulse: scale only varies by ~12% so the dot doesn't jump
            .scaleEffect(isPulsing && isPulsingLarge ? 0.88 : 1.0)
            .opacity(isHovered ? 0.0 : (isPulsing && isPulsingLarge ? 0.65 : 1.0))
            .animation(
                isPulsing ? .easeInOut(duration: 0.85).repeatForever(autoreverses: true) : .default,
                value: isPulsingLarge
            )
            .animation(.easeOut(duration: 0.15), value: isHovered)
            .onAppear { isPulsingLarge = isPulsing }
            .onChange(of: isPulsing) { active in isPulsingLarge = active }
    }
}

// MARK: - MorphingAgentBubbleView

/// A single SwiftUI view that IS both the orb and the card.
///
/// Collapsed state (isExpanded = false):
///   • kOrbCollapsedSize circle, corner radius = half (full circle)
///   • Rich radial gradient with dark rim vignette for glassy depth
///   • Agent icon colored in session.glowColor, centered, with accent inset glow
///   • Tap gesture expands to card; physics timer collapses when mouse leaves
///   • Physics shake offset applied
///
/// Expanded state (isExpanded = true):
///   • kCardExpandedWidth × kCardExpandedHeight rounded rect, corner radius = 20
///   • Dark card: response text, recommended follow-ups, text field, voice button
///   • Drag from header strip to reposition; outer drag disabled
///
/// All opacity layers read `isExpanded` directly — no async delays — so orb and
/// card crossfade simultaneously in the same spring context with no transparent gap.
private struct MorphingAgentBubbleView: View {
    @ObservedObject var session: AgentSession
    @ObservedObject var physicsState: AgentBubblePhysicsState

    /// True when this bubble is in its expanded card state.
    let isExpanded: Bool
    let onDragStarted: () -> Void
    let onDragUpdated: () -> Void
    let onDragEnded: () -> Void
    let onDismiss: () -> Void
    let onRunSuggestedAction: (String) -> Void
    let onSubmitText: (String) -> Void
    let onVoiceToggle: () -> Void

    @State private var isDragActive = false
    @State private var followUpInputText: String = ""

    private var currentWidth: CGFloat { isExpanded ? kCardExpandedWidth : kOrbCollapsedSize }
    /// Card height shrinks when there are no recommended follow-ups to display,
    /// eliminating dead space at the bottom of the expanded state.
    private var currentExpandedHeight: CGFloat {
        let hasSuggestions = !(session.latestResponseCard?.suggestedActions ?? []).isEmpty
        return hasSuggestions ? kCardExpandedHeight : kCardExpandedHeightCompact
    }
    private var currentHeight: CGFloat { isExpanded ? currentExpandedHeight : kOrbCollapsedSize }
    private var currentCornerRadius: CGFloat { isExpanded ? 20 : kOrbCollapsedSize / 2 }

    var body: some View {
        ZStack {
            // ── Card background (expanded state) ─────────────────────────────
            // Fades in as the orb gradient fades out. Both layers always present
            // so their combined opacity is always 1 — no transparent gap.
            Color(red: 0.04, green: 0.03, blue: 0.09)
                .opacity(isExpanded ? 1 : 0)

            // ── Orb gradient background (collapsed state) ─────────────────────
            // Vibrant radial gradient, light source upper-left.
            RadialGradient(
                gradient: Gradient(stops: [
                    .init(color: session.glowColor.opacity(0.95), location: 0.0),
                    .init(color: session.glowColor.opacity(0.75), location: 0.48),
                    .init(color: Color(red: 0.05, green: 0.02, blue: 0.12), location: 1.0),
                ]),
                center: UnitPoint(x: 0.30, y: 0.26),
                startRadius: 2,
                endRadius: kOrbCollapsedSize * 0.55
            )
            .opacity(isExpanded ? 0 : 1)

            // ── Inner shadow / dark rim ──────────────────────────────────────
            // Dark vignette at orb edge creates glassy bowl depth.
            RadialGradient(
                gradient: Gradient(stops: [
                    .init(color: Color.clear, location: 0.44),
                    .init(color: Color.black.opacity(0.55), location: 1.0)
                ]),
                center: .center,
                startRadius: 0,
                endRadius: kOrbCollapsedSize * 0.46
            )
            .opacity(isExpanded ? 0 : 1)

            // ── Specular highlights (orb state only) ──────────────────────────
            // Offsets are scaled for kOrbCollapsedSize = 40pt (radius 20).
            Ellipse()
                .fill(Color.white.opacity(0.28))
                .frame(width: 13, height: 6)
                .rotationEffect(.degrees(-22))
                .offset(x: -6, y: -9)
                .blur(radius: 1)
                .blendMode(.screen)
                .opacity(isExpanded ? 0 : 1)

            Ellipse()
                .fill(Color.white.opacity(0.72))
                .frame(width: 4, height: 2.5)
                .offset(x: -7, y: -11)
                .blendMode(.screen)
                .opacity(isExpanded ? 0 : 1)

            // ── Agent icon (collapsed state) ─────────────────────────────────
            // kOrbIconSize controls the pt size — adjust via the constant or
            // UserDefaults key "luma.agentBubble.iconSize".
            // The icon is colored in the session accent color, then shadowed with:
            //   • accent-color glow (simulates backlit inset illumination)
            //   • sharp black drop shadow (inset depth)
            Image(systemName: session.iconShape.systemImageName)
                .font(.system(size: kOrbIconSize, weight: .heavy))
                .foregroundColor(session.glowColor)
                .shadow(color: session.glowColor.opacity(0.95), radius: 5)
                .shadow(color: Color.black.opacity(0.75), radius: 2, x: 0, y: 1)
                .shadow(color: Color.black.opacity(0.40), radius: 4, x: 0, y: 2)
                // frame centers the icon in the orb — alignment defaults to .center
                .frame(width: kOrbCollapsedSize, height: kOrbCollapsedSize, alignment: .center)
                .opacity(isExpanded ? 0 : 1)

            // ── Card content (expanded state) ─────────────────────────────────
            cardContentView
                .opacity(isExpanded ? 1 : 0)
        }
        .frame(width: currentWidth, height: currentHeight)
        .clipShape(RoundedRectangle(cornerRadius: currentCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: currentCornerRadius, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(isExpanded ? 0.09 : 0.38),
                            Color.white.opacity(0.04)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        )
        .shadow(color: session.glowColor.opacity(isExpanded ? 0.20 : 0.50), radius: isExpanded ? 10 : 22)
        .shadow(color: Color.black.opacity(0.50), radius: 12, y: 5)
        // Physics offset only applies when collapsed — expanded card stays stable
        .offset(
            x: isExpanded ? 0 : physicsState.physicsOffset.width,
            y: isExpanded ? 0 : physicsState.physicsOffset.height
        )
        .animation(.linear(duration: 0.04), value: physicsState.physicsOffset)
        // Collapsed-state drag — disabled when expanded to prevent conflicts
        // with the card header's own drag gesture
        .gesture(
            DragGesture(minimumDistance: 4, coordinateSpace: .global)
                .onChanged { _ in
                    guard !isExpanded else { return }
                    if !isDragActive { isDragActive = true; onDragStarted() }
                    onDragUpdated()
                }
                .onEnded { _ in isDragActive = false; onDragEnded() }
        )
    }

    // MARK: - Card content

    private var cardContentView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header strip — also serves as the drag handle in expanded state
            cardHeader
            Rectangle()
                .fill(session.glowColor.opacity(0.22))
                .frame(height: 1)
            cardBody
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var cardHeader: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusAccentColor)
                .frame(width: 7, height: 7)
                .shadow(color: statusAccentColor.opacity(0.8), radius: 3)

            Text(session.title.uppercased())
                .font(.system(size: 11, weight: .heavy))
                .foregroundColor(session.glowColor.opacity(0.9))
                .kerning(0.77)
                .lineLimit(1)

            Spacer()

            statusChipView

            Button(action: onDismiss) {
                Text("✕")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.white.opacity(0.85))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.top, 13)
        .padding(.bottom, 9)
        .background(Color.white.opacity(0.03))
        // Drag the entire expanded card by grabbing this header strip
        .gesture(
            DragGesture(minimumDistance: 4, coordinateSpace: .global)
                .onChanged { _ in
                    if !isDragActive { isDragActive = true; onDragStarted() }
                    onDragUpdated()
                }
                .onEnded { _ in isDragActive = false; onDragEnded() }
        )
    }

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: 7) {
            // Latest assistant response text
            Text(session.latestActivitySummary ?? "Waiting for response...")
                .font(.system(size: 11))
                .foregroundColor(
                    Color.white.opacity(session.latestActivitySummary != nil ? 0.65 : 0.28)
                )
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .italic(session.latestActivitySummary == nil)

            // ── Recommended follow-up actions (from <NEXT_ACTIONS> tags) ──────
            // Shown when the AI returns suggested follow-ups after task completion.
            let suggestedActions = session.latestResponseCard?.suggestedActions ?? []
            if !suggestedActions.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("RECOMMENDED")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundColor(Color.white.opacity(0.30))
                        .kerning(0.5)

                    ForEach(suggestedActions.prefix(2), id: \.self) { actionText in
                        Button(action: { onRunSuggestedAction(actionText) }) {
                            Text(actionText)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(session.glowColor.opacity(0.92))
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                        }
                        .buttonStyle(.plain)
                        .background(session.glowColor.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(session.glowColor.opacity(0.18), lineWidth: 1)
                        )
                    }
                }
            }

            // ── Follow-up text input row ──────────────────────────────────────
            HStack(spacing: 6) {
                TextField("Ask a follow-up...", text: $followUpInputText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundColor(Color.white.opacity(0.80))
                    .onSubmit { submitFollowUp() }

                Button(action: submitFollowUp) {
                    Text("↑")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 20, height: 20)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(session.glowColor.opacity(
                                    followUpInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                        ? 0.25 : 0.70
                                ))
                        )
                }
                .buttonStyle(.plain)
                .disabled(followUpInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Color.white.opacity(0.07), lineWidth: 1)
            )

            // ── Voice button — compact, right-aligned, below the text field ───
            // Idle: small mic-only pill on the right.
            // Recording: expands leftward with "Listening..." label + red styling.
            HStack {
                Spacer()
                Button(action: onVoiceToggle) {
                    HStack(spacing: 5) {
                        Image(systemName: physicsState.isVoiceRecording ? "mic.fill" : "mic")
                            .font(.system(size: 10, weight: .bold))
                        if physicsState.isVoiceRecording {
                            Text("Listening...")
                                .font(.system(size: 10, weight: .semibold))
                        }
                    }
                    .foregroundColor(physicsState.isVoiceRecording ? .white : Color.white.opacity(0.50))
                    .padding(.horizontal, physicsState.isVoiceRecording ? 10 : 7)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(physicsState.isVoiceRecording
                                  ? Color.red.opacity(0.35)
                                  : Color.white.opacity(0.05))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(physicsState.isVoiceRecording
                                    ? Color.red.opacity(0.55)
                                    : Color.white.opacity(0.07), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    private func submitFollowUp() {
        let trimmedText = followUpInputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        onSubmitText(trimmedText)
        followUpInputText = ""
    }

    // MARK: Status helpers

    private var statusAccentColor: Color {
        switch session.status {
        case .stopped:            return Color.gray.opacity(0.50)
        case .ready:              return Color(red: 0.35, green: 0.78, blue: 0.45)
        case .starting, .running: return Color(red: 1.0, green: 0.62, blue: 0.22)
        case .failed:             return Color(red: 1.0, green: 0.30, blue: 0.30)
        }
    }

    private var statusChipColor: Color {
        switch session.status {
        case .running, .starting: return Color.orange
        case .ready:              return Color.green
        case .failed:             return Color.red
        case .stopped:            return Color.white.opacity(0.40)
        }
    }

    private var statusChipView: some View {
        Text(session.status.displayLabel)
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(statusChipColor)
            .textCase(.uppercase)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(statusChipColor.opacity(0.12)))
            .overlay(Capsule().stroke(statusChipColor.opacity(0.22), lineWidth: 1))
            .clipShape(Capsule())
    }
}

// MARK: - AgentBubbleRootView

/// Root SwiftUI view hosted in each AgentBubbleWindow panel (kPanelWidth × kPanelHeight fixed).
/// A clear passthrough background fills the panel; the morphing orb/card sits at the trailing
/// edge with an accent status dot overlaid at its top-right corner.
///
/// Hover-to-expand is driven by the coordinator's 25 Hz physics timer via
/// physicsState.isOrbHovered — not SwiftUI onHover — to prevent NSTrackingArea
/// interference between adjacent bubble panels.
private struct AgentBubbleRootView: View {
    @ObservedObject var session: AgentSession
    @ObservedObject var physicsState: AgentBubblePhysicsState

    let onDragStarted: () -> Void
    let onDragUpdated: () -> Void
    let onDragEnded: () -> Void
    let onDismiss: () -> Void
    let onRunSuggestedAction: (String) -> Void
    let onSubmitText: (String) -> Void
    let onVoiceFollowUp: () -> Void
    let onVoiceToggle: () -> Void
    /// Called when the orb is tapped so the coordinator can bring this panel
    /// to the front — preventing a higher-z transparent panel from intercepting
    /// subsequent drags or gestures on the now-expanded card.
    let onBringToFront: () -> Void

    /// Animated local copy of physicsState.isOrbHovered.
    /// All morph animations share this single spring context.
    @State private var isExpanded = false

    var body: some View {
        ZStack(alignment: .trailing) {
            // Passthrough background — hit testing is driven by simultaneousGesture below.
            Color.clear.allowsHitTesting(false)

            // The morphing element — orb or card, one unified view.
            // ZStack anchors the status dot to the orb's actual top-right corner
            // before the trailing padding is applied, so the dot doesn't drift
            // 12pt away when the panel has extra right space.
            ZStack(alignment: .topTrailing) {
                MorphingAgentBubbleView(
                    session: session,
                    physicsState: physicsState,
                    isExpanded: isExpanded,
                    onDragStarted: onDragStarted,
                    onDragUpdated: onDragUpdated,
                    onDragEnded: onDragEnded,
                    onDismiss: onDismiss,
                    onRunSuggestedAction: onRunSuggestedAction,
                    onSubmitText: onSubmitText,
                    onVoiceToggle: onVoiceToggle
                )

                // Status dot sits at the orb's corner — offset nudges it to overlap
                // the edge slightly for the classic notification-badge look.
                OrbAccentStatusDot(status: session.status, isHovered: isExpanded)
                    .offset(x: 4, y: -4)
            }
            .padding(.trailing, kOrbTrailingPadding)
            // Tap-to-expand: only fire when collapsed so the card can still receive
            // its own interactions (text fields, buttons) when expanded.
            // simultaneousGesture lets this fire even while DragGesture is pending.
            .simultaneousGesture(
                TapGesture().onEnded {
                    guard !isExpanded else { return }
                    onBringToFront()   // bring this panel above any overlapping transparent panels
                    physicsState.isOrbHovered = true
                }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Spring drives the morph — response/damping approximate CSS cubic-bezier(0.34,1.56,0.64,1)
        .onChange(of: physicsState.isOrbHovered) { nowExpanded in
            withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) {
                isExpanded = nowExpanded
            }
        }
    }
}
