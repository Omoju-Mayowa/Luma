//
//  ClaudeAPIAgentRuntime.swift
//  leanring-buddy
//
//  Fallback agent runtime using Claude API with tool-use definitions.
//  Used when the `claude` CLI is not available on the system.
//  Implements an iterative tool-use loop: send → tool_use → execute → tool_result → repeat.
//

import AppKit
import Combine
import Foundation

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
        let workingDirectory = UserDefaults.standard.string(forKey: "luma.agent.workingDirectory") ?? NSHomeDirectory()

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

        for _ in 0..<maxIterationsPerPrompt {
            if Task.isCancelled {
                statusSubject.send((sessionId, .stopped))
                return
            }

            do {
                let responseMessage = try await sendAPIRequest(
                    systemPrompt: systemPrompt,
                    messages: conversationMessages
                )

                guard let content = responseMessage["content"] as? [[String: Any]] else {
                    statusSubject.send((sessionId, .ready))
                    return
                }

                var hasToolUse = false
                var toolResults: [[String: Any]] = []

                for block in content {
                    let blockType = block["type"] as? String ?? ""

                    if blockType == "text", let text = block["text"] as? String, !text.isEmpty {
                        transcriptSubject.send(AgentTranscriptEntry(role: .assistant, text: text))
                    }

                    if blockType == "tool_use" {
                        hasToolUse = true
                        let toolName = block["name"] as? String ?? ""
                        let toolId = block["id"] as? String ?? UUID().uuidString
                        let toolInput = block["input"] as? [String: Any] ?? [:]

                        transcriptSubject.send(AgentTranscriptEntry(
                            role: .command,
                            text: "[\(toolName)] \(toolInput)"
                        ))

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

                conversationMessages.append(["role": "assistant", "content": content])

                if !hasToolUse {
                    statusSubject.send((sessionId, .ready))
                    return
                }

                conversationMessages.append(["role": "user", "content": toolResults])

            } catch {
                transcriptSubject.send(AgentTranscriptEntry(role: .system, text: "Error: \(error.localizedDescription)"))
                statusSubject.send((sessionId, .failed(error.localizedDescription)))
                return
            }
        }

        transcriptSubject.send(AgentTranscriptEntry(
            role: .system,
            text: "Reached maximum tool-use iterations (\(maxIterationsPerPrompt))"
        ))
        statusSubject.send((sessionId, .ready))
    }

    // MARK: - Tool Execution

    private func executeToolAction(name: String, input: [String: Any], workingDirectory: String) async -> String {
        switch name {
        case "bash":
            let command = input["command"] as? String ?? ""
            return await executeBashCommand(command, workingDirectory: workingDirectory)

        case "screenshot":
            return "[screenshot captured]"

        case "click":
            let x = input["x"] as? Int ?? 0
            let y = input["y"] as? Int ?? 0
            return executeClick(x: x, y: y)

        case "type":
            let text = input["text"] as? String ?? ""
            return executeTypeText(text)

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

    private func executeClick(x: Int, y: Int) -> String {
        let point = CGPoint(x: x, y: y)
        let mouseDown = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)
        let mouseUp = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)
        mouseDown?.post(tap: .cghidEventTap)
        mouseUp?.post(tap: .cghidEventTap)
        return "Clicked at (\(x), \(y))"
    }

    private func executeTypeText(_ text: String) -> String {
        for character in text {
            let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)
            let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
            var chars = [UniChar](String(character).utf16)
            keyDown?.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: &chars)
            keyUp?.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: &chars)
            keyDown?.post(tap: .cghidEventTap)
            keyUp?.post(tap: .cghidEventTap)
            usleep(20_000)
        }
        return "Typed: \(text)"
    }

    private func executeKeyPress(key: String, modifiers: [String]) -> String {
        let keyCode = keyCodeForName(key)

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

    private func keyCodeForName(_ key: String) -> CGKeyCode {
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

    private func openApp(bundleId: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.openApplication(at: url, configuration: config)
            return "Opened \(bundleId)"
        }
        return "App not found: \(bundleId)"
    }

    // MARK: - API Request

    private func sendAPIRequest(systemPrompt: String, messages: [[String: Any]]) async throws -> [String: Any] {
        guard let apiKey = ProfileManager.shared.loadActiveAPIKey(), !apiKey.isEmpty else {
            throw AgentRuntimeError.executableNotFound("No API key configured")
        }

        let toolDefinitions: [[String: Any]] = [
            ["name": "bash", "description": "Run a shell command and return stdout/stderr",
             "input_schema": ["type": "object", "properties": ["command": ["type": "string", "description": "The bash command to execute"]], "required": ["command"]]],
            ["name": "screenshot", "description": "Capture a screenshot of the current screen",
             "input_schema": ["type": "object", "properties": [String: Any]()]],
            ["name": "click", "description": "Click at screen coordinates",
             "input_schema": ["type": "object", "properties": ["x": ["type": "integer"], "y": ["type": "integer"]], "required": ["x", "y"]]],
            ["name": "type", "description": "Type text using keyboard input",
             "input_schema": ["type": "object", "properties": ["text": ["type": "string"]], "required": ["text"]]],
            ["name": "key_press", "description": "Press a key with optional modifiers",
             "input_schema": ["type": "object", "properties": ["key": ["type": "string"], "modifiers": ["type": "array", "items": ["type": "string"]]], "required": ["key"]]],
            ["name": "open_app", "description": "Open an application by bundle ID",
             "input_schema": ["type": "object", "properties": ["bundleId": ["type": "string"]], "required": ["bundleId"]]],
            ["name": "wait", "description": "Wait for a specified duration in seconds",
             "input_schema": ["type": "object", "properties": ["seconds": ["type": "number"]], "required": ["seconds"]]]
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
