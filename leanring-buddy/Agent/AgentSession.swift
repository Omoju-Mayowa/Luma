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

    private var runtime: (any AgentRuntime)?
    private var cancellables = Set<AnyCancellable>()
    private var hasGeneratedTitle = false

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
                self.status = newStatus
                if case .failed(let message) = newStatus {
                    self.lastErrorMessage = message
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

        do {
            try await runtime.submitPrompt(sessionId: id, prompt: prompt)
        } catch {
            status = .failed(error.localizedDescription)
            lastErrorMessage = error.localizedDescription
        }
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
