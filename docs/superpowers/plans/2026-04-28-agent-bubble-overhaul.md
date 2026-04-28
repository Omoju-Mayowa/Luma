# Agent Bubble Overhaul Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the shared-panel VStack bubble dock with independent per-session NSPanel bubbles that use the Glassy Orb visual, Rich Card hover-expand, and physics animations (violent shake when running, gentle idle drift, proximity influence).

**Architecture:** Each `AgentSession` gets its own floating `NSPanel` (72×72) managed by `AgentBubbleWindow`. The coordinator `LumaAgentDockWindowManager` maintains a `[UUID: AgentBubbleWindow]` map, diffs it on each `show(sessions:)` call, and drives a 25 Hz physics timer that computes shake offsets and proximity factors. SwiftUI views inside each panel observe the session directly via `@ObservedObject` so title/status updates are always live.

**Tech Stack:** SwiftUI + AppKit (`NSPanel`, `NSHostingView`), Combine, macOS 14+

---

## File Map

| Action | File | Responsibility |
|--------|------|----------------|
| **Rewrite** | `leanring-buddy/Agent/LumaAgentDockWindowManager.swift` | All bubble types, views, physics state, coordinator |
| **Edit** | `leanring-buddy/CompanionManager.swift` | Pass `agentSessions` instead of `agentDockItems` |
| **Update** | `CLAUDE.md` | Line count update |

---

## Task 1: Rewrite LumaAgentDockWindowManager — skeleton + physics state + NSPanel wrapper

**Files:**
- Rewrite: `leanring-buddy/Agent/LumaAgentDockWindowManager.swift`

Replace the entire file with the new architecture. After this task the app builds with simple placeholder bubbles (plain circles, no decoration yet). Do NOT remove `AgentIconShape` — it is used by `AgentSession.swift`.

- [ ] **Step 1: Replace `LumaAgentDockWindowManager.swift` with the new skeleton**

