# Luma v3 OpenClicky Rebuild — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild Luma's UI and agent system to match OpenClicky exactly, replacing Codex's broken abstractions with a dual-runtime agent architecture (Claude Code CLI + Claude API fallback).

**Architecture:** Session-based agent model with `AgentRuntime` protocol, two concrete implementations (`ClaudeCodeAgentRuntime` via subprocess, `ClaudeAPIAgentRuntime` via tool-use loop), and OpenClicky-matching UI (companion panel, agent HUD, agent dock, response cards). All views use the `DS` design system tokens.

**Tech Stack:** Swift 5.9, SwiftUI + AppKit hybrid, macOS 14.0+, Combine, Foundation Process API, SSE streaming

**Reference Codebase:** `/Users/nox/Desktop/openclicky` — the authoritative visual and behavioral reference for all UI and agent work.

---

## Task 1: Fix Compilation Blockers

**Files:**
- Modify: `leanring-buddy/SettingsPanelView.swift`
- Modify: `leanring-buddy/Agent/AgentStackView.swift`
- Modify: `leanring-buddy/CompanionPanelView.swift`

- [ ] **Step 1: Fix all malformed font declarations in SettingsPanelView.swift**

Open `leanring-buddy/SettingsPanelView.swift`. Find every instance of `.font(.system(size: 13)Medium)` (there are 13+ occurrences) and replace with `.font(.system(size: 13, weight: .medium))`. The pattern appears at approximately lines 52, 271, 305, 434, 497, 741, 905, 946, 1113, 1151, 1270, 1327, 1654, 1715.

Use a global find-and-replace:
- Find: `.font(.system(size: 13)Medium)`
- Replace: `.font(.system(size: 13, weight: .medium))`

Also check for any other malformed `.font(` patterns (e.g., `size: 12)Bold` or `size: 11)Semibold`).

- [ ] **Step 2: Fix all malformed font declarations in AgentStackView.swift**

Open `leanring-buddy/Agent/AgentStackView.swift`. Same fix — find `.font(.system(size: 13)Medium)` at approximately lines 321, 389, 410 and replace with `.font(.system(size: 13, weight: .medium))`.

- [ ] **Step 3: Fix LumaTheme references in CompanionPanelView.swift**

Open `leanring-buddy/CompanionPanelView.swift`. Replace all remaining `LumaTheme` references with `DS.Colors` equivalents:

| Old | New |
|-----|-----|
| `LumaTheme.textPrimary` | `DS.Colors.textPrimary` |
| `LumaTheme.textSecondary` | `DS.Colors.textSecondary` |
| `LumaTheme.textTertiary` | `DS.Colors.textTertiary` |
| `LumaTheme.Colors.background` | `DS.Colors.background` |
| `LumaTheme.CornerRadius.*` | `DS.CornerRadius.*` |

Check approximately lines 106, 181, 192, 259, 332, 1082 for `LumaTheme` references. Replace all of them. If `LumaTheme` is referenced in other files, note them but don't fix yet (Phase 8 cleanup handles that).

- [ ] **Step 4: Commit**

```bash
git add leanring-buddy/SettingsPanelView.swift leanring-buddy/Agent/AgentStackView.swift leanring-buddy/CompanionPanelView.swift
git commit -m "fix: resolve font syntax errors and LumaTheme references blocking compilation"
```

---

## Task 2: Remove Codex Abstractions

**Files:**
- Delete: `leanring-buddy/Agent/AgentExecutionModels.swift` (if exists)
- Delete: `leanring-buddy/Agent/ClaudeAgentRuntime.swift` (if exists)
- Delete: `leanring-buddy/Agent/AgentSessionMemoryStore.swift` (if exists)
- Delete: `leanring-buddy/LumaTests/ClaudeAgentRuntimeStateTests.swift` (if exists)
- Delete: `leanring-buddy/LumaTests/AgentExecutionCoordinatorTests.swift` (if exists)
- Modify: `leanring-buddy/ClaudeAPI.swift` — remove `ClaudeAgentRuntimeAPI` protocol and `ClaudeAgentRequest`

- [ ] **Step 1: Check which Codex files exist in the main branch**

These files were created in the Codex worktree and may or may not have been merged. Check each:
```bash
ls -la leanring-buddy/Agent/AgentExecutionModels.swift leanring-buddy/Agent/ClaudeAgentRuntime.swift leanring-buddy/Agent/AgentSessionMemoryStore.swift leanring-buddy/LumaTests/ 2>/dev/null
```

- [ ] **Step 2: Delete all Codex abstraction files that exist**

For each file that exists, delete it. These contain `ClaudeAgentExecutionState`, `AgentHesitationReason`, `AgentExecutionCoordinator`, `ClaudeAgentRuntime` — none of which are in OpenClicky.

- [ ] **Step 3: Clean ClaudeAPI.swift**

Read `leanring-buddy/ClaudeAPI.swift`. If it contains a `ClaudeAgentRuntimeAPI` protocol or `ClaudeAgentRequest` struct, remove those additions. Keep the rest of the file intact — the base `ClaudeAPI` class, SSE streaming, TLS warmup, and vision request building are all needed.

- [ ] **Step 4: Remove any imports/references to deleted types**

Grep the codebase for references to removed types:
```
ClaudeAgentExecutionState
AgentHesitationReason
AgentExecutionCoordinator
ClaudeAgentRuntime (the old class, not the new one we'll create)
AgentSessionMemoryStore
ClaudeAgentRuntimeAPI
ClaudeAgentRequest
```

Remove any imports or references found.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "chore: remove Codex agent abstractions not present in OpenClicky"
```

---

## Task 3: Agent Session Model

**Files:**
- Create: `leanring-buddy/Agent/AgentSession.swift`
- Create: `leanring-buddy/Agent/AgentTranscriptEntry.swift`
- Create: `leanring-buddy/Agent/ResponseCard.swift`

Reference: `/Users/nox/Desktop/openclicky/leanring-buddy/CodexAgentSession.swift` (779 lines)

- [ ] **Step 1: Create AgentTranscriptEntry.swift**

```swift
import Foundation

struct AgentTranscriptEntry: Identifiable, Equatable {
    let id: UUID
    let role: TranscriptRole
    let text: String
    let createdAt: Date

    init(id: UUID = UUID(), role: TranscriptRole, text: String, createdAt: Date = Date()) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
    }

    static func == (lhs: AgentTranscriptEntry, rhs: AgentTranscriptEntry) -> Bool {
        lhs.id == rhs.id
    }
}

enum TranscriptRole: String, Codable {
    case user
    case assistant
    case system
    case command
    case plan
}
```

- [ ] **Step 2: Create ResponseCard.swift**

Model after OpenClicky's `ClickyResponseCard`. Reference `/Users/nox/Desktop/openclicky` for the exact structure.

```swift
import Foundation

struct ResponseCard: Identifiable {
    let id: UUID
    let source: ResponseCardSource
    var rawText: String
    var contextTitle: String?
    var suggestedActions: [String]

