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
            self?.tickPhysics()
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

/// Pulsing colored dot indicating agent session status.
private struct OrbStatusDot: View {
    let status: AgentSessionStatus
    @State private var isPulsingLarge = false

    private var dotColor: Color {
        switch status {
        case .stopped:              return Color.gray.opacity(0.5)
        case .starting, .running:   return Color.yellow
        case .ready:                return Color.green
        case .failed:               return Color.red
        }
    }

    private var isPulsing: Bool {
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

/// Root SwiftUI view hosted in each AgentBubbleWindow panel.
/// Lays out: [expanded card] [orb] — card appears to the left of the orb on hover.
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
            // Expanded card will be added here in Task 3
            AgentGlassyOrbView(
                session: session,
                physicsState: physicsState,
                isHovered: isHovered,
                onDragStarted: onDragStarted,
                onDragUpdated: onDragUpdated,
                onDragEnded: onDragEnded
            )
        }
        // Align content to trailing so orb stays on the right as the panel expands leftward.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .onHover { hovering in
            // Resize the NSPanel BEFORE animating SwiftUI so the panel is already
            // the right size when SwiftUI starts the card transition.
            onHoverChanged(hovering)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                isHovered = hovering
            }
        }
    }
}