```swift
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

/// Per-bubble observable state for physics animation and voice recording.
/// Updated at 25 Hz by the coordinator's physics timer.
@MainActor
final class AgentBubblePhysicsState: ObservableObject {
    /// Current pixel offset applied to the orb for physics effects.
    @Published var physicsOffset: CGSize = .zero
    /// Set by coordinator when the user is voice-recording into this agent.
    @Published var isVoiceRecording: Bool = false

    /// Phase offset (radians) randomized at init so all idle bubbles drift out of sync.
    let idlePhaseOffset: Double = Double.random(in: 0 ..< Double.pi * 2)
    /// Set by the coordinator based on distance to nearest running bubble (0–1).
    var proximityShakeFactor: Double = 0.0

    /// Called by the coordinator on each physics tick.
    func updatePhysics(sessionIsRunning: Bool, currentTime: TimeInterval) {
        if sessionIsRunning {
            // Violent shake: 12 pt in a random direction, updated at 25 Hz.
            let angle = Double.random(in: 0 ..< Double.pi * 2)
            let shakeRadius = 12.0
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

// MARK: - AgentBubbleWindow

/// Wraps a single floating NSPanel for one agent session.
/// Owns drag handling (with screen clamping), panel resizing on hover,
/// and the AgentBubblePhysicsState used by the SwiftUI view inside.
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

    private var positionUserDefaultsKey: String {
        "luma.agentBubble.\(sessionID.uuidString).origin"
    }

    /// The screen-space center of this bubble's current panel frame.
    /// Used by the coordinator to compute inter-bubble proximity distances.
    var screenCenter: NSPoint {
        NSPoint(x: panel.frame.midX, y: panel.frame.midY)
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

        let orbDiameter: CGFloat = 72
        let panel = KeyAcceptingPanel(
            contentRect: NSRect(x: 0, y: 0, width: orbDiameter, height: orbDiameter),
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
            onHoverChanged: { [weak self] isHovered in self?.handleHoverChanged(isHovered: isHovered) },
            onDismiss: onDismiss,
            onRunSuggestedAction: onRunSuggestedAction,
            onSubmitText: onSubmitText,
            onVoiceFollowUp: onVoiceFollowUp,
            onVoiceToggle: onVoiceToggle
        )
        panel.contentView = NSHostingView(rootView: bubbleView)

        let clampedOrigin = Self.clampOriginToScreen(origin: initialOrigin, windowSize: panel.frame.size)
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
        let clampedOrigin = Self.clampOriginToScreen(origin: savedOrigin, windowSize: panel.frame.size)
        panel.setFrameOrigin(clampedOrigin)
    }

    // MARK: Drag callbacks (invoked by SwiftUI DragGesture in AgentBubbleRootView)

    private func handleDragStarted() {
        dragStartMouseScreenLocation = NSEvent.mouseLocation
        dragStartWindowOrigin = panel.frame.origin
        isDragging = true
    }

    private func handleDragUpdated() {
        let currentMouse = NSEvent.mouseLocation
        let deltaX = currentMouse.x - dragStartMouseScreenLocation.x
        let deltaY = currentMouse.y - dragStartMouseScreenLocation.y
        let proposedOrigin = NSPoint(
            x: dragStartWindowOrigin.x + deltaX,
            y: dragStartWindowOrigin.y + deltaY
        )
        let clampedOrigin = Self.clampOriginToScreen(origin: proposedOrigin, windowSize: panel.frame.size)
        panel.setFrameOrigin(clampedOrigin)
    }

    private func handleDragEnded() {
        isDragging = false
        let origin = panel.frame.origin
        UserDefaults.standard.set([origin.x, origin.y], forKey: positionUserDefaultsKey)
    }

    // MARK: Hover-driven panel resize

    /// Called by the SwiftUI view when hover state changes.
    /// Resizes the NSPanel (anchoring the top-right corner so the orb stays put)
    /// to fit the expanded card or collapse back to orb-only size.
    func handleHoverChanged(isHovered: Bool) {
        let orbDiameter: CGFloat = 72
        let cardWidth: CGFloat = 260
        let orbCardGap: CGFloat = 8
        let expandedWidth = cardWidth + orbCardGap + orbDiameter
        let expandedHeight: CGFloat = 280

        let topRightX = panel.frame.maxX
        let topRightY = panel.frame.maxY

        let newSize: NSSize = isHovered
            ? NSSize(width: expandedWidth, height: expandedHeight)
            : NSSize(width: orbDiameter, height: orbDiameter)

        let proposedOrigin = NSPoint(
            x: topRightX - newSize.width,
            y: topRightY - newSize.height
        )
        let clampedOrigin = Self.clampOriginToScreen(origin: proposedOrigin, windowSize: newSize)
        panel.setFrame(NSRect(origin: clampedOrigin, size: newSize), display: true, animate: false)
    }

    // MARK: Screen clamping

    private static func clampOriginToScreen(origin: NSPoint, windowSize: NSSize) -> NSPoint {
        guard let screen = NSScreen.main else { return origin }
        let visibleFrame = screen.visibleFrame
        let clampedX = max(visibleFrame.minX, min(origin.x, visibleFrame.maxX - windowSize.width))
        let clampedY = max(visibleFrame.minY, min(origin.y, visibleFrame.maxY - windowSize.height))
        return NSPoint(x: clampedX, y: clampedY)
    }
}

// MARK: - Coordinator

@MainActor
final class LumaAgentDockWindowManager {
    private var bubbleWindows: [UUID: AgentBubbleWindow] = [:]
    private var physicsTimer: Timer?

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
    }

    func hide() {
        for (_, window) in bubbleWindows { window.close() }
        bubbleWindows.removeAll()
        stopPhysicsTimer()
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
        }

        // Open windows for sessions that are new
        for session in sessions where bubbleWindows[session.id] == nil {
            guard let onDismissAgent, let onRunSuggestedAction,
                  let onVoiceFollowUp, let onSubmitTextFromDock, let onVoiceToggle else { continue }

            let initialOrigin = defaultSpawnOriginForNewBubble(existingCount: bubbleWindows.count)
            let window = AgentBubbleWindow(
                session: session,
                initialOrigin: initialOrigin,
                onDismiss: { [weak self] in
                    guard let self else { return }
                    onDismissAgent(session.id)
                },
                onRunSuggestedAction: { action in
                    onRunSuggestedAction(session.id, action)
                },
                onSubmitText: { text in
                    onSubmitTextFromDock(session.id, text)
                },
                onVoiceFollowUp: { [weak self] in
                    guard let self else { return }
                    onVoiceFollowUp(session.id)
                },
                onVoiceToggle: { [weak self] in
                    guard let self else { return }
                    onVoiceToggle(session.id)
                }
            )
            window.restorePersistedPosition()
            bubbleWindows[session.id] = window
        }
    }

    /// Computes a default spawn origin staggered from the bottom-right corner.
    private func defaultSpawnOriginForNewBubble(existingCount: Int) -> NSPoint {
        guard let screen = NSScreen.main else { return .zero }
        let visibleFrame = screen.visibleFrame
        let orbDiameter: CGFloat = 72
        let spacingBetweenBubbles: CGFloat = 10
        let rightEdgeX = visibleFrame.maxX - orbDiameter - 20
        let baseY = visibleFrame.minY + 120
        let stackedY = baseY + CGFloat(existingCount) * (orbDiameter + spacingBetweenBubbles)
        return NSPoint(x: rightEdgeX, y: stackedY)
    }

    // MARK: Physics timer

    private func startPhysicsTimerIfNeeded() {
        guard physicsTimer == nil else { return }
        physicsTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 25.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tickPhysics()
            }
        }
    }

    private func stopPhysicsTimer() {
        physicsTimer?.invalidate()
        physicsTimer = nil
    }

    private func tickPhysics() {
        let currentTime = Date.timeIntervalSinceReferenceDate

        // Collect screen centers of running bubbles for proximity computation
        let runningBubbleCenters: [NSPoint] = bubbleWindows.values
            .filter { $0.sessionIsRunning }
            .map { $0.screenCenter }

        for (_, window) in bubbleWindows {
            // Compute proximity factor for non-running bubbles
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

// MARK: - AgentBubbleRootView (placeholder — replaced in Task 2)

/// Root SwiftUI view hosted in each AgentBubbleWindow panel.
/// Placeholder: plain circle, no decoration.
private struct AgentBubbleRootView: View {
    @ObservedObject var session: AgentSession
    @ObservedObject var physicsState: AgentBubblePhysicsState

    let onDragStarted: () -> Void
    let onDragUpdated: () -> Void
    let onDragEnded: () -> Void
    let onHoverChanged: (Bool) -> Void
    let onDismiss: () -> Void
    let onRunSuggestedAction: (String) -> Void
    let onSubmitText: (String) -> Void
    let onVoiceFollowUp: () -> Void
    let onVoiceToggle: () -> Void

    @State private var isHovered = false
    @State private var isDragActive = false

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            // Expanded card will appear here in Task 3
            Circle()
                .fill(session.glowColor.opacity(0.5))
                .frame(width: 72, height: 72)
                .offset(x: physicsState.physicsOffset.width, y: physicsState.physicsOffset.height)
                .animation(.linear(duration: 0.04), value: physicsState.physicsOffset)
                .gesture(
                    DragGesture(minimumDistance: 4, coordinateSpace: .global)
                        .onChanged { _ in
                            if !isDragActive {
                                isDragActive = true
                                onDragStarted()
                            }
                            onDragUpdated()
                        }
                        .onEnded { _ in
                            isDragActive = false
                            onDragEnded()
                        }
                )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .onHover { hovering in
            onHoverChanged(hovering)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                isHovered = hovering
            }
        }
    }
}
```