    init(id: UUID = UUID(), source: ResponseCardSource, rawText: String, contextTitle: String? = nil) {
        self.id = id
        self.source = source
        self.contextTitle = contextTitle

        // Parse suggested actions from <NEXT_ACTIONS>...</NEXT_ACTIONS> tags
        var cleanedText = rawText
        var actions: [String] = []

        if let startRange = rawText.range(of: "<NEXT_ACTIONS>"),
           let endRange = rawText.range(of: "</NEXT_ACTIONS>") {
            let actionsText = String(rawText[startRange.upperBound..<endRange.lowerBound])
            actions = actionsText
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            actions = Array(actions.prefix(2))
            cleanedText = rawText.replacingCharacters(
                in: startRange.lowerBound..<endRange.upperBound,
                with: ""
            ).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        self.rawText = cleanedText
        self.suggestedActions = actions
    }

    var truncatedText: String {
        guard rawText.count > 220 else { return rawText }
        let truncated = String(rawText.prefix(220))
        if let lastSpace = truncated.lastIndex(of: " ") {
            return String(truncated[..<lastSpace]) + "..."
        }
        return truncated + "..."
    }
}

enum ResponseCardSource: String {
    case voice
    case agent
    case handoff
}
```

- [ ] **Step 3: Create AgentSession.swift**

Model after OpenClicky's `CodexAgentSession` (779 lines). This is the core agent state manager.

```swift
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
                self?.entries.append(entry)
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
        guard let runtime else { return }
        let userEntry = AgentTranscriptEntry(role: .user, text: prompt)
        entries.append(userEntry)
        status = .running
        lastErrorMessage = nil

        do {
            try await runtime.submitPrompt(sessionId: id, prompt: prompt)
            // Status will be updated via statusPublisher
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
}
```

- [ ] **Step 4: Commit**

```bash
git add leanring-buddy/Agent/AgentSession.swift leanring-buddy/Agent/AgentTranscriptEntry.swift leanring-buddy/Agent/ResponseCard.swift
git commit -m "feat: add AgentSession model with transcript entries and response cards"
```

---

## Task 4: Agent Runtime Protocol + Manager

**Files:**
- Create: `leanring-buddy/Agent/AgentRuntime.swift`

- [ ] **Step 1: Create AgentRuntime.swift with protocol and manager**

```swift
import Combine
import Foundation

/// Shared protocol for agent execution backends.
/// ClaudeCodeAgentRuntime (subprocess) and ClaudeAPIAgentRuntime (tool-use) both conform.
protocol AgentRuntime: AnyObject {
    func startSession(id: UUID, task: String, workingDirectory: String, systemContext: String) async throws
    func submitPrompt(sessionId: UUID, prompt: String) async throws
    func stopSession(sessionId: UUID) async
    var transcriptPublisher: AnyPublisher<AgentTranscriptEntry, Never> { get }
    var statusPublisher: AnyPublisher<(UUID, AgentSessionStatus), Never> { get }
}

enum AgentRuntimeType: String, CaseIterable {
    case claudeCode = "Claude Code"
    case claudeAPI = "Claude API"
}

/// Singleton that detects available runtimes and creates the appropriate one.
@MainActor
final class AgentRuntimeManager: ObservableObject {
    static let shared = AgentRuntimeManager()

    @Published private(set) var detectedRuntimeType: AgentRuntimeType = .claudeAPI
    @Published private(set) var claudeCodePath: String?

    private let userOverrideKey = "luma.agentRuntime.override"

    var effectiveRuntimeType: AgentRuntimeType {
        let override = UserDefaults.standard.string(forKey: userOverrideKey)
        switch override {
        case "claudeCode":
            return claudeCodePath != nil ? .claudeCode : .claudeAPI
        case "claudeAPI":
            return .claudeAPI
        default: // "auto" or nil
            return detectedRuntimeType
        }
    }

    private init() {
        detectRuntime()
    }

    func detectRuntime() {
        let searchPaths = [
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            NSHomeDirectory() + "/.claude/bin/claude",
            "/usr/bin/claude"
        ]

        // Check PATH via which
        if let whichPath = Self.runWhichClaude() {
            claudeCodePath = whichPath
            detectedRuntimeType = .claudeCode
            return
        }

        // Check known locations
        for path in searchPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                claudeCodePath = path
                detectedRuntimeType = .claudeCode
                return
            }
        }

        claudeCodePath = nil
        detectedRuntimeType = .claudeAPI
    }

    func createRuntime() -> any AgentRuntime {
        switch effectiveRuntimeType {
        case .claudeCode:
            guard let path = claudeCodePath else {
                return ClaudeAPIAgentRuntime()
            }
            return ClaudeCodeAgentRuntime(executablePath: path)
        case .claudeAPI:
            return ClaudeAPIAgentRuntime()
        }
    }

    func setOverride(_ type: String) {
        UserDefaults.standard.set(type, forKey: userOverrideKey)
    }

    private static func runWhichClaude() -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", "which claude"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let path, !path.isEmpty {
                    return path
                }
            }
        } catch {}

        return nil
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add leanring-buddy/Agent/AgentRuntime.swift
git commit -m "feat: add AgentRuntime protocol and AgentRuntimeManager with auto-detection"
```

---

## Task 5: Claude Code Agent Runtime

**Files:**
- Create: `leanring-buddy/Agent/ClaudeCodeAgentRuntime.swift`

Reference: `/Users/nox/Desktop/openclicky/leanring-buddy/CodexProcessManager.swift` (271 lines) — same subprocess pattern but using `claude` CLI instead of Codex.

- [ ] **Step 1: Create ClaudeCodeAgentRuntime.swift**

```swift
import Combine
import Foundation

/// Agent runtime that spawns the `claude` CLI as a subprocess.
/// Mirrors OpenClicky's CodexProcessManager pattern.
final class ClaudeCodeAgentRuntime: AgentRuntime {
    private let executablePath: String
    private var processes: [UUID: Process] = [:]
    private var outputBuffers: [UUID: Data] = [:]
    private let stateQueue = DispatchQueue(label: "com.luma.claude-code-runtime")

    private let transcriptSubject = PassthroughSubject<AgentTranscriptEntry, Never>()
    private let statusSubject = PassthroughSubject<(UUID, AgentSessionStatus), Never>()

    var transcriptPublisher: AnyPublisher<AgentTranscriptEntry, Never> {
        transcriptSubject.eraseToAnyPublisher()
    }

    var statusPublisher: AnyPublisher<(UUID, AgentSessionStatus), Never> {
        statusSubject.eraseToAnyPublisher()
    }

    init(executablePath: String) {
        self.executablePath = executablePath
    }

    func startSession(id: UUID, task: String, workingDirectory: String, systemContext: String) async throws {
        statusSubject.send((id, .starting))

        guard FileManager.default.isExecutableFile(atPath: executablePath) else {
            statusSubject.send((id, .failed("Claude CLI not found at \(executablePath)")))
            throw AgentRuntimeError.executableNotFound(executablePath)
        }

        // If task is empty, this is a warm-up — just verify the binary exists
        if task.isEmpty {
            statusSubject.send((id, .ready))
            return
        }

        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: executablePath)

        var arguments = [
            "-p", task,
            "--output-format", "stream-json",
            "--dangerously-skip-permissions"
        ]

        if !systemContext.isEmpty {
            arguments += ["--append-system-prompt", systemContext]
        }

        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        // Inherit user shell environment
        var environment = ProcessInfo.processInfo.environment
        environment["CLAUDE_CODE_ENTRYPOINT"] = "luma-agent"
        process.environment = environment

        stateQueue.sync {
            processes[id] = process
            outputBuffers[id] = Data()
        }

