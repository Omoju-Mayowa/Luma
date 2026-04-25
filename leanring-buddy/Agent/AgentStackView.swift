//
//  AgentStackView.swift
//  leanring-buddy
//
//  Overlay view that positions all agent bubbles on screen.
//  Default layout: vertical stack on right edge, 16pt from edge, 12pt gap.
//  Supports drag repositioning, hover-to-dismiss, tap-to-expand,
//  idle bounce animation, and processing shake.
//

import SwiftUI

// MARK: - CGFloat Clamped Extension

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - Agent Stack View

/// Top-level overlay that renders all agent bubbles from AgentManager.
struct AgentStackView: View {
    @ObservedObject var agentManager: AgentManager

    var body: some View {
        ZStack {
            // Dim overlay when any bubble is expanded (20% black per PRD 7.2)
            if agentManager.expandedAgentID != nil {
                Color.black.opacity(0.2)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                            agentManager.collapseExpandedAgent()
                        }
                    }
            }

            ForEach(agentManager.agents) { agent in
                if agentManager.expandedAgentID == agent.id {
                    ExpandedAgentBubbleView(
                        agent: agent,
                        agentManager: agentManager,
                        expandOrigin: agent.position
                    )
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 56.0 / 500.0, anchor: expandAnchor(for: agent.position))
                                .combined(with: .opacity),
                            removal: .scale(scale: 56.0 / 500.0, anchor: expandAnchor(for: agent.position))
                                .combined(with: .opacity)
                        )
                    )
                    .zIndex(10)
                } else {
                    MinimizedAgentBubbleView(
                        agent: agent,
                        agentManager: agentManager
                    )
                    .position(agent.position)
                    .zIndex(1)
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: agentManager.expandedAgentID)
    }

    /// Calculates a UnitPoint anchor based on the bubble's screen position
    /// so the expand/collapse animation originates from the bubble's location.
    private func expandAnchor(for bubblePosition: CGPoint) -> UnitPoint {
        guard let screen = NSScreen.main else { return .center }
        let screenFrame = screen.visibleFrame
        let normalizedX = (bubblePosition.x - screenFrame.minX) / screenFrame.width
        let normalizedY = (bubblePosition.y - screenFrame.minY) / screenFrame.height
        return UnitPoint(x: normalizedX.clamped(to: 0...1), y: normalizedY.clamped(to: 0...1))
    }
}

// MARK: - Minimized Agent Bubble

/// A 56x56pt bubble showing the agent's shape, with idle bounce, processing shake,
/// hover dismiss, and tap-to-expand behavior.
struct MinimizedAgentBubbleView: View {
    let agent: LumaAgent
    @ObservedObject var agentManager: AgentManager

    @State private var isHovering = false
    @State private var dragOffset: CGSize = .zero

    var body: some View {
        ZStack(alignment: .topTrailing) {
            AgentShapeView(
                shape: agent.shape,
                color: agent.color,
                size: 56
            )
            .modifier(IdleBounceModifier(isAnimating: agent.isAnimating && agent.state != .processing))
            .modifier(ProcessingShakeModifier(isProcessing: agent.state == .processing))
            .onTapGesture {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                    agentManager.expandAgent(withID: agent.id)
                }
            }
            .onHover { hovering in
                isHovering = hovering
                if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        dragOffset = value.translation
                    }
                    .onEnded { value in
                        let newPosition = CGPoint(
                            x: agent.position.x + value.translation.width,
                            y: agent.position.y + value.translation.height
                        )
                        agentManager.moveAgent(withID: agent.id, to: newPosition)
                        dragOffset = .zero
                    }
            )
            .offset(dragOffset)

            // Dismiss X button (visible on hover)
            if isHovering {
                Button {
                    withAnimation(.easeOut(duration: 0.25)) {
                        agentManager.dismissAgent(withID: agent.id)
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.black.opacity(0.7))
                            .frame(width: 18, height: 18)
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .buttonStyle(.plain)
                .offset(x: 6, y: -6)
                .transition(.opacity)
            }
        }
    }
}