- [ ] **Step 2: Build the project in Xcode (Cmd+B)**

Expected: build succeeds. Each agent session now shows as a simple colored circle in its own draggable window. Verify:
- Each bubble is independent (drag one, others stay put)
- Bubbles don't leave screen bounds when dragged to edge
- Working agents produce visible shake; idle agents have gentle vertical drift

- [ ] **Step 3: Commit**

```bash
cd /Users/nox/Desktop/luma
git add leanring-buddy/Agent/LumaAgentDockWindowManager.swift
git commit -m "refactor: one NSPanel per agent bubble, physics timer, screen-clamped drag"
```

---

## Task 2: Glassy Orb visual — full bubble design

**Files:**
- Modify: `leanring-buddy/Agent/LumaAgentDockWindowManager.swift` — replace placeholder `AgentBubbleRootView` with full `AgentGlassyOrbView` + wired-up `AgentBubbleRootView`

- [ ] **Step 1: Replace the placeholder `AgentBubbleRootView` and add `AgentGlassyOrbView`**

Remove the entire placeholder `AgentBubbleRootView` struct and the `// MARK: - AgentBubbleRootView (placeholder...)` comment block. Replace with these two structs:

```swift
// MARK: - AgentGlassyOrbView

/// 72×72 circular bubble with glassy orb aesthetic:
/// radial gradient fill, specular highlight, glow ring, pulsing status dot, icon.
private struct AgentGlassyOrbView: View {
    @ObservedObject var session: AgentSession
    @ObservedObject var physicsState: AgentBubblePhysicsState
    let isHovered: Bool
    let onDragStarted: () -> Void
    let onDragUpdated: () -> Void
    let onDragEnded: () -> Void

    @State private var isDragActive = false

    var body: some View {
        ZStack {
            // Base circle — radial gradient from accent color at top-left to near-black center
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            session.glowColor.opacity(0.55),
                            Color(red: 0.03, green: 0.02, blue: 0.07)
                        ]),
                        center: UnitPoint(x: 0.35, y: 0.35),
                        startRadius: 0,
                        endRadius: 44
                    )
                )
                .overlay(
                    Circle()
                        .stroke(session.glowColor.opacity(0.4), lineWidth: 1)
                )

            // Specular highlight — small white oval at top-left, simulates glass sheen
            Ellipse()
                .fill(Color.white.opacity(0.22))
                .frame(width: 20, height: 9)
                .rotationEffect(.degrees(-20))
                .offset(x: -10, y: -17)
                .blendMode(.screen)

            // Agent icon shape, centered
            Image(systemName: session.iconShape.systemImageName)
                .font(.system(size: 24, weight: .heavy))
                .foregroundColor(session.glowColor.opacity(0.9))

            // Status dot — top-right corner, pulsing when running
            OrbStatusDot(status: session.status)
                .offset(x: 26, y: -26)
        }
        .frame(width: 72, height: 72)
        // Outer glow ring — intensity increases on hover
        .shadow(color: session.glowColor.opacity(isHovered ? 0.55 : 0.35), radius: isHovered ? 18 : 12)
        .shadow(color: Color.black.opacity(0.45), radius: 10, y: 4)
        // Scale slightly on hover
        .scaleEffect(isHovered ? 1.06 : 1.0)
        // Physics displacement — applied with fast linear animation so shake feels snappy
        .offset(x: physicsState.physicsOffset.width, y: physicsState.physicsOffset.height)
        .animation(.linear(duration: 0.04), value: physicsState.physicsOffset)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isHovered)
        // Drag gesture moves the parent NSPanel via coordinator callbacks
        .gesture(
            DragGesture(minimumDistance: 4, coordinateSpace: .global)
                .onChanged { _ in
                    if !isDragActive {
                        isDragActive = true
                        onDragStarted()
                    }
                    onDragUpdated()
                }
                .onEnded { _ in
                    isDragActive = false
                    onDragEnded()
                }
        )
        .pointerCursor()
    }
}

// MARK: - OrbStatusDot

/// Pulsing colored dot for session status display.
private struct OrbStatusDot: View {
    let status: AgentSessionStatus
    @State private var isPulsingLarge = false

    var dotColor: Color {
        switch status {
        case .stopped:              return Color.gray.opacity(0.5)
        case .starting, .running:   return Color.yellow
        case .ready:                return Color.green
        case .failed:               return Color.red
        }
    }

    var isPulsing: Bool {
        status == .running || status == .starting
    }

    var body: some View {
        Circle()
            .fill(dotColor)
            .frame(width: 10, height: 10)
            .shadow(color: dotColor.opacity(0.85), radius: 4)
            .overlay(Circle().stroke(Color(red: 0.05, green: 0.04, blue: 0.08), lineWidth: 1.5))
            .scaleEffect(isPulsing && isPulsingLarge ? 0.65 : 1.0)
            .opacity(isPulsing && isPulsingLarge ? 0.35 : 1.0)
            .animation(
                isPulsing
                    ? .easeInOut(duration: 0.6).repeatForever(autoreverses: true)
                    : .default,
                value: isPulsingLarge
            )
            .onAppear { isPulsingLarge = isPulsing }
            .onChange(of: isPulsing) { active in
                isPulsingLarge = active
            }
    }
}

// MARK: - AgentBubbleRootView

/// Root view for each bubble panel.
/// Lays out: [expanded card] [orb] (card appears to the left of the orb on hover).
private struct AgentBubbleRootView: View {
    @ObservedObject var session: AgentSession
    @ObservedObject var physicsState: AgentBubblePhysicsState

    let onDragStarted: () -> Void
    let onDragUpdated: () -> Void
    let onDragEnded: () -> Void
    let onHoverChanged: (Bool) -> Void
    let onDismiss: () -> Void
    let onRunSuggestedAction: (String) -> Void
    let onSubmitText: (String) -> Void
    let onVoiceFollowUp: () -> Void
    let onVoiceToggle: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            // Expanded card will be inserted here in Task 3
            AgentGlassyOrbView(
                session: session,
                physicsState: physicsState,
                isHovered: isHovered,
                onDragStarted: onDragStarted,
                onDragUpdated: onDragUpdated,
                onDragEnded: onDragEnded
            )
        }
        // Align content to the trailing (right) edge so the orb stays put when the
        // panel expands leftward to reveal the card.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .onHover { hovering in
            // Resize the NSPanel BEFORE animating the SwiftUI card so the panel
            // is already large enough when SwiftUI starts the card transition.
            onHoverChanged(hovering)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                isHovered = hovering
            }
        }
    }
}
```