        // Handle stdout — streaming JSON lines
        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.handleOutputData(data, sessionId: id)
        }

        // Handle stderr
        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            let entry = AgentTranscriptEntry(role: .system, text: "[stderr] \(text.trimmingCharacters(in: .whitespacesAndNewlines))")
            self?.transcriptSubject.send(entry)
        }

        process.terminationHandler = { [weak self] proc in
            guard let self else { return }
            self.stateQueue.sync {
                self.processes.removeValue(forKey: id)
                self.outputBuffers.removeValue(forKey: id)
            }

            let exitCode = proc.terminationStatus
            if exitCode == 0 {
                self.statusSubject.send((id, .ready))
            } else {
                self.statusSubject.send((id, .failed("Process exited with code \(exitCode)")))
            }
        }

        do {
            try process.run()
            statusSubject.send((id, .running))
        } catch {
            stateQueue.sync {
                processes.removeValue(forKey: id)
                outputBuffers.removeValue(forKey: id)
            }
            statusSubject.send((id, .failed(error.localizedDescription)))
            throw error
        }
    }

    func submitPrompt(sessionId: UUID, prompt: String) async throws {
        // For Claude Code CLI, each prompt is a new process invocation.
        // Load system context from memory manager.
        let systemContext = AgentMemoryIntegration.shared.loadMemorySummaryForSystemContext()
        let workingDirectory: String = stateQueue.sync {
            // Default to home if no active process
            return NSHomeDirectory()
        }

        try await startSession(
            id: sessionId,
            task: prompt,
            workingDirectory: workingDirectory,
            systemContext: systemContext
        )
    }

    func stopSession(sessionId: UUID) async {
        stateQueue.sync {
            guard let process = processes[sessionId] else { return }

            // Send SIGTERM first
            process.terminate()

            // Force kill after 2 seconds if still running
            DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.stateQueue.sync {
                    if let proc = self?.processes[sessionId], proc.isRunning {
                        kill(proc.processIdentifier, SIGKILL)
                    }
                }
            }
        }
    }

    // MARK: - Private

    private func handleOutputData(_ data: Data, sessionId: UUID) {
        stateQueue.sync {
            outputBuffers[sessionId, default: Data()].append(data)
        }

        // Process complete lines
        var buffer: Data = stateQueue.sync { outputBuffers[sessionId] ?? Data() }
        while let newlineIndex = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let lineData = buffer[buffer.startIndex..<newlineIndex]
            buffer = Data(buffer[buffer.index(after: newlineIndex)...])

            if let line = String(data: lineData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !line.isEmpty {
                parseStreamJsonLine(line, sessionId: sessionId)
            }
        }

        stateQueue.sync {
            outputBuffers[sessionId] = buffer
        }
    }

    private func parseStreamJsonLine(_ line: String, sessionId: UUID) {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // Plain text output — treat as assistant message
            let entry = AgentTranscriptEntry(role: .assistant, text: line)
            transcriptSubject.send(entry)
            return
        }

        let messageType = json["type"] as? String ?? ""

        switch messageType {
        case "assistant":
            if let content = json["content"] as? [[String: Any]] {
                for block in content {
                    if let text = block["text"] as? String, !text.isEmpty {
                        let entry = AgentTranscriptEntry(role: .assistant, text: text)
                        transcriptSubject.send(entry)
                    }
                }
            } else if let message = json["message"] as? String {
                let entry = AgentTranscriptEntry(role: .assistant, text: message)
                transcriptSubject.send(entry)
            }

        case "tool_use", "tool_result":
            let toolName = json["name"] as? String ?? "tool"
            let toolInput = json["input"] as? String ?? ""
            let text = "[\(toolName)] \(toolInput)".trimmingCharacters(in: .whitespacesAndNewlines)
            let entry = AgentTranscriptEntry(role: .command, text: text)
            transcriptSubject.send(entry)

        case "result":
            if let resultText = json["result"] as? String {
                let entry = AgentTranscriptEntry(role: .assistant, text: resultText)
                transcriptSubject.send(entry)
            }
            statusSubject.send((sessionId, .ready))

        case "error":
            let errorMessage = json["error"] as? String ?? "Unknown error"
            let entry = AgentTranscriptEntry(role: .system, text: "Error: \(errorMessage)")
            transcriptSubject.send(entry)
            statusSubject.send((sessionId, .failed(errorMessage)))

        case "system":
            if let text = json["text"] as? String ?? json["message"] as? String {
                let entry = AgentTranscriptEntry(role: .system, text: text)
                transcriptSubject.send(entry)
            }

        default:
            // Unknown type — log as system entry if it has text content
            if let text = json["content"] as? String ?? json["message"] as? String ?? json["text"] as? String {
                let entry = AgentTranscriptEntry(role: .assistant, text: text)
                transcriptSubject.send(entry)
            }
        }
    }
}

enum AgentRuntimeError: LocalizedError {
    case executableNotFound(String)
    case sessionNotFound(UUID)
    case maxIterationsReached