// MARK: - Idle Bounce Modifier

/// Continuous vertical bounce for agents with isAnimating == true.
struct IdleBounceModifier: ViewModifier {
    let isAnimating: Bool
    @State private var bounceOffset: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .offset(y: bounceOffset)
            .onAppear {
                guard isAnimating else { return }
                withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                    bounceOffset = -4
                }
            }
    }
}

// MARK: - Processing Shake Modifier

/// Horizontal shake for agents in processing state.
struct ProcessingShakeModifier: ViewModifier {
    let isProcessing: Bool
    @State private var shakeOffset: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .offset(x: isProcessing ? shakeOffset : 0)
            .onChange(of: isProcessing) { processing in
                if processing {
                    withAnimation(.spring(response: 0.1, dampingFraction: 0.3).repeatForever(autoreverses: true)) {
                        shakeOffset = 3
                    }
                } else {
                    withAnimation(.default) {
                        shakeOffset = 0
                    }
                }
            }
    }
}

// MARK: - Expanded Agent Bubble

/// Expanded view (~500x400pt) with header, status area, and input section.
/// Uses stagger-reveal animation with 80ms delay between each section (PRD 7.2).
struct ExpandedAgentBubbleView: View {
    let agent: LumaAgent
    @ObservedObject var agentManager: AgentManager
    /// The minimized bubble's position, used to anchor the expand animation origin.
    var expandOrigin: CGPoint = .zero

    @State private var showTextInput = false
    @State private var textInputDraft = ""
    @State private var showSections = false

    /// Per-PRD 7.2: spring animation with response: 0.4, dampingFraction: 0.75
    private let sectionSpring = Animation.spring(response: 0.4, dampingFraction: 0.75)
    /// Per-PRD 7.2: 80ms stagger delay between each section
    private let staggerDelay: Double = 0.08

