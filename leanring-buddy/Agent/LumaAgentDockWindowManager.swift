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
            let shakeRadius = 8.0
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
    /// padding, so its horizontal center is at panel.maxX − 12 pt padding − 24 pt half-orb.
    var screenCenter: NSPoint {
        let orbCenterX = panel.frame.maxX - 36   // 12 (right padding) + 24 (half of 48 pt orb)
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

        // Panel is fixed at 340×300. The left ~268 pt is transparent when the card
        // is hidden, so hover no longer needs to resize the panel — eliminating the
        // onHover → setFrame → onHover feedback loop that caused the hover crash.
        let fixedPanelWidth: CGFloat = 340
        let fixedPanelHeight: CGFloat = 300
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

    /// Screen rect for the orb's collapsed hit zone — the mouse must enter this area to
    /// trigger hover. Generous size (right 96 pt × 120 pt) accounts for physics shake and
    /// the status dot that extends beyond the 48 pt orb frame.
    private var orbHitRect: NSRect {
        NSRect(
            x: panel.frame.maxX - 96,
            y: panel.frame.midY - 60,
            width: 96,
            height: 120
        )
    }

    /// Screen rect for the full expanded hit zone — mouse must leave this area to collapse
    /// the card once it is already open. Covers the full panel width so the user can
    /// interact with the card's text fields and buttons without losing hover.
    private var expandedHitRect: NSRect {
        NSRect(
            x: panel.frame.minX,
            y: panel.frame.minY + 5,
            width: panel.frame.width,
            height: panel.frame.height - 10
        )
    }

    /// Called by the coordinator on every physics tick (25 Hz).
    /// Uses hysteresis: enter on orb zone, exit only when mouse leaves the full card area.
    /// This approach prevents competing NSTrackingArea events from adjacent bubble panels.
    func updateHoverState(mouseScreenLocation: NSPoint) {
        if physicsState.isOrbHovered {
            physicsState.isOrbHovered = expandedHitRect.contains(mouseScreenLocation)
        } else {
            physicsState.isOrbHovered = orbHitRect.contains(mouseScreenLocation)
        }
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
        let fixedPanelWidth: CGFloat = 340
        let orbViewDiameter: CGFloat = 48
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
        // Snapshot mouse position once per tick — shared across all bubble updates.
        let mouseScreenLocation = NSEvent.mouseLocation

        // Collect screen centers of running bubbles for proximity computation
        let runningBubbleCenters: [NSPoint] = bubbleWindows.values
            .filter { $0.sessionIsRunning }
            .map { $0.screenCenter }

        for (_, window) in bubbleWindows {
            // Update hover state via exact rect hit-testing instead of NSTrackingArea,
            // preventing interference when adjacent bubble panels overlap.
            window.updateHoverState(mouseScreenLocation: mouseScreenLocation)

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

    // MARK: Header strip

    private var cardHeader: some View {
        HStack(spacing: 6) {
            OrbStatusDot(status: session.status)
                .frame(width: 6, height: 6)
                .scaleEffect(6.0 / 10.0)

            Text(session.title.uppercased())
                .font(.system(size: 11, weight: .heavy))
                .foregroundColor(session.glowColor.opacity(0.9))
                .kerning(0.07 * 11)
                .lineLimit(1)

            Spacer()

            statusChip

            Button(action: onDismiss) {
                Text("✕")
                    .font(.system(size: 13))
                    .foregroundColor(Color.white.opacity(0.2))
            }
            .buttonStyle(.plain)
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
                .buttonStyle(.plain)                .disabled(followUpInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.07), lineWidth: 1)
            )

            // Voice toggle button — trailing aligned
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
                .buttonStyle(.plain)            }
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

    @ViewBuilder
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
        .frame(width: 48, height: 48)
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
/// The panel is a fixed 340×300 rect. The left ~268 pt is transparent when the card is
/// hidden, so the panel never needs to resize on hover (eliminating the resize feedback loop).
///
/// Layout:
///   ZStack(alignment: .trailing)
///     Color.clear (passthrough — desktop clicks fall through the transparent region)
///     HStack { [card (optional)] [orb + horizontal padding for shake buffer] }
///       .onHover → animates isHovered, card appears/disappears
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

    /// Local copy of hover state, animated via onChange from physicsState.isOrbHovered.
    /// Driven by the coordinator's physics timer rather than SwiftUI onHover, which
    /// prevents NSTrackingArea interference between adjacent bubble panels.
    @State private var isHovered = false

    var body: some View {
        ZStack(alignment: .trailing) {
            // Fills the full fixed panel but passes all mouse events through to the
            // desktop — only interactive SwiftUI views below capture clicks.
            Color.clear.allowsHitTesting(false)

            // Content: card (optional) + orb. Trailing-aligned so the orb stays at the
            // right edge of the panel whether or not the card is visible.
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
                    session: session,
                    physicsState: physicsState,
                    isHovered: isHovered,
                    onDragStarted: onDragStarted,
                    onDragUpdated: onDragUpdated,
                    onDragEnded: onDragEnded
                )
                // Horizontal padding provides a clipping buffer: physics shake is ±8 pt so
                // 12 pt of padding on each side keeps the orb visible inside the panel.
                .padding(.horizontal, 12)
                // No .onHover — hover is driven by the coordinator's 25 Hz physics timer
                // checking NSEvent.mouseLocation against each bubble's orbHitRect.
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: physicsState.isOrbHovered) { nowHovered in
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                isHovered = nowHovered
            }
        }
    }
}