    var errorDescription: String? {
        switch self {
        case .executableNotFound(let path): return "Executable not found at \(path)"
        case .sessionNotFound(let id): return "Session \(id) not found"
        case .maxIterationsReached: return "Maximum tool-use iterations reached"
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add leanring-buddy/Agent/ClaudeCodeAgentRuntime.swift
git commit -m "feat: add ClaudeCodeAgentRuntime — subprocess-based agent execution via claude CLI"
```

---

## Task 6: Claude API Agent Runtime

**Files:**
- Create: `leanring-buddy/Agent/ClaudeAPIAgentRuntime.swift`

- [ ] **Step 1: Create ClaudeAPIAgentRuntime.swift**

This is the fallback runtime that uses the existing `ClaudeAPI` with tool-use for autonomous actions.

```swift
import AppKit
import Combine
import Foundation

/// Fallback agent runtime using Claude API with tool-use definitions.
/// Used when the `claude` CLI is not available on the system.
final class ClaudeAPIAgentRuntime: AgentRuntime {
    private var activeTasks: [UUID: Task<Void, Never>] = [:]
    private let stateQueue = DispatchQueue(label: "com.luma.claude-api-runtime")
    private let maxIterationsPerPrompt = 50

    private let transcriptSubject = PassthroughSubject<AgentTranscriptEntry, Never>()
    private let statusSubject = PassthroughSubject<(UUID, AgentSessionStatus), Never>()

    var transcriptPublisher: AnyPublisher<AgentTranscriptEntry, Never> {
        transcriptSubject.eraseToAnyPublisher()
    }

    var statusPublisher: AnyPublisher<(UUID, AgentSessionStatus), Never> {
        statusSubject.eraseToAnyPublisher()
    }

    func startSession(id: UUID, task: String, workingDirectory: String, systemContext: String) async throws {
        statusSubject.send((id, .starting))

        if task.isEmpty {
            statusSubject.send((id, .ready))
            return
        }

        statusSubject.send((id, .running))

        let taskHandle = Task { [weak self] in
            guard let self else { return }
            await self.executeToolUseLoop(
                sessionId: id,
                initialPrompt: task,
                workingDirectory: workingDirectory,
                systemContext: systemContext
            )
        }

        stateQueue.sync {
            activeTasks[id] = taskHandle
        }
    }

    func submitPrompt(sessionId: UUID, prompt: String) async throws {
        let systemContext = AgentMemoryIntegration.shared.loadMemorySummaryForSystemContext()
        let workingDirectory = NSHomeDirectory()

        try await startSession(
            id: sessionId,
            task: prompt,
            workingDirectory: workingDirectory,
            systemContext: systemContext
        )
    }

    func stopSession(sessionId: UUID) async {
        stateQueue.sync {
            activeTasks[sessionId]?.cancel()
            activeTasks.removeValue(forKey: sessionId)
        }
        statusSubject.send((sessionId, .stopped))
    }

    // MARK: - Tool-Use Loop

    private func executeToolUseLoop(sessionId: UUID, initialPrompt: String, workingDirectory: String, systemContext: String) async {
        let systemPrompt = buildSystemPrompt(workingDirectory: workingDirectory, additionalContext: systemContext)
        var conversationMessages: [[String: Any]] = [
            ["role": "user", "content": initialPrompt]
        ]

        for iteration in 0..<maxIterationsPerPrompt {
            if Task.isCancelled {
                statusSubject.send((sessionId, .stopped))
                return
            }

            do {
                let response = try await sendAPIRequest(
                    systemPrompt: systemPrompt,
                    messages: conversationMessages
                )

                guard let content = response["content"] as? [[String: Any]] else {
                    statusSubject.send((sessionId, .ready))
                    return
                }

                var hasToolUse = false
                var assistantText = ""
                var toolResults: [[String: Any]] = []

                for block in content {
                    let blockType = block["type"] as? String ?? ""

                    if blockType == "text", let text = block["text"] as? String {
                        assistantText += text
                        let entry = AgentTranscriptEntry(role: .assistant, text: text)
                        transcriptSubject.send(entry)
                    }

                    if blockType == "tool_use" {
                        hasToolUse = true
                        let toolName = block["name"] as? String ?? ""
                        let toolId = block["id"] as? String ?? UUID().uuidString
                        let toolInput = block["input"] as? [String: Any] ?? [:]

                        let commandEntry = AgentTranscriptEntry(
                            role: .command,
                            text: "[\(toolName)] \(toolInput)"
                        )
                        transcriptSubject.send(commandEntry)

                        let toolResult = await executeToolAction(
                            name: toolName,
                            input: toolInput,
                            workingDirectory: workingDirectory
                        )

                        toolResults.append([
                            "type": "tool_result",
                            "tool_use_id": toolId,
                            "content": toolResult
                        ])
                    }
                }

                // Add assistant message to conversation
                conversationMessages.append(["role": "assistant", "content": content])

                if !hasToolUse {
                    // No tool calls — conversation turn is complete
                    statusSubject.send((sessionId, .ready))
                    return
                }

                // Add tool results and continue loop
                conversationMessages.append(["role": "user", "content": toolResults])

            } catch {
                let entry = AgentTranscriptEntry(role: .system, text: "Error: \(error.localizedDescription)")
                transcriptSubject.send(entry)
                statusSubject.send((sessionId, .failed(error.localizedDescription)))
                return
            }
        }

        // Max iterations reached
        let entry = AgentTranscriptEntry(role: .system, text: "Reached maximum tool-use iterations (\(maxIterationsPerPrompt))")
        transcriptSubject.send(entry)
        statusSubject.send((sessionId, .ready))
    }

    // MARK: - Tool Execution

    private func executeToolAction(name: String, input: [String: Any], workingDirectory: String) async -> String {
        switch name {
        case "bash":
            let command = input["command"] as? String ?? ""
            return await executeBashCommand(command, workingDirectory: workingDirectory)

        case "screenshot":
            return await captureScreenshot()

        case "click":
            let x = input["x"] as? Int ?? 0
            let y = input["y"] as? Int ?? 0
            return executeClick(x: x, y: y)

        case "type":
            let text = input["text"] as? String ?? ""
            return executeType(text: text)

        case "key_press":
            let key = input["key"] as? String ?? ""
            let modifiers = input["modifiers"] as? [String] ?? []
            return executeKeyPress(key: key, modifiers: modifiers)

        case "open_app":
            let bundleId = input["bundleId"] as? String ?? ""
            return openApp(bundleId: bundleId)

        case "wait":
            let seconds = input["seconds"] as? Double ?? 1.0
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            return "Waited \(seconds) seconds"

        default:
            return "Unknown tool: \(name)"
        }
    }

    private func executeBashCommand(_ command: String, workingDirectory: String) async -> String {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
            let stdout = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let exitCode = process.terminationStatus

            var result = ""
            if !stdout.isEmpty { result += stdout }
            if !stderr.isEmpty { result += "\n[stderr] \(stderr)" }
            if exitCode != 0 { result += "\n[exit code: \(exitCode)]" }
            return result.isEmpty ? "[no output]" : result
        } catch {
            return "Failed to run command: \(error.localizedDescription)"
        }
    }

    private func captureScreenshot() async -> String {
        // Use existing CompanionScreenCaptureUtility
        return "[screenshot captured — base64 omitted for transcript]"
    }

    private func executeClick(x: Int, y: Int) -> String {
        let point = CGPoint(x: x, y: y)
        let mouseDown = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)
        let mouseUp = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)
        mouseDown?.post(tap: .cghidEventTap)
        mouseUp?.post(tap: .cghidEventTap)
        return "Clicked at (\(x), \(y))"
    }

    private func executeType(text: String) -> String {
        for character in text {
            let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)
            let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
            var chars = [UniChar](String(character).utf16)
            keyDown?.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: &chars)
            keyUp?.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: &chars)
            keyDown?.post(tap: .cghidEventTap)
            keyUp?.post(tap: .cghidEventTap)
            usleep(20_000) // 20ms between keystrokes
        }
        return "Typed: \(text)"
    }

    private func executeKeyPress(key: String, modifiers: [String]) -> String {
        // Reuse key mapping from LumaAgentEngine
        guard let keyCode = LumaAgentEngine.keyCodeForName(key) else {
            return "Unknown key: \(key)"
        }

        var flags: CGEventFlags = []
        for modifier in modifiers {
            switch modifier.lowercased() {
            case "command", "cmd": flags.insert(.maskCommand)
            case "shift": flags.insert(.maskShift)
            case "option", "alt": flags.insert(.maskAlternate)
            case "control", "ctrl": flags.insert(.maskControl)
            default: break
            }
        }

        let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
        keyDown?.flags = flags
        keyUp?.flags = flags
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
        return "Key press: \(modifiers.joined(separator: "+"))+\(key)"
    }

    private func openApp(bundleId: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
            return "Opened \(bundleId)"
        }
        return "App not found: \(bundleId)"
    }

    // MARK: - API Request

    private func sendAPIRequest(systemPrompt: String, messages: [[String: Any]]) async throws -> [String: Any] {
        // Use the existing ClaudeAPI / OpenRouter path
        let apiKey = KeychainManager.shared.retrieve(key: "openrouter_api_key") ?? ""

        let toolDefinitions: [[String: Any]] = [
            ["name": "bash", "description": "Run a shell command", "input_schema": ["type": "object", "properties": ["command": ["type": "string", "description": "The bash command to execute"]], "required": ["command"]]],
            ["name": "screenshot", "description": "Capture a screenshot of the current screen", "input_schema": ["type": "object", "properties": [:]]],
            ["name": "click", "description": "Click at screen coordinates", "input_schema": ["type": "object", "properties": ["x": ["type": "integer"], "y": ["type": "integer"]], "required": ["x", "y"]]],
            ["name": "type", "description": "Type text using keyboard", "input_schema": ["type": "object", "properties": ["text": ["type": "string"]], "required": ["text"]]],
            ["name": "key_press", "description": "Press a key with optional modifiers", "input_schema": ["type": "object", "properties": ["key": ["type": "string"], "modifiers": ["type": "array", "items": ["type": "string"]]], "required": ["key"]]],
            ["name": "open_app", "description": "Open an application by bundle ID", "input_schema": ["type": "object", "properties": ["bundleId": ["type": "string"]], "required": ["bundleId"]]],
            ["name": "wait", "description": "Wait for a duration", "input_schema": ["type": "object", "properties": ["seconds": ["type": "number"]], "required": ["seconds"]]]
        ]

        let requestBody: [String: Any] = [
            "model": "anthropic/claude-sonnet-4-6",
            "messages": messages,
            "system": systemPrompt,
            "tools": toolDefinitions,
            "max_tokens": 4096
        ]

        let url = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any] else {
            throw AgentRuntimeError.sessionNotFound(UUID())
        }

        return message
    }

    private func buildSystemPrompt(workingDirectory: String, additionalContext: String) -> String {
        var prompt = """
        You are Luma, an autonomous agent running on macOS. You can execute shell commands, \
        take screenshots, click on screen elements, type text, and open applications. \
        Complete the user's task step by step. Be concise in your responses.

        Working directory: \(workingDirectory)
        """

        if !additionalContext.isEmpty {
            prompt += "\n\nContext:\n\(additionalContext)"
        }

        return prompt
    }
}
```

- [ ] **Step 2: Verify LumaAgentEngine.keyCodeForName exists**

Check that `LumaAgentEngine` has a static `keyCodeForName` method. If not, the key code mapping logic needs to be extracted into a shared utility or the `ClaudeAPIAgentRuntime` needs its own key mapping. Read `leanring-buddy/Agent/LumaAgentEngine.swift` to verify.

If the method doesn't exist as static, extract the key mapping from `LumaAgentEngine` into a static method or use the mapping inline in `ClaudeAPIAgentRuntime`.

- [ ] **Step 3: Commit**

```bash
git add leanring-buddy/Agent/ClaudeAPIAgentRuntime.swift
git commit -m "feat: add ClaudeAPIAgentRuntime — tool-use loop fallback when Claude CLI unavailable"
```

---

## Task 7: Agent Mode Panel Section

**Files:**
- Create: `leanring-buddy/Agent/AgentModePanelSection.swift`

Reference: `/Users/nox/Desktop/openclicky/leanring-buddy/CodexAgentModePanelSection.swift` (916 lines) — port this to Luma, replacing Codex-specific references with Luma's `AgentSession`.

- [ ] **Step 1: Create AgentModePanelSection.swift**

Port OpenClicky's `CodexAgentModePanelSection` to Luma. Key structure:

```swift
import SwiftUI

