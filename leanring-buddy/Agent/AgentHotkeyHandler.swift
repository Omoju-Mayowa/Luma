//
//  AgentHotkeyHandler.swift
//  leanring-buddy
//
//  Registers global NSEvent monitors for agent hotkeys:
//  - Ctrl+Cmd: Spawn new agent
//  - Ctrl+Option+1..9: Switch focus to agent at index
//  - Ctrl+Option+Tab: Cycle to next agent
//

import AppKit

@MainActor
final class AgentHotkeyHandler {

    static let shared = AgentHotkeyHandler()

    private var localMonitor: Any?
    private var globalMonitor: Any?

    private init() {}

    /// Starts listening for agent-related hotkeys.
    /// Call once during app startup (e.g. in CompanionManager.start()).
    func startMonitoring() {
        guard localMonitor == nil else { return }

        // Local monitor for when the app is active
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.handleKeyEvent(event) == true {
                return nil  // Consumed
            }
            return event
        }

        // Global monitor for when the app is in the background
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
        }

        LumaLogger.log("[AgentHotkeys] Monitoring started")
    }

    func stopMonitoring() {
        if let localMonitor = localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        if let globalMonitor = globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
    }

    // MARK: - Key Event Handling

    /// Returns true if the event was consumed (matched an agent hotkey).
    @discardableResult
    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Ctrl+Cmd → Spawn new agent
        if flags == [.control, .command] && event.keyCode == 0 /* placeholder */ {
            // Use a specific key combo: Ctrl+Cmd+N (keyCode 45 = N)
        }
        if flags == [.control, .command] && event.charactersIgnoringModifiers == "n" {
            AgentManager.shared.spawnAgent()
            return true
        }

        // Ctrl+Option+Tab → Cycle to next agent
        if flags == [.control, .option] && event.keyCode == 48 { // Tab key
            cycleToNextAgent()
            return true
        }

        // Ctrl+Option+1 through Ctrl+Option+9 → Switch to agent at index
        if flags == [.control, .option],
           let characters = event.charactersIgnoringModifiers,
           let digit = characters.first,
           digit >= "1" && digit <= "9" {
            let agentIndex = Int(String(digit))! - 1
            switchToAgent(atIndex: agentIndex)
            return true
        }

        return false
    }

    // MARK: - Agent Navigation

    private func cycleToNextAgent() {
        let agents = AgentManager.shared.agents
        guard !agents.isEmpty else { return }

        if let currentExpandedID = AgentManager.shared.expandedAgentID,
           let currentIndex = agents.firstIndex(where: { $0.id == currentExpandedID }) {
            // Cycle to next
            let nextIndex = (currentIndex + 1) % agents.count
            AgentManager.shared.expandAgent(withID: agents[nextIndex].id)
        } else {
            // Nothing expanded — expand first agent
            AgentManager.shared.expandAgent(withID: agents[0].id)
        }
    }

    private func switchToAgent(atIndex index: Int) {
        guard let agent = AgentManager.shared.agent(atIndex: index) else { return }

        // Collapse current, expand target
        AgentManager.shared.expandAgent(withID: agent.id)
    }
}
