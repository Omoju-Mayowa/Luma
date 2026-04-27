//
//  AgentSession.swift
//  leanring-buddy
//
//  Core agent session model. Each session represents one autonomous agent
//  with its own transcript, status, accent theme, and runtime binding.
//  Mirrors OpenClicky's CodexAgentSession architecture.
//

import AppKit
import Combine
import Foundation
import SwiftUI

enum AgentSessionStatus: Equatable {
    case stopped
    case starting
    case ready
    case running
    case failed(String)

    var displayLabel: String {
        switch self {
        case .stopped: return "OFFLINE"
        case .starting: return "STARTING"
        case .ready: return "AGENT"
        case .running: return "WORKING"
        case .failed: return "NEEDS ATTENTION"
        }
    }

    static func == (lhs: AgentSessionStatus, rhs: AgentSessionStatus) -> Bool {
        switch (lhs, rhs) {
        case (.stopped, .stopped), (.starting, .starting), (.ready, .ready), (.running, .running):
            return true
        case (.failed(let lhsMsg), .failed(let rhsMsg)):
            return lhsMsg == rhsMsg
        default:
            return false
        }
    }
}

@MainActor
final class AgentSession: ObservableObject, Identifiable {
    let id: UUID
    @Published var title: String
    @Published var accentTheme: LumaAccentTheme
    @Published private(set) var status: AgentSessionStatus = .stopped
    @Published private(set) var entries: [AgentTranscriptEntry] = []
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var latestResponseCard: ResponseCard?
    @Published var model: String
    @Published var workingDirectoryPath: String

    /// Random icon shape assigned at creation for visual variety in the dock
    let iconShape: AgentIconShape
    /// Random glow color for the dock bubble
    let glowColor: Color

    private var runtime: (any AgentRuntime)?
    private var cancellables = Set<AnyCancellable>()
    private var hasGeneratedTitle = false

    private static let randomGlowColors: [Color] = [
        Color(red: 0.04, green: 0.52, blue: 1.0),   // Blue
        Color(red: 0.20, green: 0.83, blue: 0.60),   // Mint
        Color(red: 1.00, green: 0.70, blue: 0.14),   // Amber
        Color(red: 0.96, green: 0.36, blue: 0.42),   // Rose
        Color(red: 0.65, green: 0.40, blue: 1.00),   // Purple
        Color(red: 0.00, green: 0.87, blue: 0.87),   // Cyan
        Color(red: 1.00, green: 0.47, blue: 0.00),   // Orange
        Color(red: 0.56, green: 0.85, blue: 0.27),   // Lime
    ]

    var statusSummaryLine: String {
        switch status {
        case .stopped: return "Agent is offline"
        case .starting: return "Starting up..."
        case .ready: return "Ready for tasks"
        case .running: return "Working on task..."
        case .failed(let message): return "Failed: \(message)"
        }
    }

    var latestActivitySummary: String? {
        entries.last(where: { $0.role == .assistant })?.text
    }

    var hasVisibleActivity: Bool {
        !entries.isEmpty
    }

    init(
        id: UUID = UUID(),
        title: String = "New Agent",
        accentTheme: LumaAccentTheme = .blue,
        model: String = UserDefaults.standard.string(forKey: "luma.agent.defaultModel") ?? "claude-sonnet-4-6",
        workingDirectoryPath: String = UserDefaults.standard.string(forKey: "luma.agent.workingDirectory") ?? NSHomeDirectory()
    ) {
        self.id = id
        self.title = title
        self.accentTheme = accentTheme
        self.model = model
        self.workingDirectoryPath = workingDirectoryPath
        self.iconShape = AgentIconShape.random
        self.glowColor = Self.randomGlowColors.randomElement() ?? Color.blue
    }

    func bind(to runtime: any AgentRuntime) {
        self.runtime = runtime

        runtime.transcriptPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] entry in
                guard let self else { return }
                self.entries.append(entry)

                // Build response card from assistant messages
                if entry.role == .assistant {
                    let card = ResponseCard(source: .agent, rawText: entry.text)
                    self.latestResponseCard = card
                }