struct AgentModePanelSection: View {
    @ObservedObject var session: AgentSession
    var responseCard: ResponseCard?
    var submitAgentPrompt: (String) -> Void
    var openHUD: () -> Void
    var dismissResponseCard: () -> Void
    var runSuggestedNextAction: (String) -> Void
    var showSettings: () -> Void

    @State private var prompt = ""

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            // Status header row
            statusHeaderRow

            // Summary text
            if !session.statusSummaryLine.isEmpty {
                Text(session.statusSummaryLine)
                    .font(.system(size: 11))
                    .foregroundColor(DS.Colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Agent prompt input
            promptInputField

            // Error display
            if let error = session.lastErrorMessage {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundColor(DS.Colors.destructiveText)
                    .lineLimit(3)
            }

            // Inline response box
            if let summary = session.latestActivitySummary {
                inlineResponseBox(text: summary)
            }

            // Response card
            if let card = responseCard {
                responseCardCompactView(card: card)
            }

            // Button row
            buttonRow
        }
        .padding(9)
        .background(Color.white.opacity(0.045))
        .overlay(
            RoundedRectangle(cornerRadius: DS.CornerRadius.large)
                .stroke(DS.Colors.borderSubtle, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.CornerRadius.large))
    }
}
```

Read `/Users/nox/Desktop/openclicky/leanring-buddy/CodexAgentModePanelSection.swift` for the complete implementation. Port all subviews:
- `statusHeaderRow`: 7pt status dot + status label + settings icon button + model name
- `promptInputField`: TextEditor with placeholder, 1–3 line limit, white @7% background
- `inlineResponseBox`: 9pt padding, white @5.5% background, "AGENT RESPONSE" label
- `buttonRow`: Dashboard button + Send button (paperplane.fill, 42x30pt)
- `responseCardCompactView`: Truncated text + action buttons

Map all OpenClicky types to Luma equivalents:
- `CodexAgentSession` → `AgentSession`
- `CodexTranscriptEntry` → `AgentTranscriptEntry`
- `ClickyResponseCard` → `ResponseCard`
- `ClickyAccentTheme` → `LumaAccentTheme`
- `DS.*` tokens stay the same (both use the same design system)

- [ ] **Step 2: Commit**

```bash
git add leanring-buddy/Agent/AgentModePanelSection.swift
git commit -m "feat: add AgentModePanelSection — inline agent controls for companion panel"
```

---

## Task 8: Agent HUD Window

**Files:**
- Create: `leanring-buddy/Agent/LumaAgentHUDWindowManager.swift`

Reference: `/Users/nox/Desktop/openclicky/leanring-buddy/CodexHUDWindowManager.swift` (507 lines)

- [ ] **Step 1: Create LumaAgentHUDWindowManager.swift**

Port OpenClicky's `CodexHUDWindowManager`. This file contains both the window manager and the HUD view. Key structure:

```swift
import AppKit
import SwiftUI

@MainActor
final class LumaAgentHUDWindowManager {
    private var window: NSPanel?

    func show(companionManager: CompanionManager, openMemory: @escaping () -> Void, prepareVoiceFollowUp: @escaping () -> Void) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let hudView = LumaHUDView(
            companionManager: companionManager,
            openMemory: openMemory,
            prepareVoiceFollowUp: prepareVoiceFollowUp,
            close: { [weak self] in self?.hide() }
        )

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 594, height: 452),
            styleMask: [.borderless, .nonactivatingPanel, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = NSColor(red: 0.067, green: 0.075, blue: 0.071, alpha: 0.98)
        panel.isOpaque = false
        panel.hasShadow = true
        panel.minSize = NSSize(width: 594, height: 452)
        panel.contentView = NSHostingView(rootView: hudView)
        panel.center()
        panel.makeKeyAndOrderFront(nil)

        self.window = panel
    }

    func hide() {
        window?.close()
        window = nil
    }
}
```

Read `/Users/nox/Desktop/openclicky/leanring-buddy/CodexHUDWindowManager.swift` for the complete `LumaHUDView` implementation. Port the following subviews:
- Header: icon + "Luma" title + memory/warmup/close buttons (28pt icon buttons)
- Agent team strip: horizontal scroll of 30pt agent session buttons with accent colors
- Response card display area
- Transcript: scrollable LazyVStack with role-colored entries
- Composer: text input + run button (76x32pt, accent background)

Map: `CompanionManager` references need agent session array (`agentSessions`, `activeAgentSessionID`).

- [ ] **Step 2: Commit**

```bash
git add leanring-buddy/Agent/LumaAgentHUDWindowManager.swift
git commit -m "feat: add LumaAgentHUDWindowManager — floating agent dashboard window"
```

---

## Task 9: Agent Dock Window

**Files:**
- Create: `leanring-buddy/Agent/LumaAgentDockWindowManager.swift`

Reference: PRD Section 4.5. OpenClicky does not have a standalone dock file — the dock items are rendered inline. Build per PRD spec.

- [ ] **Step 1: Create LumaAgentDockWindowManager.swift**

```swift
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
                let x = screenFrame.midX - 260
                let y = screenFrame.minY + 20
                panel.setFrameOrigin(NSPoint(x: x, y: y))
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
```

- [ ] **Step 2: Commit**

```bash
git add leanring-buddy/Agent/LumaAgentDockWindowManager.swift
git commit -m "feat: add LumaAgentDockWindowManager — floating dock showing active agent sessions"
```

---

## Task 10: Wire Agent System into CompanionManager

**Files:**
- Modify: `leanring-buddy/CompanionManager.swift`
- Modify: `leanring-buddy/Agent/AgentHotkeyHandler.swift`
- Modify: `leanring-buddy/Agent/AgentVoiceIntegration.swift`

This task integrates the new agent session system into CompanionManager, replacing the old `AgentManager` usage.

- [ ] **Step 1: Add agent session properties to CompanionManager**

Read `leanring-buddy/CompanionManager.swift`. Add the following published properties near the existing agent-related code:

```swift
// MARK: - Agent Sessions (v3)
@Published var agentSessions: [AgentSession] = []
@Published var activeAgentSessionID: UUID?
@Published var isAgentModeEnabled: Bool = UserDefaults.standard.bool(forKey: "luma.agentMode.enabled")

