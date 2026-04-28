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

    private var positionUserDefaultsKey: String {
        "luma.agentBubble.\(sessionID.uuidString).origin"
    }

    /// The screen-space center of the orb in this bubble's panel.
    /// The orb sits at the trailing (right) end of the fixed 340-pt panel with 12 pt right
    /// padding, so its horizontal center is at panel.maxX − 12 pt padding − 28 pt half-orb.
    var screenCenter: NSPoint {
        let orbCenterX = panel.frame.maxX - 40   // 12 (right padding) + 28 (half of 56 pt orb)
        return NSPoint(x: orbCenterX, y: panel.frame.midY)
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

        // Panel is fixed at 300×200. The morphing view is a single element that
        // expands from 56×56 orb to 280×160 card — no separate card view.
        let fixedPanelWidth: CGFloat = 300
        let fixedPanelHeight: CGFloat = 200
        let panel = KeyAcceptingPanel(
            contentRect: NSRect(x: 0, y: 0, width: fixedPanelWidth, height: fixedPanelHeight),
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

    // MARK: Hover hit-testing (driven by coordinator's physics timer)

    /// Screen rect for the collapsed orb hit zone. Generous margins account for
    /// physics shake and the accent dot that extends above the 56 pt orb frame.
    /// Internal (not private) so the coordinator can access it for one-at-a-time logic.
    var orbHitRect: NSRect {
        let orbSize: CGFloat = 56
        let rightPad: CGFloat = 12
        let margin: CGFloat = 12
        return NSRect(
            x: panel.frame.maxX - rightPad - orbSize - margin,
            y: panel.frame.midY - orbSize / 2 - margin,
            width: orbSize + margin * 2,
            height: orbSize + margin * 2
        )
    }

    /// Screen rect for the expanded card hit zone. Mouse must leave this to collapse.
    /// Internal so the coordinator can use it for one-at-a-time enforcement.
    var expandedHitRect: NSRect {
        let cardWidth: CGFloat = 280
        let cardHeight: CGFloat = 160
        let inset: CGFloat = 8
        return NSRect(
            x: panel.frame.maxX - 12 - cardWidth - inset,
            y: panel.frame.midY - cardHeight / 2 - inset,
            width: cardWidth + inset * 2,
            height: cardHeight + inset * 2
        )
    }

    /// Returns true if the mouse is within the collapsed orb's enter zone.
    func isMouseInOrbZone(_ mouseScreenLocation: NSPoint) -> Bool {
        orbHitRect.contains(mouseScreenLocation)
    }

    /// Returns true if the mouse is within the expanded card's stay zone.
    func isMouseInCardZone(_ mouseScreenLocation: NSPoint) -> Bool {
        expandedHitRect.contains(mouseScreenLocation)
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
    /// The fixed 340×300 panel is placed so its right edge is flush with the screen's
    /// right edge — the orb (trailing end, 12 pt right padding) then appears ~12 pt
    /// from the right screen edge. Orbs stack upward with 10 pt gaps between them.
    private func defaultSpawnOriginForNewBubble(existingCount: Int) -> NSPoint {
        guard let screen = NSScreen.main else { return .zero }
        let visibleFrame = screen.visibleFrame
        let fixedPanelWidth: CGFloat = 300
        let orbViewDiameter: CGFloat = 56
        let spacingBetweenBubbles: CGFloat = 10
        let originX = visibleFrame.maxX - fixedPanelWidth
        let baseY = visibleFrame.minY + 120
        let stackedY = baseY + CGFloat(existingCount) * (orbViewDiameter + spacingBetweenBubbles)
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

    private func tickPhysics() {
        let currentTime = Date.timeIntervalSinceReferenceDate
        let mouseScreenLocation = NSEvent.mouseLocation

        // ── One-at-a-time hover enforcement ──────────────────────────────────
        // Only one bubble may be hovered at any moment. The coordinator decides
        // which one wins — per-bubble SwiftUI onHover is not used at all.
        //
        // Step 1: If a bubble is already expanded, keep it hovered only while
        //         the mouse remains inside its card zone.
        var activelyHoveredID: UUID? = nil
        for (id, window) in bubbleWindows where window.physicsState.isOrbHovered {
            if window.isMouseInCardZone(mouseScreenLocation) {
                activelyHoveredID = id  // Mouse still inside card — stay expanded
            } else {
                window.physicsState.isOrbHovered = false  // Mouse left — collapse
            }
        }

        // Step 2: If nothing is expanded, check if mouse enters any orb zone.
        if activelyHoveredID == nil {
            for (id, window) in bubbleWindows where !window.physicsState.isOrbHovered {
                if window.isMouseInOrbZone(mouseScreenLocation) {
                    window.physicsState.isOrbHovered = true
                    activelyHoveredID = id
                    break  // First match wins — enforces one at a time
                }
            }
        }

        // Step 3: Safety net — collapse any bubble that isn't the active one.
        for (id, window) in bubbleWindows where id != activelyHoveredID {
            window.physicsState.isOrbHovered = false
        }

        // ── Proximity shake + physics update ─────────────────────────────────
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
            .scaleEffect(isPulsing && isPulsingLarge ? 0.72 : 1.0)
            .opacity(isHovered ? 0.0 : (isPulsing && isPulsingLarge ? 0.6 : 1.0))
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
/// Collapsed state (isHovered = false):
///   • 56×56 circle, corner radius = 28 (full circle)
///   • Rich radial gradient with inner shadow for glassy depth
///   • Icon + specular highlights visible
///
/// Expanded state (isHovered = true):
///   • 280×160 rounded rect, corner radius = 20
///   • Dark card background with agent info
///   • Icon hidden, card content fades in after morph starts
///
/// The width, height, and corner radius all animate with a spring curve that
/// matches the CSS cubic-bezier(0.34, 1.56, 0.64, 1) springy overshoot feel.
private struct MorphingAgentBubbleView: View {
    @ObservedObject var session: AgentSession
    @ObservedObject var physicsState: AgentBubblePhysicsState

    let isHovered: Bool
    let onDragStarted: () -> Void
    let onDragUpdated: () -> Void
    let onDragEnded: () -> Void
    let onDismiss: () -> Void
    let onRunSuggestedAction: (String) -> Void
    let onSubmitText: (String) -> Void
    let onVoiceToggle: () -> Void

    // Cross-fade state — driven by onChange(of: isHovered) with staggered timing
    @State private var showCardContent = false
    @State private var showOrbIcon = true
    @State private var isDragActive = false
    @State private var followUpInputText: String = ""

    private let collapsedSize: CGFloat = 56
    private let expandedWidth: CGFloat = 280
    private let expandedHeight: CGFloat = 160

    private var currentWidth: CGFloat { isHovered ? expandedWidth : collapsedSize }
    private var currentHeight: CGFloat { isHovered ? expandedHeight : collapsedSize }
    // Full circle when collapsed; gentle rounded rect when expanded
    private var currentCornerRadius: CGFloat { isHovered ? 20 : collapsedSize / 2 }

    var body: some View {
        ZStack {
            // ── Card background (expanded state) ─────────────────────────────
            // Always rendered; fades in as the orb collapses
            Color(red: 0.04, green: 0.03, blue: 0.09)
                .opacity(showCardContent ? 1 : 0)
                .animation(.easeIn(duration: 0.18), value: showCardContent)

            // ── Orb gradient background (collapsed state) ─────────────────────
            // Vibrant radial gradient with light source at upper-left.
            // Fades out as the card background fades in.
            RadialGradient(
                gradient: Gradient(stops: [
                    .init(color: session.glowColor.opacity(0.95), location: 0.0),
                    .init(color: session.glowColor.opacity(0.75), location: 0.48),
                    .init(color: Color(red: 0.05, green: 0.02, blue: 0.12), location: 1.0),
                ]),
                center: UnitPoint(x: 0.30, y: 0.26),
                startRadius: 2,
                endRadius: 36
            )
            .opacity(showOrbIcon ? 1 : 0)
            .animation(.easeOut(duration: 0.12), value: showOrbIcon)

            // ── Inner shadow / dark rim ──────────────────────────────────────
            // Dark vignette at the orb edge creates glassy depth — like looking
            // into a bowl lit from above. The outer rim is near-black while the
            // center stays vibrant. Fades with the orb gradient.
            RadialGradient(
                gradient: Gradient(stops: [
                    .init(color: Color.clear, location: 0.44),
                    .init(color: Color.black.opacity(0.55), location: 1.0)
                ]),
                center: .center,
                startRadius: 0,
                endRadius: 30
            )
            .opacity(showOrbIcon ? 1 : 0)
            .animation(.easeOut(duration: 0.12), value: showOrbIcon)

            // ── Specular highlights (orb state only) ──────────────────────────
            // Primary soft highlight — large, blurred, upper-left
            Ellipse()
                .fill(Color.white.opacity(0.28))
                .frame(width: 24, height: 11)
                .rotationEffect(.degrees(-22))
                .offset(x: -12, y: -17)
                .blur(radius: 2)
                .blendMode(.screen)
                .opacity(showOrbIcon ? 1 : 0)
                .animation(.easeOut(duration: 0.10), value: showOrbIcon)

            // Secondary pin-point catch light — sharp, crisp
            Ellipse()
                .fill(Color.white.opacity(0.72))
                .frame(width: 7, height: 4)
                .offset(x: -14, y: -20)
                .blendMode(.screen)
                .opacity(showOrbIcon ? 1 : 0)
                .animation(.easeOut(duration: 0.10), value: showOrbIcon)

            // ── Agent icon (collapsed state) ──────────────────────────────────
            Image(systemName: session.iconShape.systemImageName)
                .font(.system(size: 22, weight: .heavy))
                .foregroundColor(Color.white.opacity(0.95))
                .shadow(color: Color.black.opacity(0.35), radius: 3)
                .opacity(showOrbIcon ? 1 : 0)
                .animation(.easeOut(duration: 0.12), value: showOrbIcon)

            // ── Card content (expanded state) ─────────────────────────────────
            cardContentView
                .opacity(showCardContent ? 1 : 0)
                .animation(.easeIn(duration: 0.18), value: showCardContent)
        }
        .frame(width: currentWidth, height: currentHeight)
        .clipShape(RoundedRectangle(cornerRadius: currentCornerRadius, style: .continuous))
        // Glass border — bright at top-left, subtle at bottom-right
        .overlay(
            RoundedRectangle(cornerRadius: currentCornerRadius, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(isHovered ? 0.09 : 0.38),
                            Color.white.opacity(0.04)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        )
        // Outer glow — stronger on collapsed orb, subtler on expanded card
        .shadow(color: session.glowColor.opacity(isHovered ? 0.20 : 0.50), radius: isHovered ? 10 : 18)
        .shadow(color: Color.black.opacity(0.50), radius: 12, y: 5)
        // Physics offset — disabled when expanded so the card is stable
        .offset(
            x: isHovered ? 0 : physicsState.physicsOffset.width,
            y: isHovered ? 0 : physicsState.physicsOffset.height
        )
        .animation(.linear(duration: 0.04), value: physicsState.physicsOffset)
        // Drag gesture — only active when collapsed (drag while expanded is ignored)
        .gesture(
            DragGesture(minimumDistance: 4, coordinateSpace: .global)
                .onChanged { _ in
                    guard !isHovered else { return }
                    if !isDragActive { isDragActive = true; onDragStarted() }
                    onDragUpdated()
                }
                .onEnded { _ in isDragActive = false; onDragEnded() }
        )
        // Staggered cross-fade: icon fades first, card reveals after morph is underway
        .onChange(of: isHovered) { nowHovered in
            if nowHovered {
                withAnimation(.easeOut(duration: 0.10)) { showOrbIcon = false }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                    withAnimation(.easeIn(duration: 0.18)) { showCardContent = true }
                }
            } else {
                withAnimation(.easeOut(duration: 0.12)) { showCardContent = false }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                    withAnimation(.easeIn(duration: 0.10)) { showOrbIcon = true }
                }
            }
        }
    }

    // MARK: - Card content

    private var cardContentView: some View {
        VStack(alignment: .leading, spacing: 0) {
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
            // Inline status dot matching the accent dot color
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
        .padding(.vertical, 9)
        .background(Color.white.opacity(0.03))
    }

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(session.latestActivitySummary ?? "Waiting for response...")
                .font(.system(size: 11))
                .foregroundColor(
                    Color.white.opacity(session.latestActivitySummary != nil ? 0.60 : 0.28)
                )
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .italic(session.latestActivitySummary == nil)

            // Follow-up text input
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

/// Root SwiftUI view hosted in each AgentBubbleWindow panel (300×200 fixed rect).
/// A clear passthrough background fills the panel; the morphing orb/card sits at
/// the trailing edge with an accent status dot overlaid at its top-right.
///
/// Hover state is driven by the coordinator's 25 Hz physics timer (physicsState.isOrbHovered),
/// not by SwiftUI onHover, preventing NSTrackingArea interference between adjacent panels.
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

    /// Animated local copy of physicsState.isOrbHovered.
    /// Updated with a spring so the morph animation is driven by withAnimation context.
    @State private var isHovered = false

    var body: some View {
        ZStack(alignment: .trailing) {
            // Transparent fill — passes all mouse events through to desktop except
            // where interactive SwiftUI views below capture them.
            Color.clear.allowsHitTesting(false)

            // The morphing element — orb or card, one unified view
            MorphingAgentBubbleView(
                session: session,
                physicsState: physicsState,
                isHovered: isHovered,
                onDragStarted: onDragStarted,
                onDragUpdated: onDragUpdated,
                onDragEnded: onDragEnded,
                onDismiss: onDismiss,
                onRunSuggestedAction: onRunSuggestedAction,
                onSubmitText: onSubmitText,
                onVoiceToggle: onVoiceToggle
            )
            .padding(.trailing, 12)
            // Status accent dot floats above the orb's top-right corner.
            // Uses overlay so it is not clipped by the morphing view's clipShape.
            .overlay(alignment: .topTrailing) {
                OrbAccentStatusDot(status: session.status, isHovered: isHovered)
                    .offset(x: 4, y: -4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Spring drives the morph — response/damping match CSS cubic-bezier(0.34,1.56,0.64,1)
        .onChange(of: physicsState.isOrbHovered) { nowHovered in
            withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) {
                isHovered = nowHovered
            }
        }
    }
}