- [ ] **Step 2: Build the project in Xcode (Cmd+B)**

Expected: build succeeds. Bubbles are now Glassy Orb style — circular with radial gradient, specular highlight, pulsing status dot, glow ring.

- [ ] **Step 3: Commit**

```bash
git add leanring-buddy/Agent/LumaAgentDockWindowManager.swift
git commit -m "feat: glassy orb bubble visual with radial gradient, specular highlight, pulsing dot"
```

---

## Task 3: Rich Card expanded view on hover

**Files:**
- Modify: `leanring-buddy/Agent/LumaAgentDockWindowManager.swift` — add `AgentBubbleExpandedRichCard`, wire into `AgentBubbleRootView`

- [ ] **Step 1: Add `AgentBubbleExpandedRichCard` before `AgentBubbleRootView`**

Insert this new struct before the `// MARK: - AgentBubbleRootView` mark:

```swift
// MARK: - AgentBubbleExpandedRichCard

/// Rich card that slides in to the left of the orb on hover.
/// Layout: header strip (title + status chip + close) / body (text + actions + input + voice).
private struct AgentBubbleExpandedRichCard: View {
    @ObservedObject var session: AgentSession
    @ObservedObject var physicsState: AgentBubblePhysicsState

    let onDismiss: () -> Void
    let onRunSuggestedAction: (String) -> Void
    let onSubmitText: (String) -> Void
    let onVoiceToggle: () -> Void

    @State private var followUpInputText: String = ""

    var body: some View {
        VStack(spacing: 0) {
            cardHeader
            cardBody
        }
        .frame(width: 260)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(red: 0.03, green: 0.024, blue: 0.07).opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.8), radius: 24, y: 8)
        .shadow(color: session.glowColor.opacity(0.08), radius: 16)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: Header

    private var cardHeader: some View {
        HStack(spacing: 6) {
            // Pulse dot
            OrbStatusDot(status: session.status)
                .frame(width: 6, height: 6)
                .scaleEffect(6.0 / 10.0)  // scale down from OrbStatusDot's 10pt base

            Text(session.title.uppercased())
                .font(.system(size: 11, weight: .heavy))
                .foregroundColor(session.glowColor.opacity(0.9))
                .kerning(0.07 * 11)
                .lineLimit(1)

            Spacer()

            // Status chip
            statusChip

            // Close / terminate button
            Button(action: onDismiss) {
                Text("✕")
                    .font(.system(size: 13))
                    .foregroundColor(Color.white.opacity(0.2))
            }
            .buttonStyle(.plain)
            .pointerCursor()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.02))
        .overlay(
            // Accent gradient divider at the bottom of the header strip
            LinearGradient(
                colors: [.clear, session.glowColor.opacity(0.3), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 1),
            alignment: .bottom
        )
    }

    // MARK: Body

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Latest response text (max 3 lines)
            Text(session.latestActivitySummary ?? "Waiting for response...")
                .font(.system(size: 11.5))
                .foregroundColor(Color.white.opacity(session.latestActivitySummary != nil ? 0.65 : 0.3))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .italic(session.latestActivitySummary == nil)

            // Suggested next-step action pills (from ResponseCard, max 2)
            let suggestedActions = session.latestResponseCard?.suggestedActions ?? []
            if !suggestedActions.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Next steps")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.25))
                        .kerning(0.08 * 9)
                        .textCase(.uppercase)

                    HStack(spacing: 5) {
                        ForEach(Array(suggestedActions.prefix(2)), id: \.self) { action in
                            Button(action: { onRunSuggestedAction(action) }) {
                                Text(action)
                                    .font(.system(size: 9.5, weight: .semibold))
                                    .foregroundColor(Color.white.opacity(0.55))
                                    .lineLimit(1)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color.white.opacity(0.05))
                                    .clipShape(Capsule())
                                    .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .pointerCursor()
                        }
                    }
                }
            }

            // Follow-up text input + send button
            HStack(spacing: 6) {
                TextField("Ask a follow-up...", text: $followUpInputText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 10.5))
                    .foregroundColor(Color.white.opacity(0.85))
                    .onSubmit { submitFollowUpInput() }

                Button(action: submitFollowUpInput) {
                    Text("↑")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 24, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(session.glowColor.opacity(
                                    followUpInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.25 : 0.7
                                ))
                        )
                }
                .buttonStyle(.plain)
                .pointerCursor()
                .disabled(followUpInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.07), lineWidth: 1)
            )

            // Voice toggle button — aligned to trailing edge
            HStack {
                Spacer()
                Button(action: onVoiceToggle) {
                    HStack(spacing: 4) {
                        Image(systemName: physicsState.isVoiceRecording ? "mic.fill" : "mic")
                            .font(.system(size: 9, weight: .semibold))
                        Text(physicsState.isVoiceRecording ? "Stop" : "Voice")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundColor(physicsState.isVoiceRecording ? Color.red.opacity(0.9) : Color.white.opacity(0.55))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        physicsState.isVoiceRecording ? Color.red.opacity(0.15) : Color.white.opacity(0.05)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(
                                physicsState.isVoiceRecording ? Color.red.opacity(0.3) : Color.white.opacity(0.08),
                                lineWidth: 0.5
                            )
                    )
                }
                .buttonStyle(.plain)
                .pointerCursor()
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 14)
    }

    // MARK: Helpers

    private func submitFollowUpInput() {
        let trimmedText = followUpInputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        onSubmitText(trimmedText)
        followUpInputText = ""
    }

    private var statusChip: some View {
        Text(session.status.displayLabel)
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(statusChipTextColor)
            .kerning(0.05 * 9)
            .textCase(.uppercase)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(statusChipBackground)
            .clipShape(Capsule())
    }

    private var statusChipTextColor: Color {
        switch session.status {
        case .running, .starting: return Color.yellow
        case .ready:              return Color.green
        case .failed:             return Color.red
        case .stopped:            return Color.white.opacity(0.4)
        }
    }

    private var statusChipBackground: some View {
        Capsule()
            .fill(statusChipFillColor)
            .overlay(Capsule().stroke(statusChipBorderColor, lineWidth: 1))
    }

    private var statusChipFillColor: Color {
        switch session.status {
        case .running, .starting: return Color.yellow.opacity(0.12)
        case .ready:              return Color.green.opacity(0.1)
        case .failed:             return Color.red.opacity(0.1)
        case .stopped:            return Color.white.opacity(0.05)
        }
    }

    private var statusChipBorderColor: Color {
        switch session.status {
        case .running, .starting: return Color.yellow.opacity(0.2)
        case .ready:              return Color.green.opacity(0.2)
        case .failed:             return Color.red.opacity(0.2)
        case .stopped:            return Color.white.opacity(0.08)
        }
    }
}
```