                // Persist to memory history
                switch entry.role {
                case .user:
                    AgentMemoryIntegration.recordUserMessage(
                        agentId: self.id.uuidString,
                        agentTitle: self.title,
                        content: entry.text
                    )
                case .assistant:
                    AgentMemoryIntegration.recordAgentResponse(
                        agentId: self.id.uuidString,
                        agentTitle: self.title,
                        content: entry.text,
                        taskStatus: nil
                    )
                default:
                    break
                }
            }
            .store(in: &cancellables)

        runtime.statusPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (sessionId, newStatus) in
                guard let self, sessionId == self.id else { return }
                let previousStatus = self.status
                self.status = newStatus
                if case .failed(let message) = newStatus {
                    self.lastErrorMessage = message
                }

                // Detect task completion: running → ready
                if case .running = previousStatus, case .ready = newStatus {
                    self.announceTaskCompletion()
                }
            }
            .store(in: &cancellables)
    }

    func warmUp() async {
        guard let runtime else { return }
        status = .starting
        do {
            try await runtime.startSession(
                id: id,
                task: "",
                workingDirectory: workingDirectoryPath,
                systemContext: ""
            )
            status = .ready
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    func submitPrompt(_ prompt: String, systemContext: String = "") async {
        generateTitleIfNeeded(from: prompt)

        guard let runtime else { return }
        let userEntry = AgentTranscriptEntry(role: .user, text: prompt)
        entries.append(userEntry)
        status = .running
        lastErrorMessage = nil

        // Build full conversation context so the runtime has complete history
        let contextualPrompt = buildContextualPrompt(latestPrompt: prompt)

        do {
            try await runtime.submitPrompt(sessionId: id, prompt: contextualPrompt)
        } catch {
            status = .failed(error.localizedDescription)
            lastErrorMessage = error.localizedDescription
        }
    }

    /// Builds a prompt string that includes prior conversation history so each
    /// CLI invocation has full context (Claude CLI spawns a new process per prompt).
    private func buildContextualPrompt(latestPrompt: String) -> String {
        // If this is the first message, just return the prompt as-is
        let priorEntries = entries.dropLast() // everything except the one we just appended
        guard !priorEntries.isEmpty else { return latestPrompt }

        var contextLines: [String] = ["[Previous conversation for context:]"]
        for entry in priorEntries {
            let roleLabel: String
            switch entry.role {
            case .user: roleLabel = "User"
            case .assistant: roleLabel = "Assistant"
            case .system: roleLabel = "System"
            case .command: roleLabel = "Command"
            case .plan: roleLabel = "Plan"
            }
            contextLines.append("\(roleLabel): \(entry.text)")
        }
        contextLines.append("")
        contextLines.append("[New request:]")
        contextLines.append(latestPrompt)

        return contextLines.joined(separator: "\n")
    }

    func stop() async {
        guard let runtime else { return }
        await runtime.stopSession(sessionId: id)
        status = .stopped
    }

    func dismissLatestResponseCard() {
        latestResponseCard = nil
    }

    func setResponseCard(_ card: ResponseCard) {
        latestResponseCard = card
    }

    // MARK: - Task Completion

    /// Notification posted when an agent session completes a task.
    /// userInfo contains "sessionId" (UUID), "title" (String), "summary" (String).
    static let taskCompletedNotificationName = Notification.Name("lumaAgentTaskCompleted")

    private func announceTaskCompletion() {
        let completionSummary = entries.last(where: { $0.role == .assistant })?.text ?? "Task completed"
        let truncatedSummary = completionSummary.count > 200
            ? String(completionSummary.prefix(200)) + "..."
            : completionSummary

        // Post notification so overlay/pointer bubble can display the result
        NotificationCenter.default.post(
            name: Self.taskCompletedNotificationName,
            object: nil,
            userInfo: [
                "sessionId": id,
                "title": title,
                "summary": truncatedSummary
            ]
        )

        LumaLogger.log("[Luma] Agent '\(title)' completed task: \(truncatedSummary.prefix(80))...")
    }

    // MARK: - Title Generation

    private func generateTitleIfNeeded(from prompt: String) {
        guard !hasGeneratedTitle else { return }
        hasGeneratedTitle = true

        Task {
            guard let apiKey = ProfileManager.shared.loadActiveAPIKey(), !apiKey.isEmpty else { return }

            let titlePrompt = "Generate a 3-5 word title for this task: \(prompt). Return only the title, nothing else."

            var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

            let requestBody: [String: Any] = [
                "model": "google/gemini-2.5-flash:free",
                "messages": [["role": "user", "content": titlePrompt]],
                "max_tokens": 20
            ]
            request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)

            do {
                let (data, _) = try await URLSession.shared.data(for: request)
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]],
                   let message = choices.first?["message"] as? [String: Any],
                   let content = message["content"] as? String {
                    await MainActor.run {
                        self.title = content.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
            } catch {
                LumaLogger.log("[Luma] Title generation failed: \(error)")
            }
        }
    }
}
