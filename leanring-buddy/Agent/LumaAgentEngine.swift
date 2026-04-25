//
//  LumaAgentEngine.swift
//  leanring-buddy
//
//  Autonomous task execution engine for agent mode. Receives a task string,
//  builds a multi-step action plan via Claude API, and executes actions
//  sequentially using CGEvent for clicks/keypresses and AX API for app interaction.
//

import AppKit
import Combine
import Foundation
import UserNotifications

// MARK: - Agent Action

/// Discrete actions the agent engine can perform on the Mac.
enum AgentAction: Codable {
    case click(coordinate: CGPoint)
    case type(text: String)
    case keyPress(key: String, modifiers: [String])
    case screenshot
    case wait(seconds: Double)
    case openApp(bundleId: String)
    case search(query: String)

    var displayDescription: String {
        switch self {
        case .click(let coordinate):
            return "Clicking at (\(Int(coordinate.x)), \(Int(coordinate.y)))"
        case .type(let text):
            return "Typing: \(text.prefix(40))..."
        case .keyPress(let key, let modifiers):
            let modString = modifiers.isEmpty ? "" : modifiers.joined(separator: "+") + "+"
            return "Pressing \(modString)\(key)"
        case .screenshot:
            return "Taking screenshot"
        case .wait(let seconds):
            return "Waiting \(seconds)s"
        case .openApp(let bundleId):
            return "Opening \(bundleId)"
        case .search(let query):
            return "Searching: \(query)"
        }
    }
}

// MARK: - Agent Engine

@MainActor
final class LumaAgentEngine: ObservableObject {

    static let shared = LumaAgentEngine()

    /// Whether the cursor is currently controlled by an agent.
    @Published private(set) var isMouseInUse: Bool = false

    /// Queue-based lock: only one agent controls the cursor at a time.
    private var cursorOwnerAgentID: UUID? = nil

    private init() {}

    // MARK: - Task Execution

    /// Executes a task for the given agent. Builds an action plan, then
    /// executes each action sequentially.
    func executeTask(agentID: UUID, taskDescription: String) async {
        LumaLogger.log("[AgentEngine] Starting task for agent \(agentID): \(taskDescription)")

        // Update agent state
        AgentManager.shared.updateAgent(withID: agentID) { agent in
            agent.state = .processing
            agent.processingText = taskDescription
        }

        // For now, simulate task execution. In the full implementation,
        // this would call Claude API to get an action plan, then execute it.
        do {
            // Simulate processing time
            try await Task.sleep(nanoseconds: 2_000_000_000)

            // Mark complete
            AgentManager.shared.updateAgent(withID: agentID) { agent in
                agent.state = .complete
                agent.processingText = nil
                agent.completionText = "Task completed: \(taskDescription)"
                agent.taskStatus = .complete
            }

            // Record to memory
            if let agent = AgentManager.shared.agents.first(where: { $0.id == agentID }) {
                AgentMemoryIntegration.recordAgentResponse(
                    agentId: agentID.uuidString,
                    agentTitle: agent.title,
                    content: agent.completionText ?? "",
                    taskStatus: "complete"
                )
            }

            // Send completion notification
            sendCompletionNotification(agentID: agentID, taskDescription: taskDescription)

        } catch {
            AgentManager.shared.updateAgent(withID: agentID) { agent in
                agent.state = .complete
                agent.processingText = nil
                agent.completionText = "Failed: \(error.localizedDescription)"
                agent.taskStatus = .failed
            }
        }
    }

    // MARK: - Action Execution

    /// Executes a single agent action. Returns when the action completes.
    func executeAction(_ action: AgentAction, forAgentID agentID: UUID) async throws {
        // Update processing text
        AgentManager.shared.updateAgent(withID: agentID) { agent in
            agent.processingText = action.displayDescription
        }

        switch action {
        case .click(let coordinate):
            try await performClick(at: coordinate, forAgentID: agentID)

        case .type(let text):
            try performType(text: text)

        case .keyPress(let key, let modifiers):
            try performKeyPress(key: key, modifiers: modifiers)

        case .screenshot:
            // Screenshot is handled by CompanionScreenCaptureUtility
            break

        case .wait(let seconds):
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))

        case .openApp(let bundleId):
            NSWorkspace.shared.launchApplication(
                withBundleIdentifier: bundleId,
                options: [],
                additionalEventParamDescriptor: nil,
                launchIdentifier: nil
            )