- [ ] **Step 2: Wire `AgentBubbleExpandedRichCard` into `AgentBubbleRootView`**

In the `AgentBubbleRootView.body` computed property, find the `HStack` and add the card with its transition before `AgentGlassyOrbView`:

Replace:
```swift
var body: some View {
    HStack(alignment: .center, spacing: 0) {
        // Expanded card will be inserted here in Task 3
        AgentGlassyOrbView(
```

With:
```swift
var body: some View {
    HStack(alignment: .center, spacing: 0) {
        if isHovered {
            AgentBubbleExpandedRichCard(
                session: session,
                physicsState: physicsState,
                onDismiss: onDismiss,
                onRunSuggestedAction: onRunSuggestedAction,
                onSubmitText: onSubmitText,
                onVoiceToggle: onVoiceToggle
            )
            .padding(.trailing, 8)
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .opacity
            ))
        }
        AgentGlassyOrbView(
```

- [ ] **Step 3: Build the project in Xcode (Cmd+B)**

Expected: build succeeds. Hovering over a bubble expands the panel leftward and shows the Rich Card with header strip (title, status chip, close button), response text, action pills, follow-up input, and voice toggle.

- [ ] **Step 4: Commit**

```bash
git add leanring-buddy/Agent/LumaAgentDockWindowManager.swift
git commit -m "feat: rich card expanded view slides in on orb hover"
```

