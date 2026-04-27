//
//  LumaAgentDockWindowManager.swift
//  leanring-buddy
//
//  Floating dock showing active agent sessions as circular icons
//  at the bottom of the screen. Each icon shows the agent's initials,
//  accent color, and status indicator dot.
//

import AppKit
import SwiftUI

struct AgentDockItem: Identifiable {
    let id: UUID
    var title: String
    var accentTheme: LumaAccentTheme
    var status: AgentSessionStatus
    var caption: String?
}

@MainActor
final class LumaAgentDockWindowManager {
    private var window: NSPanel?

    func show(items: [AgentDockItem], onSelect: @escaping (UUID) -> Void) {
        guard !items.isEmpty else {
            hide()
            return
        }

        let dockView = AgentDockView(items: items, onSelect: onSelect)

        if window == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 190),
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
            panel.contentView = NSHostingView(rootView: dockView)

            // Position at bottom center of main screen
            if let screen = NSScreen.main {
                let screenFrame = screen.visibleFrame
                let horizontalCenter = screenFrame.midX - 260
                let bottomWithMargin = screenFrame.minY + 20
                panel.setFrameOrigin(NSPoint(x: horizontalCenter, y: bottomWithMargin))
            }

            panel.makeKeyAndOrderFront(nil)
            self.window = panel
        } else {
            window?.contentView = NSHostingView(rootView: dockView)
        }
    }

    func hide() {
        window?.close()
        window = nil
    }
}

// MARK: - Dock View

private struct AgentDockView: View {
    let items: [AgentDockItem]
    let onSelect: (UUID) -> Void

    var body: some View {
        HStack(spacing: 10) {
            ForEach(items) { item in
                AgentDockItemView(item: item)
                    .onTapGesture { onSelect(item.id) }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Dock Item

private struct AgentDockItemView: View {
    let item: AgentDockItem
    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(DS.Colors.surface2)
                    .frame(width: 54, height: 54)
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [item.accentTheme.accent, item.accentTheme.accentHover],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.1
                            )
                    )
                    .shadow(color: .black.opacity(0.3), radius: 24, y: 0)
                    .shadow(color: .black.opacity(0.62), radius: 15, y: 0)
                    .shadow(color: .black.opacity(0.5), radius: 10, y: 0)

                Text(String(item.title.prefix(2)).uppercased())
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(item.accentTheme.accent)

                // Status indicator dot
                Circle()
                    .fill(statusColor)
                    .frame(width: 9, height: 9)
                    .offset(x: 20, y: 20)
            }
            .frame(width: 66, height: 66)
            .scaleEffect(isHovered ? 1.08 : 1.0)
            .animation(.easeOut(duration: 0.15), value: isHovered)
            .onHover { isHovered = $0 }
            .pointerCursor()

            if let caption = item.caption {
                Text(caption)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(DS.Colors.textTertiary)
                    .lineLimit(1)
            }
        }
    }

    private var statusColor: Color {
        switch item.status {
        case .stopped: return DS.Colors.textTertiary
        case .starting: return DS.Colors.warning
        case .ready: return DS.Colors.success
        case .running: return item.accentTheme.accent
        case .failed: return DS.Colors.destructive
        }
    }
}