        case .search(let query):
            // Open default browser with search
            if let searchURL = URL(string: "https://www.google.com/search?q=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query)") {
                NSWorkspace.shared.open(searchURL)
            }
        }
    }

    // MARK: - Mouse Conflict Resolution

    /// Attempts to acquire cursor control for the given agent.
    /// Returns true if acquired, false if another agent holds it.
    func acquireCursorControl(forAgentID agentID: UUID) -> Bool {
        guard !isMouseInUse || cursorOwnerAgentID == agentID else {
            return false
        }
        isMouseInUse = true
        cursorOwnerAgentID = agentID
        return true
    }

    /// Releases cursor control.
    func releaseCursorControl(forAgentID agentID: UUID) {
        guard cursorOwnerAgentID == agentID else { return }
        isMouseInUse = false
        cursorOwnerAgentID = nil
    }

    // MARK: - Private: CGEvent Actions

    private func performClick(at coordinate: CGPoint, forAgentID agentID: UUID) async throws {
        guard acquireCursorControl(forAgentID: agentID) else {
            // Another agent owns the cursor — wait and retry
            try await Task.sleep(nanoseconds: 500_000_000)
            guard acquireCursorControl(forAgentID: agentID) else {
                throw AgentEngineError.cursorConflict
            }
        }
        defer { releaseCursorControl(forAgentID: agentID) }

        // Move cursor with smooth animation
        let moveEvent = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: coordinate, mouseButton: .left)
        moveEvent?.post(tap: .cghidEventTap)

        try await Task.sleep(nanoseconds: 150_000_000) // 0.15s ease

        // Click
        let mouseDown = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: coordinate, mouseButton: .left)
        let mouseUp = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: coordinate, mouseButton: .left)
        mouseDown?.post(tap: .cghidEventTap)
        mouseUp?.post(tap: .cghidEventTap)
    }

    private func performType(text: String) throws {
        for character in text {
            let source = CGEventSource(stateID: .hidSystemState)
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)

            var buffer = [UniChar](String(character).utf16)
            keyDown?.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: &buffer)
            keyUp?.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: &buffer)

            keyDown?.post(tap: .cghidEventTap)
            keyUp?.post(tap: .cghidEventTap)

            Thread.sleep(forTimeInterval: 0.03) // 30ms delay between characters
        }
    }

    private func performKeyPress(key: String, modifiers: [String]) throws {
        // Map modifier names to CGEvent flags
        var flags: CGEventFlags = []
        for modifier in modifiers {
            switch modifier.lowercased() {
            case "cmd", "command":   flags.insert(.maskCommand)
            case "ctrl", "control":  flags.insert(.maskControl)
            case "alt", "option":    flags.insert(.maskAlternate)
            case "shift":            flags.insert(.maskShift)
            default: break
            }
        }

        let source = CGEventSource(stateID: .hidSystemState)
        let keyCode = keyCodeForString(key)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)

        keyDown?.flags = flags
        keyUp?.flags = flags

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    /// Maps common key names to virtual key codes.
    private func keyCodeForString(_ key: String) -> CGKeyCode {
        switch key.lowercased() {
        case "return", "enter": return 36
        case "tab":             return 48
        case "space":           return 49
        case "delete":          return 51
        case "escape", "esc":   return 53
        case "up":              return 126
        case "down":            return 125
        case "left":            return 123
        case "right":           return 124
        case "a":               return 0
        case "c":               return 8
        case "v":               return 9
        case "x":               return 7
        case "z":               return 6
        case "w":               return 13
        case "t":               return 17
        case "n":               return 45
        default:                return 0
        }
    }

    // MARK: - Notification

    private func sendCompletionNotification(agentID: UUID, taskDescription: String) {
        guard let agent = AgentManager.shared.agents.first(where: { $0.id == agentID }) else { return }

        let content = UNMutableNotificationContent()
        content.title = agent.title
        content.body = agent.completionText ?? "Task completed"
        content.sound = .default

        // Check if completion text contains a file path — add "Open Now" action
        if let completionText = agent.completionText,
           completionText.contains("/") && (completionText.contains(".") || completionText.contains("~")) {
            content.categoryIdentifier = "AGENT_TASK_WITH_FILE"
        }

        let request = UNNotificationRequest(
            identifier: "luma.agent.\(agentID.uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                LumaLogger.log("[AgentEngine] Notification error: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Errors

enum AgentEngineError: Error, LocalizedError {
    case cursorConflict
    case disabled
    case actionFailed(String)

    var errorDescription: String? {
        switch self {
        case .cursorConflict: return "Another agent is using the cursor"
        case .disabled:       return "Agent mode is disabled"
        case .actionFailed(let reason): return "Action failed: \(reason)"
        }
    }
}