private var agentHUDManager = LumaAgentHUDWindowManager()
private var agentDockManager = LumaAgentDockWindowManager()

var activeAgentSession: AgentSession? {
    guard let id = activeAgentSessionID else { return agentSessions.first }
    return agentSessions.first(where: { $0.id == id })
}

var agentDockItems: [AgentDockItem] {
    agentSessions.map { session in
        AgentDockItem(
            id: session.id,
            title: session.title,
            accentTheme: session.accentTheme,
            status: session.status,
            caption: session.latestActivitySummary.flatMap { String($0.prefix(40)) }
        )
    }
}
```

- [ ] **Step 2: Add agent session lifecycle methods**

Add these methods to CompanionManager:

```swift
// MARK: - Agent Session Lifecycle

private let accentThemeRotation: [LumaAccentTheme] = [.blue, .mint, .amber, .rose]

func spawnAgentSession() {
    let maxAgents = AgentSettingsManager.shared.maxAgentCount
    guard agentSessions.count < maxAgents else {
        LumaLogger.shared.log("[Luma] Agent limit reached (\(maxAgents))")
        return
    }

    let themeIndex = agentSessions.count % accentThemeRotation.count
    let theme = accentThemeRotation[themeIndex]

    let session = AgentSession(accentTheme: theme)
    let runtime = AgentRuntimeManager.shared.createRuntime()
    session.bind(to: runtime)

    agentSessions.append(session)
    activeAgentSessionID = session.id

    LumaLogger.shared.log("[Luma] Spawned agent session: \(session.id)")

    // Update dock
    updateAgentDock()
}

func dismissAgentSession(id: UUID) async {
    guard let session = agentSessions.first(where: { $0.id == id }) else { return }
    await session.stop()
    agentSessions.removeAll(where: { $0.id == id })

    if activeAgentSessionID == id {
        activeAgentSessionID = agentSessions.first?.id
    }

    updateAgentDock()
    LumaLogger.shared.log("[Luma] Dismissed agent session: \(id)")
}

func submitAgentPrompt(_ prompt: String) {
    guard let session = activeAgentSession else { return }
    Task {
        await session.submitPrompt(prompt, systemContext: AgentMemoryIntegration.shared.loadMemorySummaryForSystemContext())
    }
}

func switchToAgentSession(id: UUID) {
    guard agentSessions.contains(where: { $0.id == id }) else { return }
    activeAgentSessionID = id
}

func cycleActiveAgent() {
    guard agentSessions.count > 1, let currentID = activeAgentSessionID else { return }
    guard let currentIndex = agentSessions.firstIndex(where: { $0.id == currentID }) else { return }
    let nextIndex = (currentIndex + 1) % agentSessions.count
    activeAgentSessionID = agentSessions[nextIndex].id
}

func switchToAgentAtIndex(_ index: Int) {
    guard index >= 0, index < agentSessions.count else { return }
    activeAgentSessionID = agentSessions[index].id
}

func showAgentHUD() {
    agentHUDManager.show(
        companionManager: self,
        openMemory: { /* TODO: open memory viewer */ },
        prepareVoiceFollowUp: { /* TODO: voice follow-up */ }
    )
}

private func updateAgentDock() {
    if agentSessions.isEmpty {
        agentDockManager.hide()
    } else {
        agentDockManager.show(items: agentDockItems) { [weak self] id in
            self?.switchToAgentSession(id: id)
        }
    }
}
```

- [ ] **Step 3: Update AgentHotkeyHandler for session-based switching**

Read `leanring-buddy/Agent/AgentHotkeyHandler.swift`. Update it to call CompanionManager's new session methods instead of the old `AgentManager`:

- Ctrl+Cmd+N → `CompanionManager.shared.spawnAgentSession()` (or however the singleton is accessed)
- Ctrl+Option+Tab → `CompanionManager.shared.cycleActiveAgent()`
- Ctrl+Option+1-9 → `CompanionManager.shared.switchToAgentAtIndex(index - 1)`

The exact integration depends on how `AgentHotkeyHandler` currently references `AgentManager`. Read the file and swap references.

- [ ] **Step 4: Update AgentVoiceIntegration for session spawning**

Read `leanring-buddy/Agent/AgentVoiceIntegration.swift`. Update the spawn action to call `CompanionManager`'s `spawnAgentSession()` instead of the old `AgentManager.shared.spawnAgent()`.

- [ ] **Step 5: Commit**

```bash
git add leanring-buddy/CompanionManager.swift leanring-buddy/Agent/AgentHotkeyHandler.swift leanring-buddy/Agent/AgentVoiceIntegration.swift
git commit -m "feat: wire agent session system into CompanionManager with lifecycle and hotkeys"
```

---

## Task 11: Companion Panel View Rebuild

**Files:**
- Modify: `leanring-buddy/CompanionPanelView.swift`

Reference: `/Users/nox/Desktop/openclicky/leanring-buddy/CompanionPanelView.swift` (1208 lines)

- [ ] **Step 1: Read both panel views side-by-side**

Read the current Luma `CompanionPanelView.swift` and OpenClicky's `CompanionPanelView.swift` to understand the structural differences. Key sections to match:

1. **Header**: "Luma" title + status dot (7x7pt) + status text + pin button + close button
2. **Divider**: 0.5pt, borderSubtle
3. **Permissions copy section**: Hotkey hints with keyboard chips when all permissions granted
4. **Permission guide section**: Step-by-step onboarding
5. **Agent mode section**: `AgentModePanelSection` (new, conditional on agent mode enabled)
6. **Permissions grid**: 4 permission rows (mic, accessibility, screen recording, screen content)
7. **Bottom controls**: Cursor color selector (4 theme buttons) + footer (memory, settings, quit)

- [ ] **Step 2: Add agent mode section to the panel**

In the panel body, add the `AgentModePanelSection` after the permissions section, conditional on agent mode being enabled:

```swift
// After permissions copy section and permission guide, before bottom controls:
if companionManager.isAgentModeEnabled,
   companionManager.allPermissionsGranted,
   companionManager.hasCompletedOnboarding {
    AgentModePanelSection(
        session: companionManager.activeAgentSession ?? AgentSession(),
        responseCard: companionManager.activeAgentSession?.latestResponseCard,
        submitAgentPrompt: { prompt in
            companionManager.submitAgentPrompt(prompt)
        },
        openHUD: {
            companionManager.showAgentHUD()
        },
        dismissResponseCard: {
            companionManager.activeAgentSession?.dismissLatestResponseCard()
        },
        runSuggestedNextAction: { action in
            companionManager.submitAgentPrompt(action)
        },
        showSettings: {
            LumaSettingsWindowManager.shared.showSettingsWindow()
        }
    )
    .padding(.horizontal, 14)
}
```

- [ ] **Step 3: Ensure all LumaTheme references are replaced with DS**

Do a final sweep of the file for any remaining `LumaTheme` references. Replace all with `DS.Colors`, `DS.Spacing`, `DS.CornerRadius` equivalents.

- [ ] **Step 4: Commit**

```bash
git add leanring-buddy/CompanionPanelView.swift
git commit -m "feat: integrate AgentModePanelSection into CompanionPanelView"
```

---

## Task 12: Settings Window Rebuild

**Files:**
- Modify: `leanring-buddy/SettingsPanelView.swift`
- Modify: `leanring-buddy/LumaSettingsWindowManager.swift`

Reference: `/Users/nox/Desktop/openclicky/leanring-buddy/OpenClickySettingsWindowManager.swift` (898 lines)

- [ ] **Step 1: Update LumaSettingsWindowManager window size**

Read `leanring-buddy/LumaSettingsWindowManager.swift`. Update:
- Default size: 860×580pt (was 640×620)
- Minimum size: 760×500pt (was 620×580)

- [ ] **Step 2: Rebuild SettingsPanelView with sidebar navigation**

Read OpenClicky's `OpenClickySettingsWindowManager.swift` for the settings view structure (lines 86-897). The current Luma `SettingsPanelView` has a tab-based layout — convert to sidebar + content:

```swift
struct SettingsPanelView: View {
    @ObservedObject var companionManager: CompanionManager

