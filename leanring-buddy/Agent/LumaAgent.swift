//
//  LumaAgent.swift
//  leanring-buddy
//
//  Data model for a single Luma agent instance. Each agent has a unique identity,
//  visual appearance (color, shape, animation), state, and task context.
//

import Foundation
import SwiftUI

// MARK: - Agent Shape

/// Visual shapes for agent bubble icons. Randomly assigned on creation.
enum AgentShape: String, Codable, CaseIterable {
    case square
    case rhombus
    case triangle
    case hexagon
    case circle
}

// MARK: - Agent State

/// Lifecycle state of an agent bubble.
enum AgentState: String, Codable {
    case idle       // Minimized, waiting for input
    case expanded   // User tapped, showing full bubble
    case processing // Actively working on a task
    case complete   // Task finished, showing result
}

// MARK: - Task Status

/// Outcome of the agent's most recent task.
enum AgentTaskStatus: String, Codable {
    case complete
    case failed
    case inProgress
}

// MARK: - Luma Agent

/// A single agent instance with identity, appearance, position, state, and task context.
struct LumaAgent: Identifiable {
    let id: UUID
    var title: String                      // Generated from first task
    var color: Color                       // Random on creation
    var shape: AgentShape                  // Random on creation
    var isAnimating: Bool                  // Random — some bounce, some don't
    var position: CGPoint                  // Screen position (persisted)
    var state: AgentState
    var lastUsedAt: Date
    var model: String                      // Model ID for API calls
    var conversationHistory: [ConversationEntry]
    var processingText: String?            // e.g. "researching metal cups"
    var completionText: String?            // One-liner result
    var taskStatus: AgentTaskStatus?

    /// Creates a new agent with random visual properties.
    init(
        id: UUID = UUID(),
        title: String = "New Agent",
        model: String = AgentModel.claudeSonnet.rawValue,
        position: CGPoint = .zero
    ) {
        self.id = id
        self.title = title
        self.color = Self.randomAgentColor()
        self.shape = AgentShape.allCases.randomElement() ?? .circle
        self.isAnimating = Bool.random()
        self.position = position
        self.state = .idle
        self.lastUsedAt = Date()
        self.model = model
        self.conversationHistory = []
        self.processingText = nil
        self.completionText = nil
        self.taskStatus = nil
    }

    /// Pool of visually distinct agent colors.
    private static func randomAgentColor() -> Color {
        let agentColors: [Color] = [
            Color(red: 0.04, green: 0.52, blue: 1.0),  // Blue
            Color(red: 1.0,  green: 0.62, blue: 0.04), // Orange
            Color(red: 0.19, green: 0.82, blue: 0.35),  // Green
            Color(red: 1.0,  green: 0.23, blue: 0.19),  // Red
            Color(red: 0.69, green: 0.32, blue: 0.87),  // Purple
            Color(red: 0.0,  green: 0.80, blue: 0.78),  // Teal
            Color(red: 1.0,  green: 0.84, blue: 0.04),  // Yellow
            Color(red: 0.95, green: 0.46, blue: 0.59),  // Pink
        ]
        return agentColors.randomElement() ?? .blue
    }
}