    var body: some View {
        VStack(spacing: 0) {
            // Section 1: Header (delay: 0ms)
            headerSection
                .opacity(showSections ? 1 : 0)
                .offset(y: showSections ? 0 : 10)
                .animation(sectionSpring, value: showSections)

            // Section 2: Status Area (delay: 80ms)
            statusSection
                .opacity(showSections ? 1 : 0)
                .offset(y: showSections ? 0 : 10)
                .animation(sectionSpring.delay(staggerDelay), value: showSections)

            // Section 3: Input (delay: 160ms)
            inputSection
                .opacity(showSections ? 1 : 0)
                .offset(y: showSections ? 0 : 10)
                .animation(sectionSpring.delay(staggerDelay * 2), value: showSections)
        }
        .frame(width: 500, height: 400)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 0.06, green: 0.06, blue: 0.08))
                .shadow(color: Color.black.opacity(0.4), radius: 20)
        )
        .onAppear {
            withAnimation(sectionSpring) {
                showSections = true
            }
        }
    }

    // MARK: Header

    private var headerSection: some View {
        HStack(spacing: 10) {
            // Small shape icon
            AgentShapeView(shape: agent.shape, color: agent.color, size: 28)

            Text(agent.title)
                .font(LumaTheme.Typography.headline)
                .foregroundColor(LumaTheme.Colors.primaryText)
                .lineLimit(1)

            Spacer()

            // Collapse button — fade out content first, then collapse (PRD 7.2)
            Button {
                // Step 1: Fade out sections
                withAnimation(.easeOut(duration: 0.15)) {
                    showSections = false
                }
                // Step 2: After content fades, collapse the bubble
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                        agentManager.collapseExpandedAgent()
                    }
                }
            } label: {
                Image(systemName: "chevron.down.circle")
                    .font(.system(size: 16))
                    .foregroundColor(LumaTheme.Colors.secondaryText)
            }
            .buttonStyle(.plain)
            .onHover { isHovering in
                if isHovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(agent.color.opacity(0.08))
    }

    // MARK: Status Area

    private var statusSection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if agent.state == .processing {
                    // Processing state: show processing text + progress bar
                    if let processingText = agent.processingText {
                        Text(processingText)
                            .font(LumaTheme.Typography.body)
                            .foregroundColor(LumaTheme.Colors.primaryText)
                    }
                    ProgressView()
                        .progressViewStyle(.linear)
                        .tint(agent.color)
                } else if agent.state == .complete {
                    // Complete state: show result + status badge
                    if let completionText = agent.completionText {
                        Text(completionText)
                            .font(LumaTheme.Typography.body)
                            .foregroundColor(LumaTheme.Colors.primaryText)
                    }
                    HStack(spacing: 4) {
                        Image(systemName: agent.taskStatus == .failed ? "xmark.circle.fill" : "checkmark.circle.fill")
                        Text(agent.taskStatus == .failed ? "Failed" : "Complete")
                    }
                    .font(LumaTheme.Typography.bodyMedium)
                    .foregroundColor(agent.taskStatus == .failed ? LumaTheme.Colors.error : agent.color)
                } else {
                    // Idle state
                    Text("Ready for a task. Use voice or text to get started.")
                        .font(LumaTheme.Typography.body)
                        .foregroundColor(LumaTheme.Colors.tertiaryText)
                }
            }
            .padding(20)
        }
        .frame(height: 260)
    }

    // MARK: Input Section

    private var inputSection: some View {
        VStack(spacing: 0) {
            Divider().background(LumaTheme.Colors.surfaceElevated)

            if showTextInput {
                // Text input field
                HStack(spacing: 8) {
                    // Dismiss text field
                    Button {
                        showTextInput = false
                        textInputDraft = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(LumaTheme.Colors.secondaryText)
                    }
                    .buttonStyle(.plain)
                    .onHover { h in if h { NSCursor.pointingHand.push() } else { NSCursor.pop() } }

                    TextField("Type a task...", text: $textInputDraft)
                        .textFieldStyle(.plain)
                        .font(LumaTheme.Typography.body)
                        .foregroundColor(LumaTheme.Colors.primaryText)
                        .onSubmit {
                            submitTextInput()
                        }

                    // Submit button
                    Button {
                        submitTextInput()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(agent.color)
                    }
                    .buttonStyle(.plain)
                    .disabled(textInputDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                    .onHover { h in if h { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            } else {
                // Voice + Text buttons
                HStack(spacing: 16) {
                    // Voice button
                    Button {
                        // Voice input handled in Phase 5
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 14))
                            Text("Voice")
                                .font(LumaTheme.Typography.bodyMedium)
                        }
                        .foregroundColor(agent.color)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(agent.color.opacity(0.15))
                        .cornerRadius(LumaTheme.CornerRadius.medium)
                    }
                    .buttonStyle(.plain)
                    .onHover { h in if h { NSCursor.pointingHand.push() } else { NSCursor.pop() } }

                    // Text button
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showTextInput = true
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "keyboard")
                                .font(.system(size: 14))
                            Text("Text")
                                .font(LumaTheme.Typography.bodyMedium)
                        }
                        .foregroundColor(agent.color)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(agent.color.opacity(0.15))
                        .cornerRadius(LumaTheme.CornerRadius.medium)
                    }
                    .buttonStyle(.plain)
                    .onHover { h in if h { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
                }
                .padding(.vertical, 16)
            }
        }
    }

    // MARK: Actions

    private func submitTextInput() {
        let trimmedInput = textInputDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else { return }

        // Record to memory
        AgentMemoryIntegration.recordUserMessage(
            agentId: agent.id.uuidString,
            agentTitle: agent.title,
            content: trimmedInput
        )

        // Update agent state to processing
        agentManager.updateAgent(withID: agent.id) { agent in
            agent.state = .processing
            agent.processingText = trimmedInput
        }

        // Clear input immediately
        textInputDraft = ""
        showTextInput = false
    }
}