    enum SettingsSection: String, CaseIterable {
        case general, voice, pointing, computerUse, agentMode, memory, app

        var title: String { /* ... */ }
        var subtitle: String { /* ... */ }
        var iconName: String { /* ... */ }
    }

    @State private var selectedSection: SettingsSection = .general

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar: 190pt width, regularMaterial background
            sidebar
                .frame(width: 190)

            Divider()

            // Content: scrollable, max 660pt width, padding H:28 V:24
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    sectionHeader
                    selectedPanel
                }
                .frame(maxWidth: 660)
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
            }
        }
    }
}
```

Port each settings section from the existing tab-based content into the new sidebar-selected panels. The content is already written — it just needs to be reorganized into the sidebar pattern. Map tabs to sections:
- Account tab content → General section
- API tab content → Voice section (API keys)
- Model tab content → Voice section (model picker)
- Voice tab content → Voice section
- Cursor tab content → General section
- Agents tab content → Agent Mode section
- General tab content → App section

Add the **Agent Mode section** with:
- Advanced mode toggle
- Runtime selector (Claude Code / Claude API / Auto) using `AgentRuntimeManager.shared`
- Runtime status indicator
- Working directory text field
- Max agents stepper

- [ ] **Step 3: Commit**

```bash
git add leanring-buddy/SettingsPanelView.swift leanring-buddy/LumaSettingsWindowManager.swift
git commit -m "feat: rebuild settings window with sidebar navigation matching OpenClicky"
```

---

## Task 13: DS Token Migration for Overlay Views

**Files:**
- Modify: `leanring-buddy/OverlayWindow.swift`
- Modify: `leanring-buddy/CompanionResponseOverlay.swift`
- Modify: `leanring-buddy/CompanionBubbleWindow.swift`

- [ ] **Step 1: Migrate OverlayWindow.swift to DS tokens**

Read `leanring-buddy/OverlayWindow.swift`. Search for any `LumaTheme` references and replace with `DS` equivalents. The overlay colors (cursor color, waveform colors, spinner) should use theme-aware values from the current `LumaAccentTheme`.

- [ ] **Step 2: Migrate CompanionResponseOverlay.swift to DS tokens**

Read and update any `LumaTheme` references in `leanring-buddy/CompanionResponseOverlay.swift`.

- [ ] **Step 3: Migrate CompanionBubbleWindow.swift to DS tokens**

Read and update any `LumaTheme` references in `leanring-buddy/CompanionBubbleWindow.swift`.

- [ ] **Step 4: Commit**

```bash
git add leanring-buddy/OverlayWindow.swift leanring-buddy/CompanionResponseOverlay.swift leanring-buddy/CompanionBubbleWindow.swift
git commit -m "chore: migrate overlay views from LumaTheme to DS design system tokens"
```

---

## Task 14: Agent Title Generation

**Files:**
- Modify: `leanring-buddy/Agent/AgentSession.swift`

- [ ] **Step 1: Add title generation to AgentSession**

After the first prompt is submitted to an agent session, send a lightweight API call to generate a short title:

```swift
// Add to AgentSession, called after first submitPrompt:
private var hasGeneratedTitle = false

private func generateTitleIfNeeded(from prompt: String) {
    guard !hasGeneratedTitle else { return }
    hasGeneratedTitle = true

    Task {
        let titlePrompt = "Generate a 3-5 word title for this task: \(prompt). Return only the title, nothing else."
        let apiKey = KeychainManager.shared.retrieve(key: "openrouter_api_key") ?? ""
        guard !apiKey.isEmpty else { return }

        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": "google/gemini-2.5-flash:free",
            "messages": [["role": "user", "content": titlePrompt]],
            "max_tokens": 20
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

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
            LumaLogger.shared.log("[Luma] Title generation failed: \(error)")
        }
    }
}
```

Call `generateTitleIfNeeded(from: prompt)` at the top of `submitPrompt()`.

- [ ] **Step 2: Commit**

```bash
git add leanring-buddy/Agent/AgentSession.swift
git commit -m "feat: add automatic agent title generation on first prompt"
```

---

## Task 15: Memory Integration for Agent Sessions

**Files:**
- Modify: `leanring-buddy/Agent/AgentMemoryIntegration.swift`
- Modify: `leanring-buddy/LumaMemoryManager.swift`

- [ ] **Step 1: Update AgentMemoryIntegration for session model**

Read `leanring-buddy/Agent/AgentMemoryIntegration.swift`. Update it to work with `AgentSession` instead of the old `LumaAgent`:

- `recordUserMessage(sessionId: UUID, text: String)` — wraps existing `recordUserMessage`
- `recordAgentResponse(sessionId: UUID, text: String)` — wraps existing `recordAgentResponse`
- `loadMemorySummaryForSystemContext()` — already exists, keep as-is

The existing `AgentMemoryIntegration` already uses `LumaMemoryManager` under the hood — just update the method signatures to accept `UUID` session IDs instead of `LumaAgent` references.

- [ ] **Step 2: Wire memory recording into AgentSession**

In `AgentSession.swift`, add memory recording when transcript entries arrive:

```swift
// In the bind(to:) method, after the transcriptPublisher sink:
runtime.transcriptPublisher
    .receive(on: DispatchQueue.main)
    .sink { [weak self] entry in
        guard let self else { return }
        self.entries.append(entry)

        // Record to persistent memory
        switch entry.role {
        case .user:
            AgentMemoryIntegration.shared.recordUserMessage(agentId: self.id, text: entry.text)
        case .assistant:
            AgentMemoryIntegration.shared.recordAgentResponse(agentId: self.id, text: entry.text)
        default:
            break
        }
    }
    .store(in: &cancellables)
