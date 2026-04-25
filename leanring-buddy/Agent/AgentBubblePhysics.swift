//
//  AgentBubblePhysics.swift
//  leanring-buddy
//
//  Simple spring physics simulation for agent bubbles.
//  Uses CADisplayLink at 60fps to update bubble positions with:
//  - Velocity + momentum on drag release (decays over 0.5s)
//  - Gentle repulsion when bubbles overlap (min 8pt separation)
//  - Force impulse from processing shake propagating to nearby bubbles
//

import AppKit
import Combine
import Foundation

@MainActor
final class AgentBubblePhysicsEngine: ObservableObject {

    static let shared = AgentBubblePhysicsEngine()

    // MARK: - Physics State

    /// Per-bubble velocity vectors keyed by agent ID.
    @Published var velocities: [UUID: CGPoint] = [:]

    /// Per-bubble wobble amplitude (0–1) for neighbour shake effect.
    @Published var wobbleAmplitudes: [UUID: CGFloat] = [:]

    // MARK: - Configuration

    private let dragMomentumDecayRate: CGFloat = 0.92     // Decay per frame (~0.5s to zero)
    private let minimumBubbleSeparation: CGFloat = 8.0
    private let repulsionForce: CGFloat = 2.0
    private let shakeImpulseRadius: CGFloat = 80.0
    private let shakeImpulseStrength: CGFloat = 3.0
    private let wobbleDecayRate: CGFloat = 0.95

    // MARK: - Display Link

    private var displayLink: CVDisplayLink?
    private var isRunning = false

    private init() {}

    // MARK: - Start / Stop

    func start() {
        guard !isRunning else { return }
        isRunning = true

        // Use a Timer on the main run loop at 60fps instead of CVDisplayLink
        // since we need @MainActor access to update published properties.
        Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self = self, self.isRunning else {
                    timer.invalidate()
                    return
                }
                self.tick()
            }
        }
    }

    func stop() {
        isRunning = false
    }

    // MARK: - Drag Momentum

    /// Called when a bubble drag ends. Sets initial velocity for momentum effect.
    func applyDragMomentum(agentID: UUID, velocity: CGPoint) {
        velocities[agentID] = velocity
    }

    // MARK: - Processing Shake Impulse

    /// Called when an agent enters processing state. Sends force impulse
    /// to all nearby bubbles within the shake radius.
    func emitShakeImpulse(fromAgentID sourceID: UUID, atPosition sourcePosition: CGPoint) {
        let agents = AgentManager.shared.agents

        for agent in agents where agent.id != sourceID {
            let distance = hypot(
                agent.position.x - sourcePosition.x,
                agent.position.y - sourcePosition.y
            )
            guard distance < shakeImpulseRadius && distance > 0 else { continue }

            // Wobble amplitude inversely proportional to distance
            let normalizedDistance = distance / shakeImpulseRadius
            let amplitude = (1.0 - normalizedDistance) * 0.5  // 50% at edge
            wobbleAmplitudes[agent.id] = amplitude
        }
    }

    // MARK: - Physics Tick

    private func tick() {
        let agents = AgentManager.shared.agents
        guard !agents.isEmpty else { return }

        // Apply velocity decay and update positions
        for agent in agents {
            guard var velocity = velocities[agent.id],
                  (abs(velocity.x) > 0.1 || abs(velocity.y) > 0.1) else {
                velocities[agent.id] = .zero
                continue
            }

            velocity.x *= dragMomentumDecayRate
            velocity.y *= dragMomentumDecayRate
            velocities[agent.id] = velocity

            let newPosition = CGPoint(
                x: agent.position.x + velocity.x,
                y: agent.position.y + velocity.y
            )
            AgentManager.shared.moveAgent(withID: agent.id, to: newPosition)
        }

        // Apply gentle repulsion between overlapping bubbles
        let bubbleRadius: CGFloat = 28.0  // Half of 56pt bubble
        for i in 0..<agents.count {
            for j in (i + 1)..<agents.count {
                let agentA = agents[i]
                let agentB = agents[j]
                let dx = agentB.position.x - agentA.position.x
                let dy = agentB.position.y - agentA.position.y
                let distance = hypot(dx, dy)
                let minDistance = bubbleRadius * 2 + minimumBubbleSeparation

                if distance < minDistance && distance > 0 {
                    let overlap = minDistance - distance
                    let nx = dx / distance
                    let ny = dy / distance
                    let pushAmount = overlap * 0.5 * repulsionForce / minDistance

                    AgentManager.shared.moveAgent(
                        withID: agentA.id,
                        to: CGPoint(
                            x: agentA.position.x - nx * pushAmount,
                            y: agentA.position.y - ny * pushAmount
                        )
                    )
                    AgentManager.shared.moveAgent(
                        withID: agentB.id,
                        to: CGPoint(
                            x: agentB.position.x + nx * pushAmount,
                            y: agentB.position.y + ny * pushAmount
                        )
                    )
                }
            }
        }

        // Decay wobble amplitudes
        for (agentID, amplitude) in wobbleAmplitudes {
            let decayed = amplitude * wobbleDecayRate
            if decayed < 0.01 {
                wobbleAmplitudes[agentID] = nil
            } else {
                wobbleAmplitudes[agentID] = decayed
            }
        }
    }
}
