//
//  AgentManager.swift
//  leanring-buddy
//
//  Singleton that owns the live array of LumaAgent instances.
//  Handles spawn, dismiss, update, and position persistence.
//

import Foundation
import SwiftUI

@MainActor
final class AgentManager: ObservableObject {

    static let shared = AgentManager()

    // MARK: - Published State

    /// All active agents. Observed by AgentStackView for rendering.
    @Published private(set) var agents: [LumaAgent] = []

    /// The ID of the currently expanded agent (only one at a time), or nil.
    @Published var expandedAgentID: UUID? = nil

    // MARK: - UserDefaults Keys

    private static let agentPositionsKey = "luma.agents.positions"

    // MARK: - Init

    private init() {
        loadPersistedPositions()
    }

    // MARK: - Spawn

    /// Creates and adds a new agent. Enforces the max agent limit from AgentSettingsManager.
    /// Returns the newly created agent.
    @discardableResult
    func spawnAgent(title: String = "New Agent", model: String? = nil) -> LumaAgent {
        // Enforce agent limit
        let activeAgentDescriptors = agents.map {
            (id: $0.id, lastUsedAt: $0.lastUsedAt, isProcessing: $0.state == .processing)
        }
        if let dismissedAgentID = AgentSettingsManager.shared.enforceAgentLimit(activeAgents: activeAgentDescriptors) {
            dismissAgent(withID: dismissedAgentID)
        }

        // Calculate position — stack on right edge
        let stackIndex = agents.count
        let yPosition = 60.0 + Double(stackIndex) * 68.0
        let screenWidth = NSScreen.main?.frame.width ?? 1440
        let position = CGPoint(x: screenWidth - 44, y: yPosition)

        let resolvedModel = model ?? AgentModel.claudeSonnet.rawValue

        var newAgent = LumaAgent(
            title: title,
            model: resolvedModel,
            position: position
        )
        newAgent.lastUsedAt = Date()

        agents.append(newAgent)
        persistPositions()

        LumaLogger.log("[AgentManager] Spawned agent '\(newAgent.title)' (id: \(newAgent.id), shape: \(newAgent.shape.rawValue))")
        return newAgent
    }

    // MARK: - Dismiss

    /// Removes an agent by ID with optional animation delay.
    func dismissAgent(withID agentID: UUID) {
        agents.removeAll { $0.id == agentID }
        if expandedAgentID == agentID {
            expandedAgentID = nil
        }
        persistPositions()
        LumaLogger.log("[AgentManager] Dismissed agent \(agentID)")
    }

    // MARK: - Update

    /// Updates an agent in place. Use this to change state, title, processing text, etc.
    func updateAgent(withID agentID: UUID, update: (inout LumaAgent) -> Void) {
        guard let index = agents.firstIndex(where: { $0.id == agentID }) else { return }
        update(&agents[index])
        agents[index].lastUsedAt = Date()
    }

    /// Moves an agent to a new position and persists.
    func moveAgent(withID agentID: UUID, to newPosition: CGPoint) {
        guard let index = agents.firstIndex(where: { $0.id == agentID }) else { return }
        agents[index].position = newPosition
        persistPositions()
    }

    /// Expands a specific agent and collapses any currently expanded one.
    func expandAgent(withID agentID: UUID) {
        expandedAgentID = agentID
    }

    /// Collapses the currently expanded agent.
    func collapseExpandedAgent() {
        expandedAgentID = nil
    }

    /// Returns the agent at the given index, if it exists.
    func agent(atIndex index: Int) -> LumaAgent? {
        guard index >= 0 && index < agents.count else { return nil }
        return agents[index]
    }

    // MARK: - Position Persistence

    private func persistPositions() {
        let positionMap = Dictionary(uniqueKeysWithValues: agents.map {
            ($0.id.uuidString, [Double($0.position.x), Double($0.position.y)])
        })
        UserDefaults.standard.set(positionMap, forKey: Self.agentPositionsKey)
    }

    private func loadPersistedPositions() {
        // Positions are loaded when agents are spawned — since agents don't
        // persist across app launches (they're ephemeral), we only persist
        // positions for the current session. This method exists as a hook
        // for future persistence of agents across launches.
    }
}