---

## Task 4: Update CompanionManager to pass sessions directly

**Files:**
- Modify: `leanring-buddy/CompanionManager.swift` — change `updateAgentDock()` and `agentDockManager.show()` call

This is the fix for the title-always-shows-"New-Agent" bug. The dock was receiving a snapshot `AgentDockItem` struct whose `title` never updated. Now each `AgentBubbleWindow` holds a direct `AgentSession` reference and the SwiftUI view observes `session.title` live.

- [ ] **Step 1: Remove `agentDockItems` computed property from `CompanionManager`**

Find and delete these lines in `CompanionManager.swift` (around line 158–172):

```swift
    var agentDockItems: [AgentDockItem] {
        agentSessions.map { session in
            AgentDockItem(
                id: session.id,
                title: session.title,
                accentTheme: session.accentTheme,
                status: session.status,
                caption: session.latestActivitySummary.flatMap { String($0.prefix(40)) },
                responseText: session.latestResponseCard?.truncatedText,
                suggestedActions: session.latestResponseCard?.suggestedActions ?? [],
                iconShape: session.iconShape,
                glowColor: session.glowColor
            )
        }
    }
```

- [ ] **Step 2: Update `updateAgentDock()` to pass sessions directly**

Find `updateAgentDock()` (around line 1752) and replace:

