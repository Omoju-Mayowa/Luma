//
//  AgentVoiceIntegration.swift
//  leanring-buddy
//
//  Handles per-agent voice input, spawn detection via voice commands,
//  and agent title generation via lightweight API calls.
//

import Foundation

/// Integrates voice commands and text input with the agent system.
@MainActor
enum AgentVoiceIntegration {

    // MARK: - Voice Command Detection

    /// Intent detection patterns for agent spawn commands.
    /// Matches phrases like "open a new agent", "create a new agent",
    /// "spawn agent and research metal cups".
    private static let agentSpawnPatterns: [String] = [
        #"(?i)(?:open|create|spawn|start|launch)\s+(?:a\s+)?(?:new\s+)?agent\s+(?:and|to)\s+(.+)"#,
        #"(?i)(?:open|create|spawn|start|launch)\s+(?:a\s+)?(?:new\s+)?agent"#,
    ]

    /// Checks if a transcript contains an agent spawn command.
    /// Returns the extracted inline task if one follows the spawn command,
    /// or an empty string if the command is just "create a new agent".
    /// Returns nil if the transcript is not a spawn command.
    static func extractAgentSpawnIntent(from transcript: String) -> String? {
        let normalizedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTranscript.isEmpty else { return nil }

        for pattern in agentSpawnPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(normalizedTranscript.startIndex..<normalizedTranscript.endIndex, in: normalizedTranscript)
            if let match = regex.firstMatch(in: normalizedTranscript, range: range) {
                // Check if there's a captured task after the spawn command
                if match.numberOfRanges > 1,
                   let taskRange = Range(match.range(at: 1), in: normalizedTranscript) {
                    let inlineTask = String(normalizedTranscript[taskRange])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    return inlineTask.isEmpty ? "" : inlineTask
                }
                return ""  // Spawn command without inline task
            }
        }

        return nil
    }

    /// Handles a spawn intent: creates a new agent, and if an inline task was
    /// extracted, starts it immediately.
    static func handleSpawnIntent(inlineTask: String) {
        let agent = AgentManager.shared.spawnAgent()

        if !inlineTask.isEmpty {
            // Record the task and start processing
            AgentMemoryIntegration.recordUserMessage(
                agentId: agent.id.uuidString,
                agentTitle: agent.title,
                content: inlineTask
            )
            AgentManager.shared.updateAgent(withID: agent.id) { mutableAgent in
                mutableAgent.state = .processing
                mutableAgent.processingText = inlineTask
            }
            // Title will be generated once the task classifier processes it
            Task {
                await generateAgentTitle(for: agent.id, fromTask: inlineTask)
            }
        }
    }

    // MARK: - Agent Title Generation

    /// Generates a short (3–5 word) title for an agent based on its first task.
    /// Uses a lightweight API call to produce the title.
    static func generateAgentTitle(for agentID: UUID, fromTask task: String) async {
        let titlePrompt = "Generate a 3-5 word title for this task: \(task). Return only the title, nothing else."

        // Use the cheapest model available — prefer gpt-4o-mini
        // For now, generate a simple heuristic title to avoid API dependency in Phase 5
        let generatedTitle = heuristicTitle(from: task)

        AgentManager.shared.updateAgent(withID: agentID) { agent in
            agent.title = generatedTitle
        }

        LumaLogger.log("[AgentVoice] Generated title '\(generatedTitle)' for agent \(agentID)")
    }

    /// Simple heuristic title generation: takes first few meaningful words from the task.
    private static func heuristicTitle(from task: String) -> String {
        let stopWords: Set<String> = ["a", "an", "the", "to", "for", "and", "or", "in", "on", "at", "is", "it", "of", "my", "me", "i", "please", "can", "you", "could", "would"]
        let words = task.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty && !stopWords.contains($0) }

        let titleWords = Array(words.prefix(4))
        guard !titleWords.isEmpty else { return "Agent Task" }

        return titleWords
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}
