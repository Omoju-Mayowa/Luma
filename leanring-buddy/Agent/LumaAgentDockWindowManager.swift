//
//  LumaAgentDockWindowManager.swift
//  leanring-buddy
//
//  Floating agent bubbles stacked vertically on the right edge of the screen.
//  Each bubble is a 48x48 rounded square with a random shape icon and colored
//  glow. Hover expands inline to show response card. Draggable with physics.
//

import AppKit
import SwiftUI

// MARK: - Data Model

struct AgentDockItem: Identifiable {
    let id: UUID
    var title: String
    var accentTheme: LumaAccentTheme
    var status: AgentSessionStatus
    var caption: String?
    var responseText: String?
    var suggestedActions: [String]
    /// Random shape assigned at session creation for visual variety
    var iconShape: AgentIconShape
    /// Random accent color for glow
    var glowColor: Color
}

/// Random shapes for agent bubble icons
enum AgentIconShape: String, CaseIterable {
    case triangle, diamond, hexagon, star, circle, square

    var systemImageName: String {
        switch self {
        case .triangle: return "triangle.fill"
        case .diamond: return "diamond.fill"
        case .hexagon: return "hexagon.fill"
        case .star: return "star.fill"
        case .circle: return "circle.fill"
        case .square: return "square.fill"
        }
    }

    static var random: AgentIconShape {
        allCases.randomElement() ?? .triangle
    }
}

// MARK: - Window Manager

@MainActor
final class LumaAgentDockWindowManager {
    private var window: NSPanel?

    func show(
        items: [AgentDockItem],
        onDismissAgent: @escaping (UUID) -> Void,
        onRunSuggestedAction: @escaping (UUID, String) -> Void,
        onVoiceFollowUp: @escaping (UUID) -> Void
    ) {
        guard !items.isEmpty else {
            hide()
            return
        }

        let bubbleView = AgentBubbleStackView(
            items: items,
            onDismissAgent: onDismissAgent,
            onRunSuggestedAction: onRunSuggestedAction,
            onVoiceFollowUp: onVoiceFollowUp
        )

        if window == nil {
            let panelWidth: CGFloat = 420
            let panelHeight: CGFloat = 600
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
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
            panel.contentView = NSHostingView(rootView: bubbleView)
            positionOnRightEdge(panel)
            panel.makeKeyAndOrderFront(nil)
            self.window = panel
        } else {
            window?.contentView = NSHostingView(rootView: bubbleView)
        }
    }

    func hide() {
        window?.close()
        window = nil
    }

    private func positionOnRightEdge(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let panelSize = panel.frame.size
        let rightEdgeX = screenFrame.maxX - panelSize.width - 8
        let verticalCenter = screenFrame.midY - panelSize.height / 2
        panel.setFrameOrigin(NSPoint(x: rightEdgeX, y: verticalCenter))
    }
}

// MARK: - Bubble Stack View

private struct AgentBubbleStackView: View {
    let items: [AgentDockItem]
    let onDismissAgent: (UUID) -> Void
    let onRunSuggestedAction: (UUID, String) -> Void
    let onVoiceFollowUp: (UUID) -> Void