```swift
    private func updateAgentDock() {
        if agentSessions.isEmpty || !isAgentModeEnabled {
            agentDockManager.hide()
        } else {
            agentDockManager.show(
                items: agentDockItems,
                onDismissAgent: { [weak self] sessionID in
                    Task { await self?.dismissAgentSession(id: sessionID) }
                },
                onRunSuggestedAction: { [weak self] sessionID, action in
                    self?.activeAgentSessionID = sessionID
                    self?.submitAgentPromptFromUI(action)
                },
                onVoiceFollowUp: { [weak self] sessionID in
                    self?.activeAgentSessionID = sessionID
                    self?.buddyDictationManager.cancelCurrentDictation()
                },
                onSubmitTextFromDock: { [weak self] sessionID, text in
                    self?.submitAgentPromptForSession(sessionID: sessionID, prompt: text)
                },
                onVoiceToggle: { [weak self] sessionID in
                    self?.toggleAgentVoiceRecording(sessionID: sessionID)
                }
            )
        }
    }
```

With:

```swift
    private func updateAgentDock() {
        if agentSessions.isEmpty || !isAgentModeEnabled {
            agentDockManager.hide()
        } else {
            agentDockManager.show(
                sessions: agentSessions,
                onDismissAgent: { [weak self] sessionID in
                    Task { await self?.dismissAgentSession(id: sessionID) }
                },
                onRunSuggestedAction: { [weak self] sessionID, action in
                    self?.activeAgentSessionID = sessionID
                    self?.submitAgentPromptFromUI(action)
                },
                onVoiceFollowUp: { [weak self] sessionID in
                    self?.activeAgentSessionID = sessionID
                    self?.buddyDictationManager.cancelCurrentDictation()
                },
                onSubmitTextFromDock: { [weak self] sessionID, text in
                    self?.submitAgentPromptForSession(sessionID: sessionID, prompt: text)
                },
                onVoiceToggle: { [weak self] sessionID in
                    self?.toggleAgentVoiceRecording(sessionID: sessionID)
                }
            )
        }
    }
```

- [ ] **Step 3: Build in Xcode (Cmd+B)**

