//
//  LumaAgentDockWindowManager.swift
//  leanring-buddy
//
//  Floating agent bubbles stacked vertically on the right edge of the screen.
//  Each bubble is a 48x48 rounded square with a colored cursor arrow icon
//  and a status dot. Tapping expands to show the response card with
//  suggested actions and follow-up buttons.
//

import AppKit
import SwiftUI

struct AgentDockItem: Identifiable {
    let id: UUID
    var title: String
    var accentTheme: LumaAccentTheme
    var status: AgentSessionStatus
    var caption: String?
    var responseText: String?
    var suggestedActions: [String]
}

@MainActor
final class LumaAgentDockWindowManager {
    private var window: NSPanel?

    func show(
        items: [AgentDockItem],
        expandedItemID: UUID?,
        onSelect: @escaping (UUID) -> Void,
        onDismissExpanded: @escaping () -> Void,
        onRunSuggestedAction: @escaping (UUID, String) -> Void,
        onTextFollowUp: @escaping (UUID) -> Void,
        onVoiceFollowUp: @escaping (UUID) -> Void
    ) {
        guard !items.isEmpty else {
            hide()
            return
        }

        let bubbleView = AgentBubbleStackView(
            items: items,
            expandedItemID: expandedItemID,
            onSelect: onSelect,
            onDismissExpanded: onDismissExpanded,
            onRunSuggestedAction: onRunSuggestedAction,
            onTextFollowUp: onTextFollowUp,
            onVoiceFollowUp: onVoiceFollowUp
        )

        if window == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 600),
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
    let expandedItemID: UUID?
    let onSelect: (UUID) -> Void
    let onDismissExpanded: () -> Void
    let onRunSuggestedAction: (UUID, String) -> Void
    let onTextFollowUp: (UUID) -> Void
    let onVoiceFollowUp: (UUID) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Expanded card appears to the left of the mini bubbles
            if let expandedID = expandedItemID,
               let expandedItem = items.first(where: { $0.id == expandedID }) {
                ExpandedAgentBubbleView(
                    item: expandedItem,
                    onDismiss: onDismissExpanded,
                    onRunSuggestedAction: { action in
                        onRunSuggestedAction(expandedID, action)
                    },
                    onTextFollowUp: { onTextFollowUp(expandedID) },
                    onVoiceFollowUp: { onVoiceFollowUp(expandedID) }
                )
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }

            // Mini bubble stack on the right edge
            VStack(spacing: 10) {
                ForEach(items) { item in
                    MiniBubbleView(
                        item: item,
                        isExpanded: item.id == expandedItemID
                    )
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            onSelect(item.id)
                        }
                    }
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: expandedItemID)
    }
}

// MARK: - Mini Bubble (48x48 rounded square)

private struct MiniBubbleView: View {
    let item: AgentDockItem
    var isExpanded: Bool = false
    @State private var isHovered = false

    var body: some View {
        ZStack {
            // Rounded square background
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: 0.08, green: 0.08, blue: 0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            isExpanded
                                ? item.accentTheme.accent.opacity(0.6)
                                : Color.white.opacity(isHovered ? 0.12 : 0.06),
                            lineWidth: isExpanded ? 1.5 : 1
                        )
                )

            // Colored cursor arrow icon
            Image(systemName: "cursorarrow")
                .font(.system(size: 18, weight: .heavy))
                .foregroundColor(item.accentTheme.accent)
                .rotationEffect(.degrees(-18))

            // Status dot — top right
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .overlay(Circle().stroke(Color.black.opacity(0.5), lineWidth: 1))
                .offset(x: 16, y: -16)
        }
        .frame(width: 48, height: 48)
        .shadow(color: .black.opacity(0.45), radius: 12, y: 4)
        .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
        .scaleEffect(isHovered ? 1.06 : 1.0)
        .animation(.easeOut(duration: DS.Animation.fast), value: isHovered)
        .onHover { isHovered = $0 }
        .pointerCursor()
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

// MARK: - Expanded Agent Bubble (response card)

private struct ExpandedAgentBubbleView: View {
    let item: AgentDockItem
    let onDismiss: () -> Void
    let onRunSuggestedAction: (String) -> Void
    let onTextFollowUp: () -> Void
    let onVoiceFollowUp: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: title + status
            HStack {
                Text(item.title.uppercased())
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundColor(DS.Colors.textPrimary)
                    .kerning(0.5)
                    .lineLimit(1)

                Spacer()

                Text(statusLabel)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(statusLabelColor)

                Circle()
                    .fill(statusDotColor)
                    .frame(width: 8, height: 8)
            }

            // Response text body
            if let responseText = item.responseText, !responseText.isEmpty {
                Text(responseText)
                    .font(.system(size: 12.5, weight: .regular))
                    .foregroundColor(DS.Colors.textPrimary)
                    .lineLimit(6)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            } else {
                Text("Waiting for response...")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DS.Colors.textTertiary)
                    .italic()
            }

            // Suggested next actions
            if !item.suggestedActions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Suggested next:")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(DS.Colors.textTertiary)

                    ForEach(item.suggestedActions, id: \.self) { action in
                        Button(action: { onRunSuggestedAction(action) }) {
                            Text(action)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(DS.Colors.textPrimary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color.white.opacity(0.08))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                                )
                        }
                        .buttonStyle(.plain)
                        .pointerCursor()
                    }
                }
            }

            // Follow up row
            VStack(alignment: .leading, spacing: 6) {
                Text("Follow up")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(DS.Colors.textTertiary)

                HStack(spacing: 8) {
                    followUpButton(
                        iconName: "character.cursor.ibeam",
                        label: "Text",
                        action: onTextFollowUp
                    )
                    followUpButton(
                        iconName: "mic.fill",
                        label: "Voice",
                        action: onVoiceFollowUp
                    )
                }
            }
        }
        .padding(14)
        .frame(width: 280, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 0.08, green: 0.08, blue: 0.10).opacity(0.96))
                .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func followUpButton(iconName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: iconName)
                    .font(.system(size: 10, weight: .semibold))
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundColor(DS.Colors.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
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

    private var statusDotColor: Color {
        switch item.status {
        case .stopped: return DS.Colors.textTertiary
        case .starting: return DS.Colors.warning
        case .ready: return DS.Colors.success
        case .running: return Color.yellow
        case .failed: return DS.Colors.destructive
        }
    }
}
