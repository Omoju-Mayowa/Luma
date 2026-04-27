//
//  AgentVoiceIntegration.swift
//  leanring-buddy
//
//  Handles voice command detection for agent spawning via regex patterns.
//  Includes heuristic title generation from task text.
//

import Foundation

/// Integrates voice commands and text input with the agent session system.
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

    /// Handles a spawn intent: creates a new agent session, and if an inline task was
    /// extracted, submits it immediately.
    static func handleSpawnIntent(inlineTask: String, companionManager: CompanionManager) {
        let session = companionManager.createAndSelectNewAgentSession()

        if !inlineTask.isEmpty {
            let systemContext = AgentMemoryIntegration.loadSummarizedMemoryForSystemContext()
            Task {
                await session.submitPrompt(inlineTask, systemContext: systemContext)
            }
        }
    }

    // MARK: - Heuristic Title Generation

    /// Simple heuristic title generation: takes first few meaningful words from the task.
    static func heuristicTitle(from task: String) -> String {
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