Expected: build succeeds with zero errors. The only change from the compiler's perspective is the `items:` label → `sessions:` label and the type changing from `[AgentDockItem]` to `[AgentSession]`. If the compiler reports a missing `AgentDockItem` type, confirm the type is only defined in `LumaAgentDockWindowManager.swift` (where it was already removed in Task 1).

- [ ] **Step 4: Verify title update behavior**

Run the app, spawn an agent, submit a prompt ("research Swift concurrency"). The bubble title should update from "New Agent" to the generated title (e.g., "Swift Concurrency Research") within a few seconds of the first prompt.

- [ ] **Step 5: Commit**

```bash
git add leanring-buddy/CompanionManager.swift
git commit -m "fix: pass AgentSession references directly to dock so title updates live"
```

---

## Task 5: Update CLAUDE.md

**Files:**
- Modify: `CLAUDE.md` — update line count for `LumaAgentDockWindowManager.swift` and remove `AgentDockItem` reference

- [ ] **Step 1: Update the Key Files table entry**

Find the row for `LumaAgentDockWindowManager.swift` in `CLAUDE.md` and update its line count and description to reflect the new architecture (approximately 550 lines). Update the description to match:

> `Agent/LumaAgentDockWindowManager.swift` | ~550 | One floating NSPanel per agent session. Coordinator manages `[UUID: AgentBubbleWindow]`, syncs on each `show(sessions:)` call, drives 25 Hz physics timer. `AgentBubblePhysicsState` owns idle/working/proximity offsets. `AgentGlassyOrbView` (circular with radial gradient, specular highlight, glow) + `AgentBubbleExpandedRichCard` (Rich Card with header strip, accent divider, response text, action pills, follow-up input).

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md for new one-panel-per-bubble architecture"
```

---

## Self-Review

**Spec coverage check:**

| Requirement | Task |
|-------------|------|
| Fix off-screen glitch — clamp to screen bounds | Task 1 (`clampOriginToScreen` in `AgentBubbleWindow`) |
| Independent bubbles — one panel per session | Task 1 (`syncSessions` creates/destroys `AgentBubbleWindow`) |
| Idle slow hover/bounce (sine wave, 5 pt, 3 s) | Task 1 (`updatePhysics` idle branch) |
| Working violent shake (12 pt, 25 Hz, random direction) | Task 1 (`updatePhysics` running branch) |
| Proximity shake (nearby bubbles at 35 % amplitude) | Task 1 (`tickPhysics` proximity computation) |
| Glassy Orb visual | Task 2 (`AgentGlassyOrbView`) |
| Specular highlight | Task 2 (white `Ellipse`, blendMode `.screen`) |
| Rich Card expanded view (header + body) | Task 3 (`AgentBubbleExpandedRichCard`) |
| Status chip in card header | Task 3 (`statusChip` computed var) |
| Accent gradient divider in header | Task 3 (`.overlay` on header background) |
| Title fix — live from `AgentSession.title` | Task 4 (remove `agentDockItems` snapshot) |
| Screen-clamped drag | Task 1 (`handleDragUpdated` calls `clampOriginToScreen`) |
| Position persisted per-session | Task 1 (`positionUserDefaultsKey`, `restorePersistedPosition`) |

**Placeholder scan:** No TBDs, TODOs, or incomplete sections found.

**Type consistency check:**
- `AgentBubblePhysicsState.updatePhysics(sessionIsRunning:currentTime:)` — used in `tickPhysics` ✓
- `AgentBubbleWindow.physicsState` — accessed by coordinator in `tickPhysics` and `setVoiceRecordingAgent` ✓
- `AgentBubbleWindow.sessionIsRunning` — used by coordinator in `tickPhysics` ✓
- `AgentGlassyOrbView` — instantiated in `AgentBubbleRootView` ✓
- `AgentBubbleExpandedRichCard` — instantiated in `AgentBubbleRootView` ✓
- `session.latestResponseCard?.suggestedActions` — `ResponseCard` has `suggestedActions: [String]` ✓
- `session.status.displayLabel` — `AgentSessionStatus.displayLabel` returns uppercase status string ✓
- `OrbStatusDot` — used in both `AgentGlassyOrbView` (full size) and `AgentBubbleExpandedRichCard` header (scaled) ✓