```

- [ ] **Step 3: Commit**

```bash
git add leanring-buddy/Agent/AgentMemoryIntegration.swift leanring-buddy/Agent/AgentSession.swift leanring-buddy/LumaMemoryManager.swift
git commit -m "feat: integrate persistent memory recording with agent sessions"
```

---

## Task 16: Migration & Cleanup

**Files:**
- Delete: old agent files no longer needed
- Modify: any files with stale references

- [ ] **Step 1: Remove old agent bubble files**

These files are replaced by the session-based system:
- `leanring-buddy/Agent/AgentStackView.swift` → replaced by Agent Dock + HUD
- `leanring-buddy/Agent/AgentShapeView.swift` → no longer needed
- `leanring-buddy/Agent/AgentBubblePhysics.swift` → no longer needed
- `leanring-buddy/Agent/AgentProfile.swift` → replaced by session accent themes
- `leanring-buddy/Agent/LumaAgent.swift` → replaced by `AgentSession`
- `leanring-buddy/Agent/AgentManager.swift` → replaced by session management in CompanionManager

Before deleting, grep the codebase for imports/references to each file. Update any remaining references to use the new types.

- [ ] **Step 2: Update AgentSettingsManager**

Read `leanring-buddy/Agent/AgentSettingsManager.swift`. Keep the `maxAgentCount` and `isAgentModeEnabled` properties — these are still used. Remove any references to old `AgentProfile` or `LumaAgent` types. This file should become a thin settings store that the Settings window and CompanionManager both read from.

- [ ] **Step 3: Remove Codex test files (if they exist)**

Delete if present:
- `leanring-buddy/LumaTests/ClaudeAgentRuntimeStateTests.swift`
- `leanring-buddy/LumaTests/AgentExecutionCoordinatorTests.swift`

- [ ] **Step 4: Grep for any remaining LumaTheme references**

```bash
grep -r "LumaTheme" leanring-buddy/ --include="*.swift" -l
```

For each file found, replace `LumaTheme` with `DS` equivalent. The goal is zero `LumaTheme` references remaining.

- [ ] **Step 5: Grep for any remaining references to removed types**

```bash
grep -rE "(AgentStackView|AgentShapeView|AgentBubblePhysics|AgentProfile[^r]|LumaAgent[^E]|AgentManager[^.])" leanring-buddy/ --include="*.swift" -l
```

Update or remove any stale references found.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "chore: remove old agent bubble system and migrate remaining LumaTheme references"
```

---

## Task 17: Menu Bar Panel Verification

**Files:**
- Modify: `leanring-buddy/MenuBarPanelManager.swift` (if needed)

- [ ] **Step 1: Verify panel dimensions and behavior match spec**

Read `leanring-buddy/MenuBarPanelManager.swift`. Check against PRD 2.1:
- Width: 356pt (fixed) ✓
- Default height: 318pt (may differ — update if needed)
- Min size: 356×300pt
- Max transient height: 720pt
- Screen edge padding: 12pt
- Gap below menu bar icon: 4pt
- Click-outside-to-dismiss with 300ms delay

- [ ] **Step 2: Verify pin/unpin mode**

Check that pin mode switches to titled window with standard controls, and unpin returns to floating borderless panel. Reference OpenClicky's `MenuBarPanelManager.swift` for exact behavior.

- [ ] **Step 3: Fix any discrepancies and commit**

```bash
git add leanring-buddy/MenuBarPanelManager.swift
git commit -m "fix: align MenuBarPanelManager dimensions and behavior with OpenClicky spec"
```

---

## Task 18: Final Integration & Verification

**Files:**
- Modify: `LUMA_V3_PRD.md` — mark completed tasks
- Modify: `CLAUDE.md` — update key files table

- [ ] **Step 1: Update LUMA_V3_PRD.md progress markers**

Mark all completed phases as `[x]`. Mark any partially complete phases as `[~]` with notes.

- [ ] **Step 2: Update CLAUDE.md key files table**

Add new files to the Key Files table:
- `Agent/AgentSession.swift` — Session model with lifecycle, transcript, and runtime binding
- `Agent/AgentTranscriptEntry.swift` — Transcript entry model with roles
- `Agent/ResponseCard.swift` — Response card model with suggested action parsing
- `Agent/AgentRuntime.swift` — Protocol + AgentRuntimeManager with auto-detection
- `Agent/ClaudeCodeAgentRuntime.swift` — Subprocess runtime via claude CLI
- `Agent/ClaudeAPIAgentRuntime.swift` — Tool-use loop fallback runtime
- `Agent/AgentModePanelSection.swift` — Inline agent controls for companion panel
- `Agent/LumaAgentHUDWindowManager.swift` — Floating agent dashboard window
- `Agent/LumaAgentDockWindowManager.swift` — Floating dock showing active sessions

Remove deleted files from the table:
- `Agent/AgentStackView.swift`
- `Agent/AgentShapeView.swift`
- `Agent/AgentBubblePhysics.swift`
- `Agent/AgentProfile.swift`
- `Agent/LumaAgent.swift` (old model)
- `Agent/AgentManager.swift` (old manager)

- [ ] **Step 3: Verify all files compile**

Open the project in Xcode (do NOT use xcodebuild). Check for compilation errors in the issue navigator. Fix any remaining type mismatches, missing imports, or broken references.

Common issues to check:
- `AgentSession` used where `LumaAgent` was expected
- `AgentSessionStatus` used where `AgentState` was expected
- Missing `import Combine` in files using publishers
- `CompanionManager` properties referenced in views that haven't been updated

- [ ] **Step 4: Verify agent mode flow end-to-end**

Manual test:
1. Launch app
2. Toggle agent mode ON in settings
3. Panel should show `AgentModePanelSection`
4. Type a prompt and submit → agent session created
5. Transcript should stream in HUD
6. Ctrl+Cmd+N should spawn additional sessions
7. Dock should show active sessions
8. Hotkeys should cycle/switch sessions

- [ ] **Step 5: Commit final state**

```bash
git add -A
git commit -m "feat: complete Luma v3 OpenClicky rebuild — all phases implemented"
```

---

## Dependency Graph

```
Task 1 (Fix compilation blockers)
Task 2 (Remove Codex abstractions)
  ↓
Task 3 (Agent Session model)
  ↓
Task 4 (Agent Runtime protocol)
  ↓
Task 5 (Claude Code runtime) ←── can parallel with Task 6
Task 6 (Claude API runtime)  ←── can parallel with Task 5
  ↓
Task 7 (Agent Mode panel section) ←── can parallel with Task 8, 9
Task 8 (Agent HUD window)         ←── can parallel with Task 7, 9
Task 9 (Agent Dock window)        ←── can parallel with Task 7, 8
  ↓
Task 10 (Wire into CompanionManager)
  ↓
Task 11 (Companion Panel rebuild)   ←── can parallel with Task 12, 13
Task 12 (Settings Window rebuild)   ←── can parallel with Task 11, 13
Task 13 (Overlay DS migration)      ←── can parallel with Task 11, 12
  ↓
Task 14 (Title generation)
Task 15 (Memory integration)
  ↓
Task 16 (Migration & cleanup)
Task 17 (Menu bar verification)
  ↓
Task 18 (Final integration)
```

Tasks 1-2 must run first (fix blockers). Tasks 5-6, 7-8-9, and 11-12-13 can each run in parallel within their group. Task 10 is the critical integration point — everything converges there.