    var body: some View {
        VStack(spacing: 10) {
            ForEach(items) { item in
                AgentBubbleItemView(
                    item: item,
                    onDismissAgent: { onDismissAgent(item.id) },
                    onRunSuggestedAction: { action in onRunSuggestedAction(item.id, action) },
                    onVoiceFollowUp: { onVoiceFollowUp(item.id) }
                )
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }
}

// MARK: - Single Agent Bubble (hover-expandable)

private struct AgentBubbleItemView: View {
    let item: AgentDockItem
    let onDismissAgent: () -> Void
    let onRunSuggestedAction: (String) -> Void
    let onVoiceFollowUp: () -> Void

    @State private var isHovered = false
    @State private var dragOffset: CGSize = .zero
    /// Persisted position from previous drags so the bubble stays where you drop it
    @State private var savedPosition: CGSize = .zero

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Expanded card appears to the left when hovered
            if isHovered {
                expandedCard
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .trailing)))
                    .padding(.trailing, 8)
            }

            // Mini bubble (always visible)
            miniBubble
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        // Hover on the entire row (mini + expanded) so moving to the card keeps it open
        .onHover { hovering in
            isHovered = hovering
        }
        .offset(x: savedPosition.width + dragOffset.width,
                y: savedPosition.height + dragOffset.height)
        .gesture(
            DragGesture()
                .onChanged { value in
                    dragOffset = value.translation
                }
                .onEnded { value in
                    // Keep the bubble where it was dropped
                    savedPosition = CGSize(
                        width: savedPosition.width + value.translation.width,
                        height: savedPosition.height + value.translation.height
                    )
                    dragOffset = .zero
                }
        )
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isHovered)
    }

    // MARK: Mini Bubble

    private var miniBubble: some View {
        ZStack {
            // Rounded square with glow
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: 0.08, green: 0.08, blue: 0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(item.glowColor.opacity(isHovered ? 0.5 : 0.15), lineWidth: isHovered ? 1.5 : 1)
                )
                .shadow(color: item.glowColor.opacity(isHovered ? 0.35 : 0.15), radius: isHovered ? 12 : 6, y: 0)

            // Random shape icon
            Image(systemName: item.iconShape.systemImageName)
                .font(.system(size: 18, weight: .heavy))
                .foregroundColor(item.glowColor)

            // Status dot — top right
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .overlay(Circle().stroke(Color.black.opacity(0.5), lineWidth: 1))
                .offset(x: 16, y: -16)
        }
        .frame(width: 48, height: 48)
        .shadow(color: .black.opacity(0.45), radius: 12, y: 4)
        .scaleEffect(isHovered ? 1.08 : 1.0)
        .pointerCursor()
    }

    // MARK: Expanded Card

    private var expandedCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header: title + status + close button
            HStack(spacing: 6) {
                Text(item.title.uppercased())
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundColor(DS.Colors.textPrimary)
                    .kerning(0.5)
                    .lineLimit(1)

                Spacer()

                Text(statusLabel)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(statusLabelColor)

                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)

                // Close/terminate button
                Button(action: onDismissAgent) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(DS.Colors.textTertiary)
                }
                .buttonStyle(.plain)
                .pointerCursor()
            }

            // Response text
            if let responseText = item.responseText, !responseText.isEmpty {
                Text(responseText)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(DS.Colors.textPrimary)
                    .lineLimit(5)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            } else {
                Text("Waiting for response...")
                    .font(.system(size: 11.5))
                    .foregroundColor(DS.Colors.textTertiary)
                    .italic()
            }

            // Recommended follow-up (max 2)
            if !item.suggestedActions.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Recommended")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(DS.Colors.textTertiary)
                        .kerning(0.3)

                    HStack(spacing: 6) {
                        ForEach(Array(item.suggestedActions.prefix(2)), id: \.self) { action in
                            Button(action: { onRunSuggestedAction(action) }) {
                                Text(action)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(DS.Colors.textPrimary)
                                    .lineLimit(1)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .fill(Color.white.opacity(0.07))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                                    )
                            }
                            .buttonStyle(.plain)
                            .pointerCursor()
                        }
                    }
                }
            }

            // Follow up row
            HStack(spacing: 6) {
                Text("Follow up")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(DS.Colors.textTertiary)
                    .kerning(0.3)

                Spacer()

                followUpButton(iconName: "mic.fill", label: "Voice", action: onVoiceFollowUp)
            }
        }
        .padding(12)
        .frame(width: 260, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 0.07, green: 0.07, blue: 0.09).opacity(0.96))
                .shadow(color: item.glowColor.opacity(0.12), radius: 16, y: 0)
                .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(item.glowColor.opacity(0.12), lineWidth: 1)
        )
    }

    // MARK: Helpers

    private func followUpButton(iconName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: iconName)
                    .font(.system(size: 9, weight: .semibold))
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundColor(DS.Colors.textPrimary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.white.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }

    private var statusLabel: String {
        switch item.status {
        case .stopped: return "Offline"
        case .starting: return "Starting"
        case .ready: return "Ready"
        case .running: return "Working"
        case .failed: return "Error"
        }
    }

    private var statusLabelColor: Color {
        switch item.status {
        case .ready: return DS.Colors.success
        case .running: return Color.yellow
        case .failed: return DS.Colors.destructiveText
        default: return DS.Colors.textTertiary
        }
    }

    private var statusColor: Color {
        switch item.status {
        case .stopped: return DS.Colors.textTertiary
        case .starting: return DS.Colors.warning
        case .ready: return DS.Colors.success
        case .running: return Color.yellow
        case .failed: return DS.Colors.destructive
        }
    }
}
