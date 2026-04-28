# Luma v3 Claude Agent Rebuild Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild Luma into a cleaner OpenClicky-inspired product with a professional shell and a Claude Opus-powered visible multi-agent mode that can act autonomously for the user.

**Architecture:** Keep the proven companion foundations, but split the rebuild into a new design system, a rebuilt shell, and a new Claude-first agent runtime. Preserve Luma’s visible multi-agent method while replacing the current orchestration internals with per-agent Claude sessions plus a shared execution coordinator.

**Tech Stack:** Swift 5.9, SwiftUI, AppKit, AVFoundation, ScreenCaptureKit, Anthropic API via existing `ClaudeAPI.swift`, XCTest in Xcode, `swiftc -parse` for terminal verification.

---

## File Structure

### New files

- `leanring-buddy/Agent/ClaudeAgentRuntime.swift`
  Owns agent session lifecycle, Claude Opus request flow, and per-agent state transitions.
- `leanring-buddy/Agent/AgentExecutionCoordinator.swift`
  Serializes device control so only one visible agent owns keyboard and pointer actions at a time.
- `leanring-buddy/Agent/AgentExecutionModels.swift`
  Shared models for agent session state, execution lock ownership, hesitation reasons, and action summaries.
- `leanring-buddy/Agent/AgentSessionMemoryStore.swift`
  Persists per-agent summaries and active session memory without bloating `LumaMemoryManager.swift`.
- `leanring-buddy/Agent/AgentRuntimeSafetyPolicy.swift`
  Centralizes hesitation rules for destructive actions, credential entry, ambiguous targets, and permission interruptions.
- `leanring-buddy/LumaTests/ClaudeAgentRuntimeStateTests.swift`
  Covers agent state transitions and Claude-only runtime constraints.
- `leanring-buddy/LumaTests/AgentExecutionCoordinatorTests.swift`
  Covers execution lock behavior and interruption semantics.

### Existing files to modify

- `leanring-buddy/DesignSystem.swift`
  Normalize the visual system around the approved Luma-specific professional shell.
- `leanring-buddy/MenuBarPanelManager.swift`
  Rebuild menu bar panel behavior, sizing, and pinned/unpinned presentation.
- `leanring-buddy/CompanionPanelView.swift`
  Rebuild the panel layout around clean status, agent entry points, and operational controls.
- `leanring-buddy/SettingsPanelView.swift`
  Rebuild settings into a compact operational surface with Anthropic-focused agent configuration.
- `leanring-buddy/OverlayWindow.swift`
  Rework overlay presentation so companion and agent surfaces feel like the same system.
- `leanring-buddy/CompanionResponseOverlay.swift`
  Tighten streamed response and execution HUD rendering.
- `leanring-buddy/CompanionBubbleWindow.swift`
  Align bubble chrome and sizing behavior with the new professional visual system.
- `leanring-buddy/CompanionManager.swift`
  Route companion and agent state through the new shell and runtime boundaries.
- `leanring-buddy/ClaudeAPI.swift`
  Add the Agent Mode request shape needed for Claude Opus sessions if the current API surface is insufficient.
- `leanring-buddy/AccountManager.swift`
  Update account/memory affordances only where needed to support the rebuilt shell.
- `leanring-buddy/Agent/LumaAgent.swift`
  Replace legacy shape/state definitions with clearer session-backed agent metadata.
- `leanring-buddy/Agent/AgentManager.swift`
  Shift from visual-bubble-first ownership to session/runtime-backed visible agent ownership.
- `leanring-buddy/Agent/AgentSettingsManager.swift`
  Add Agent Mode defaults for Claude-only execution, autonomy, and safety policy.
- `leanring-buddy/Agent/AgentStackView.swift`
  Preserve visible multi-agent interaction while rebuilding minimized and expanded surfaces.
- `leanring-buddy/Agent/AgentShapeView.swift`
  Align agent presentation with the cleaned-up visual system.
- `leanring-buddy/Agent/LumaAgentEngine.swift`
  Either retire or reduce this file to a thin adapter if runtime responsibilities move into `ClaudeAgentRuntime.swift`.
- `leanring-buddy/AGENTS.md`
  Update line counts and architecture notes only after the rebuild lands.

### Existing files to inspect during implementation

- `leanring-buddy/BuddyDictationManager.swift`
- `leanring-buddy/CompanionScreenCaptureUtility.swift`
- `leanring-buddy/LumaMemoryManager.swift`
- `leanring-buddy/WindowPositionManager.swift`
- `leanring-buddy/GlobalPushToTalkShortcutMonitor.swift`

---

### Task 1: Establish the runtime test seam and project scaffolding

**Files:**
- Create: `leanring-buddy/Agent/AgentExecutionModels.swift`
- Create: `leanring-buddy/LumaTests/ClaudeAgentRuntimeStateTests.swift`
- Create: `leanring-buddy/LumaTests/AgentExecutionCoordinatorTests.swift`
- Modify: `Luma.xcodeproj/project.pbxproj`

- [ ] **Step 1: Add the runtime model file with minimal state types**

```swift
import Foundation

enum ClaudeAgentExecutionState: Equatable {
    case idle
    case planning
    case waitingForExecutionLock
    case acting
    case hesitating(AgentHesitationReason)
    case paused
    case completed
    case failed(String)
}

enum AgentHesitationReason: Equatable {
    case destructiveAction(String)
    case credentialEntry
    case ambiguousTarget(String)
    case permissionInterruption(String)
}

struct ClaudeAgentSessionSnapshot: Equatable, Identifiable {
    let id: UUID
    var title: String
    var assignedTask: String
    var executionState: ClaudeAgentExecutionState
    var lastActionSummary: String?
}
```

- [ ] **Step 2: Add the files to the app target and create a `LumaTests` test target in Xcode**

Use Xcode to create a unit test bundle named `LumaTests`, then add:
- `leanring-buddy/LumaTests/ClaudeAgentRuntimeStateTests.swift`
- `leanring-buddy/LumaTests/AgentExecutionCoordinatorTests.swift`

No terminal `xcodebuild` here. This target exists so the runtime logic can be test-driven without relying on the full app shell.

- [ ] **Step 3: Write the failing runtime state tests**

```swift
import XCTest
@testable import leanring_buddy

final class ClaudeAgentRuntimeStateTests: XCTestCase {
    func testRuntimeRejectsNonOpusModelSelection() {
        let runtime = ClaudeAgentRuntime(apiClient: .stub, executionCoordinator: .stub)

        XCTAssertThrowsError(
            try runtime.validateAgentModelSelection("claude-3-5-sonnet")
        )
    }

    func testCompletingAgentTransitionsFromActingToCompleted() async throws {
        let runtime = ClaudeAgentRuntime(apiClient: .stub, executionCoordinator: .stub)
        let sessionID = try await runtime.spawnAgent(title: "Research", task: "Inspect app")

        try await runtime.forceState(sessionID: sessionID, state: .acting)
        try await runtime.finishAgent(sessionID: sessionID, summary: "Done")

        let snapshot = try runtime.snapshot(for: sessionID)
        XCTAssertEqual(snapshot.executionState, .completed)
        XCTAssertEqual(snapshot.lastActionSummary, "Done")
    }
}
```

```swift
import XCTest
@testable import leanring_buddy

final class AgentExecutionCoordinatorTests: XCTestCase {
    func testCoordinatorGrantsLockToOnlyOneAgentAtATime() async throws {
        let coordinator = AgentExecutionCoordinator()
        let firstAgentID = UUID()
        let secondAgentID = UUID()

        let firstLock = await coordinator.acquireLock(for: firstAgentID)
        let secondLock = await coordinator.acquireLock(for: secondAgentID)

        XCTAssertTrue(firstLock)
        XCTAssertFalse(secondLock)
    }
}
```

- [ ] **Step 4: Run the tests in Xcode and confirm they fail for the right reasons**

Run in Xcode: `Product > Test`

Expected:
- `ClaudeAgentRuntimeStateTests` fails because `ClaudeAgentRuntime` does not exist yet.
- `AgentExecutionCoordinatorTests` fails because `AgentExecutionCoordinator` does not exist yet.

- [ ] **Step 5: Commit the scaffolding**

```bash
git add Luma.xcodeproj/project.pbxproj leanring-buddy/Agent/AgentExecutionModels.swift leanring-buddy/LumaTests
git commit -m "test: add Luma runtime test scaffolding for Claude agent rebuild"
```

---

### Task 2: Build the Claude-only agent runtime core

**Files:**
- Create: `leanring-buddy/Agent/ClaudeAgentRuntime.swift`
- Create: `leanring-buddy/Agent/AgentSessionMemoryStore.swift`
- Modify: `leanring-buddy/ClaudeAPI.swift`
- Modify: `leanring-buddy/Agent/AgentExecutionModels.swift`
- Test: `leanring-buddy/LumaTests/ClaudeAgentRuntimeStateTests.swift`

- [ ] **Step 1: Extend the failing test with session expectations**

```swift
func testSpawnedAgentStartsInPlanningState() async throws {
    let runtime = ClaudeAgentRuntime(apiClient: .stub, executionCoordinator: .stub)

    let sessionID = try await runtime.spawnAgent(title: "Plan", task: "Open Notes")
    let snapshot = try runtime.snapshot(for: sessionID)

    XCTAssertEqual(snapshot.executionState, .planning)
    XCTAssertEqual(snapshot.title, "Plan")
    XCTAssertEqual(snapshot.assignedTask, "Open Notes")
}
```

- [ ] **Step 2: Run the runtime state test to verify it fails**

Run in Xcode: `ClaudeAgentRuntimeStateTests`

Expected:
- Failure because `spawnAgent`, `snapshot`, and the runtime implementation do not exist yet.

- [ ] **Step 3: Implement the minimal runtime and memory store**

```swift
import Foundation

@MainActor
final class ClaudeAgentRuntime {
    private let apiClient: ClaudeAgentRuntimeAPI
    private let executionCoordinator: AgentExecutionCoordinator
    private let memoryStore: AgentSessionMemoryStore
    private var sessions: [UUID: ClaudeAgentSessionSnapshot] = [:]

    init(
        apiClient: ClaudeAgentRuntimeAPI,
        executionCoordinator: AgentExecutionCoordinator,
        memoryStore: AgentSessionMemoryStore = AgentSessionMemoryStore()
    ) {
        self.apiClient = apiClient
        self.executionCoordinator = executionCoordinator
        self.memoryStore = memoryStore
    }

    func validateAgentModelSelection(_ modelIdentifier: String) throws {
        guard modelIdentifier.localizedCaseInsensitiveContains("opus") else {
            throw ClaudeAgentRuntimeError.unsupportedModel(modelIdentifier)
        }
    }

    func spawnAgent(title: String, task: String) async throws -> UUID {
        let sessionID = UUID()
        sessions[sessionID] = ClaudeAgentSessionSnapshot(
            id: sessionID,
            title: title,
            assignedTask: task,
            executionState: .planning,
            lastActionSummary: nil
        )
        return sessionID
    }

    func snapshot(for sessionID: UUID) throws -> ClaudeAgentSessionSnapshot {
        guard let snapshot = sessions[sessionID] else {
            throw ClaudeAgentRuntimeError.missingSession(sessionID)
        }
        return snapshot
    }
}
```

```swift
import Foundation

final class AgentSessionMemoryStore {
    private var summaries: [UUID: String] = [:]

    func saveSummary(_ summary: String, for sessionID: UUID) {
        summaries[sessionID] = summary
    }

    func summary(for sessionID: UUID) -> String? {
        summaries[sessionID]
    }
}
```

- [ ] **Step 4: Add the Agent Mode request shape needed by `ClaudeAPI.swift`**

```swift
struct ClaudeAgentRequest {
    let systemPrompt: String
    let userTask: String
    let modelIdentifier: String
    let screenshotPayloads: [Data]
}

protocol ClaudeAgentRuntimeAPI {
    func sendAgentRequest(_ request: ClaudeAgentRequest) async throws -> String
}
```

- [ ] **Step 5: Run the runtime state test and make it pass**

Run in Xcode: `ClaudeAgentRuntimeStateTests`

Expected:
- `testRuntimeRejectsNonOpusModelSelection` passes.
- `testSpawnedAgentStartsInPlanningState` passes.
- `testCompletingAgentTransitionsFromActingToCompleted` still fails because completion helpers do not exist yet.

- [ ] **Step 6: Commit the runtime core**

```bash
git add leanring-buddy/Agent/ClaudeAgentRuntime.swift leanring-buddy/Agent/AgentSessionMemoryStore.swift leanring-buddy/Agent/AgentExecutionModels.swift leanring-buddy/ClaudeAPI.swift leanring-buddy/LumaTests/ClaudeAgentRuntimeStateTests.swift
git commit -m "feat: add Claude-only agent runtime core for Agent Mode"
```

---

### Task 3: Add execution coordination and interruption behavior

**Files:**
- Create: `leanring-buddy/Agent/AgentExecutionCoordinator.swift`
- Test: `leanring-buddy/LumaTests/AgentExecutionCoordinatorTests.swift`
- Modify: `leanring-buddy/Agent/ClaudeAgentRuntime.swift`

- [ ] **Step 1: Add the next failing coordinator tests**

```swift
func testCoordinatorReleasesLockWhenOwnerStops() async throws {
    let coordinator = AgentExecutionCoordinator()
    let firstAgentID = UUID()
    let secondAgentID = UUID()

    XCTAssertTrue(await coordinator.acquireLock(for: firstAgentID))
    await coordinator.releaseLock(for: firstAgentID)
    XCTAssertTrue(await coordinator.acquireLock(for: secondAgentID))
}

func testRuntimeMovesAgentToWaitingWhenLockIsUnavailable() async throws {
    let coordinator = AgentExecutionCoordinator()
    let runtime = ClaudeAgentRuntime(apiClient: .stub, executionCoordinator: coordinator)

    let firstAgentID = try await runtime.spawnAgent(title: "First", task: "Click")
    let secondAgentID = try await runtime.spawnAgent(title: "Second", task: "Type")

    try await runtime.beginExecution(for: firstAgentID)
    try await runtime.beginExecution(for: secondAgentID)

    let secondSnapshot = try runtime.snapshot(for: secondAgentID)
    XCTAssertEqual(secondSnapshot.executionState, .waitingForExecutionLock)
}
```

- [ ] **Step 2: Run the coordinator tests to verify they fail**

Run in Xcode: `AgentExecutionCoordinatorTests`

Expected:
- Failure because acquisition, release, and waiting-state integration do not exist yet.

- [ ] **Step 3: Implement the coordinator and minimal runtime integration**

```swift
import Foundation

actor AgentExecutionCoordinator {
    private var currentOwner: UUID?

    func acquireLock(for agentID: UUID) -> Bool {
        guard currentOwner == nil else { return false }
        currentOwner = agentID
        return true
    }

    func releaseLock(for agentID: UUID) {
        guard currentOwner == agentID else { return }
        currentOwner = nil
    }

    func ownerID() -> UUID? {
        currentOwner
    }
}
```

```swift
func beginExecution(for sessionID: UUID) async throws {
    guard sessions[sessionID] != nil else {
        throw ClaudeAgentRuntimeError.missingSession(sessionID)
    }

    let granted = await executionCoordinator.acquireLock(for: sessionID)
    sessions[sessionID]?.executionState = granted ? .acting : .waitingForExecutionLock
}

func stopAgent(sessionID: UUID) async {
    await executionCoordinator.releaseLock(for: sessionID)
    sessions[sessionID]?.executionState = .paused
}
```

- [ ] **Step 4: Run the coordinator tests and make them pass**

Run in Xcode: `AgentExecutionCoordinatorTests`

Expected:
- All coordinator lock tests pass.

- [ ] **Step 5: Commit the coordinator layer**

```bash
git add leanring-buddy/Agent/AgentExecutionCoordinator.swift leanring-buddy/Agent/ClaudeAgentRuntime.swift leanring-buddy/LumaTests/AgentExecutionCoordinatorTests.swift
git commit -m "feat: add shared execution coordination for autonomous agents"
```

---

### Task 4: Add safety policy and completion persistence

**Files:**
- Create: `leanring-buddy/Agent/AgentRuntimeSafetyPolicy.swift`
- Modify: `leanring-buddy/Agent/ClaudeAgentRuntime.swift`
- Modify: `leanring-buddy/Agent/AgentSessionMemoryStore.swift`
- Test: `leanring-buddy/LumaTests/ClaudeAgentRuntimeStateTests.swift`

- [ ] **Step 1: Add failing tests for hesitation behavior and summary persistence**

```swift
func testRuntimeMovesToHesitationForCredentialEntry() async throws {
    let runtime = ClaudeAgentRuntime(apiClient: .stub, executionCoordinator: .stub)
    let sessionID = try await runtime.spawnAgent(title: "Login", task: "Enter password")

    try await runtime.handlePlannedAction(.enterCredential, for: sessionID)

    let snapshot = try runtime.snapshot(for: sessionID)
    XCTAssertEqual(snapshot.executionState, .hesitating(.credentialEntry))
}

func testFinishingAgentPersistsSummary() async throws {
    let memoryStore = AgentSessionMemoryStore()
    let runtime = ClaudeAgentRuntime(
        apiClient: .stub,
        executionCoordinator: .stub,
        memoryStore: memoryStore
    )
    let sessionID = try await runtime.spawnAgent(title: "Checkout", task: "Confirm order")

    try await runtime.finishAgent(sessionID: sessionID, summary: "Order complete")

    XCTAssertEqual(memoryStore.summary(for: sessionID), "Order complete")
}
```

- [ ] **Step 2: Run the runtime tests to verify they fail**

Run in Xcode: `ClaudeAgentRuntimeStateTests`

Expected:
- Failure because planned action handling, hesitation state, and summary persistence are not implemented yet.

- [ ] **Step 3: Implement the safety policy and finish flow**

```swift
import Foundation

enum PlannedAgentAction {
    case click(String)
    case typeText(String)
    case destructive(String)
    case enterCredential
}

struct AgentRuntimeSafetyPolicy {
    func hesitationReason(for action: PlannedAgentAction) -> AgentHesitationReason? {
        switch action {
        case .destructive(let detail):
            return .destructiveAction(detail)
        case .enterCredential:
            return .credentialEntry
        default:
            return nil
        }
    }
}
```

```swift
private let safetyPolicy = AgentRuntimeSafetyPolicy()

func handlePlannedAction(_ action: PlannedAgentAction, for sessionID: UUID) async throws {
    if let reason = safetyPolicy.hesitationReason(for: action) {
        sessions[sessionID]?.executionState = .hesitating(reason)
        return
    }

    try await beginExecution(for: sessionID)
}

func finishAgent(sessionID: UUID, summary: String) async throws {
    await executionCoordinator.releaseLock(for: sessionID)
    sessions[sessionID]?.executionState = .completed
    sessions[sessionID]?.lastActionSummary = summary
    memoryStore.saveSummary(summary, for: sessionID)
}
```

- [ ] **Step 4: Run the runtime tests and make them pass**

Run in Xcode: `ClaudeAgentRuntimeStateTests`

Expected:
- Hesitation tests pass.
- Completion summary persistence passes.
- Earlier runtime state tests remain green.

- [ ] **Step 5: Commit the safety and persistence layer**

```bash
git add leanring-buddy/Agent/AgentRuntimeSafetyPolicy.swift leanring-buddy/Agent/ClaudeAgentRuntime.swift leanring-buddy/Agent/AgentSessionMemoryStore.swift leanring-buddy/LumaTests/ClaudeAgentRuntimeStateTests.swift
git commit -m "feat: add hesitation safety policy and agent summary persistence"
```

---

### Task 5: Rebuild the visible agent model and manager integration

**Files:**
- Modify: `leanring-buddy/Agent/LumaAgent.swift`
- Modify: `leanring-buddy/Agent/AgentManager.swift`
- Modify: `leanring-buddy/Agent/AgentSettingsManager.swift`
- Modify: `leanring-buddy/Agent/LumaAgentEngine.swift`
- Modify: `leanring-buddy/CompanionManager.swift`

- [ ] **Step 1: Add the new visible-agent shape to `LumaAgent.swift`**

```swift
import CoreGraphics
import Foundation
import SwiftUI

enum VisibleAgentPresentationState: Equatable {
    case minimized
    case expanded
}

struct LumaAgent: Identifiable, Equatable {
    let id: UUID
    var title: String
    var assignedTask: String
    var color: Color
    var position: CGPoint
    var presentationState: VisibleAgentPresentationState
    var runtimeState: ClaudeAgentExecutionState
    var lastActionSummary: String?
}
```

- [ ] **Step 2: Route `AgentManager` through the Claude runtime instead of stand-alone fake state**

```swift
@MainActor
final class AgentManager: ObservableObject {
    @Published private(set) var agents: [LumaAgent] = []

    private let runtime: ClaudeAgentRuntime

    init(runtime: ClaudeAgentRuntime) {
        self.runtime = runtime
    }

    func spawnVisibleAgent(title: String, task: String, color: Color, position: CGPoint) async throws {
        let sessionID = try await runtime.spawnAgent(title: title, task: task)
        let snapshot = try runtime.snapshot(for: sessionID)
        agents.append(
            LumaAgent(
                id: snapshot.id,
                title: snapshot.title,
                assignedTask: snapshot.assignedTask,
                color: color,
                position: position,
                presentationState: .expanded,
                runtimeState: snapshot.executionState,
                lastActionSummary: snapshot.lastActionSummary
            )
        )
    }
}
```

- [ ] **Step 3: Add Claude-only Agent Mode defaults to `AgentSettingsManager.swift`**

```swift
@Published var isFullAutonomyEnabled: Bool = true
@Published var requiredAgentModelIdentifier: String = "claude-opus"
@Published var shouldPauseForRiskyActions: Bool = true
```

- [ ] **Step 4: Reduce `LumaAgentEngine.swift` to an adapter or remove duplicated orchestration**

```swift
@MainActor
final class LumaAgentEngine {
    private let runtime: ClaudeAgentRuntime

    init(runtime: ClaudeAgentRuntime) {
        self.runtime = runtime
    }

    func executeTask(for sessionID: UUID, plannedAction: PlannedAgentAction) async throws {
        try await runtime.handlePlannedAction(plannedAction, for: sessionID)
    }
}
```

- [ ] **Step 5: Commit the visible-agent runtime integration**

```bash
git add leanring-buddy/Agent/LumaAgent.swift leanring-buddy/Agent/AgentManager.swift leanring-buddy/Agent/AgentSettingsManager.swift leanring-buddy/Agent/LumaAgentEngine.swift leanring-buddy/CompanionManager.swift
git commit -m "refactor: back visible agents with Claude runtime sessions"
```

---

### Task 6: Rebuild the design system and menu shell

**Files:**
- Modify: `leanring-buddy/DesignSystem.swift`
- Modify: `leanring-buddy/MenuBarPanelManager.swift`
- Modify: `leanring-buddy/CompanionPanelView.swift`
- Modify: `leanring-buddy/SettingsPanelView.swift`

- [ ] **Step 1: Normalize `DesignSystem.swift` around the approved shell direction**

```swift
enum DS {
    enum Colors {
        static let background = Color(hex: "#111315")
        static let surface = Color(hex: "#171A1C")
        static let surfaceElevated = Color(hex: "#1E2225")
        static let borderSubtle = Color.white.opacity(0.08)
        static let borderStrong = Color.white.opacity(0.16)
        static let textPrimary = Color(hex: "#F2F4F5")
        static let textSecondary = Color(hex: "#B4BDC2")
        static let textTertiary = Color(hex: "#7A848A")
        static let success = Color(hex: "#34D399")
        static let warning = Color(hex: "#FFB224")
        static let destructive = Color(hex: "#E5484D")
    }
}
```

Keep the existing helper types that are already working, but align the token names and values with the approved professional shell instead of the earlier exact-clone direction.

- [ ] **Step 2: Rebuild `MenuBarPanelManager.swift` with pinned and floating states**

```swift
private let panelWidth: CGFloat = 356
private let defaultPanelHeight: CGFloat = 340
private let panelEdgePadding: CGFloat = 12

private func makeFloatingPanel() -> NSPanel {
    let panel = NSPanel(
        contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: defaultPanelHeight),
        styleMask: [.nonactivatingPanel, .fullSizeContentView],
        backing: .buffered,
        defer: false
    )
    panel.isFloatingPanel = true
    panel.backgroundColor = .clear
    panel.hasShadow = false
    return panel
}
```

- [ ] **Step 3: Rebuild the panel header and operational layout in `CompanionPanelView.swift`**

```swift
HStack(spacing: 10) {
    Text("Luma")
        .font(.system(size: 14, weight: .semibold))
        .foregroundColor(DS.Colors.textPrimary)

    Circle()
        .fill(statusColor)
        .frame(width: 7, height: 7)

    Text(statusText)
        .font(.system(size: 11, weight: .medium))
        .foregroundColor(DS.Colors.textTertiary)

    Spacer()

    Button(action: togglePinnedState) {
        Image(systemName: isPinned ? "pin.fill" : "pin")
    }
    .buttonStyle(DSIconButtonStyle(size: 20))
}
```

- [ ] **Step 4: Rebuild the settings surface as an operational inspector**

```swift
VStack(alignment: .leading, spacing: 16) {
    settingsSection(title: "Agent Mode") {
        Toggle("Full autonomy", isOn: $agentSettingsManager.isFullAutonomyEnabled)
        Text("Claude Opus is required for autonomous agents.")
            .font(.system(size: 11))
            .foregroundColor(DS.Colors.textTertiary)
    }

    settingsSection(title: "API Keys") {
        SecureField("Anthropic API Key", text: $anthropicAPIKey)
    }
}
```

- [ ] **Step 5: Verify with parse checks and a manual Xcode build**

Run:

```bash
swiftc -parse /Users/nox/Desktop/luma/leanring-buddy/DesignSystem.swift /Users/nox/Desktop/luma/leanring-buddy/MenuBarPanelManager.swift /Users/nox/Desktop/luma/leanring-buddy/CompanionPanelView.swift /Users/nox/Desktop/luma/leanring-buddy/SettingsPanelView.swift
```

Expected:
- No syntax errors from the rebuilt shell files.

Then open Xcode and build the `Luma by Nox` scheme with `Cmd+B`.

- [ ] **Step 6: Commit the shell rebuild**

```bash
git add leanring-buddy/DesignSystem.swift leanring-buddy/MenuBarPanelManager.swift leanring-buddy/CompanionPanelView.swift leanring-buddy/SettingsPanelView.swift
git commit -m "feat: rebuild Luma shell with professional panel and settings surfaces"
```

---

### Task 7: Rebuild the overlay and visible agent surfaces

**Files:**
- Modify: `leanring-buddy/OverlayWindow.swift`
- Modify: `leanring-buddy/CompanionResponseOverlay.swift`
- Modify: `leanring-buddy/CompanionBubbleWindow.swift`
- Modify: `leanring-buddy/Agent/AgentStackView.swift`
- Modify: `leanring-buddy/Agent/AgentShapeView.swift`

- [ ] **Step 1: Rebuild the companion response HUD styling**

```swift
VStack(alignment: .leading, spacing: 10) {
    Text(activeTitle)
        .font(.system(size: 12, weight: .semibold))
        .foregroundColor(DS.Colors.textPrimary)

    Text(activeBody)
        .font(.system(size: 12, weight: .medium))
        .foregroundColor(DS.Colors.textSecondary)
}
.padding(14)
.background(DS.Colors.surfaceElevated.opacity(0.96))
.overlay(
    RoundedRectangle(cornerRadius: 12)
        .stroke(DS.Colors.borderSubtle, lineWidth: 1)
)
```

- [ ] **Step 2: Rebuild minimized and expanded visible-agent surfaces without losing the method**

```swift
struct MinimizedAgentView: View {
    let agent: LumaAgent

    var body: some View {
        Circle()
            .fill(agent.color.opacity(0.18))
            .overlay(
                Circle()
                    .stroke(agent.color.opacity(0.58), lineWidth: 1)
            )
            .frame(width: 56, height: 56)
    }
}
```

```swift
struct ExpandedAgentView: View {
    let agent: LumaAgent

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(agent.title)
                .font(.system(size: 13, weight: .semibold))
            Text(agent.assignedTask)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(DS.Colors.textSecondary)
            Text(agent.lastActionSummary ?? "Preparing next action")
                .font(.system(size: 11))
                .foregroundColor(DS.Colors.textTertiary)
        }
        .padding(16)
        .background(DS.Colors.surface)
    }
}
```

- [ ] **Step 3: Add the overlay-level interruption affordances**

```swift
Button("Stop All Agents") {
    companionManager.stopAllAgents()
}
.buttonStyle(DSDestructiveButtonStyle())
```

- [ ] **Step 4: Verify with parse checks and a manual Xcode run**

Run:

```bash
swiftc -parse /Users/nox/Desktop/luma/leanring-buddy/OverlayWindow.swift /Users/nox/Desktop/luma/leanring-buddy/CompanionResponseOverlay.swift /Users/nox/Desktop/luma/leanring-buddy/CompanionBubbleWindow.swift /Users/nox/Desktop/luma/leanring-buddy/Agent/AgentStackView.swift /Users/nox/Desktop/luma/leanring-buddy/Agent/AgentShapeView.swift
```

Expected:
- No syntax errors from the rebuilt overlay and visible-agent surface files.

Then verify manually in Xcode:
- spawn multiple agents
- confirm minimized and expanded views still work
- confirm the overlay shows active task context
- confirm stop actions are always reachable

- [ ] **Step 5: Commit the surface rebuild**

```bash
git add leanring-buddy/OverlayWindow.swift leanring-buddy/CompanionResponseOverlay.swift leanring-buddy/CompanionBubbleWindow.swift leanring-buddy/Agent/AgentStackView.swift leanring-buddy/Agent/AgentShapeView.swift
git commit -m "feat: rebuild overlay and visible multi-agent surfaces"
```

---

### Task 8: Integrate full Agent Mode flow and update project documentation

**Files:**
- Modify: `leanring-buddy/CompanionManager.swift`
- Modify: `leanring-buddy/Agent/AgentManager.swift`
- Modify: `leanring-buddy/Agent/AgentSettingsManager.swift`
- Modify: `leanring-buddy/AGENTS.md`
- Modify: `AGENTS.md`

- [ ] **Step 1: Wire the manager graph together inside `CompanionManager.swift`**

```swift
private lazy var agentExecutionCoordinator = AgentExecutionCoordinator()
private lazy var claudeAgentRuntime = ClaudeAgentRuntime(
    apiClient: claudeAPI,
    executionCoordinator: agentExecutionCoordinator
)
private lazy var agentManager = AgentManager(runtime: claudeAgentRuntime)
```

- [ ] **Step 2: Route voice and panel actions into the rebuilt Agent Mode**

```swift
func spawnAgentFromVoice(task: String) async {
    try? await agentManager.spawnVisibleAgent(
        title: AgentVoiceIntegration.title(for: task),
        task: task,
        color: .blue,
        position: defaultAgentSpawnPoint()
    )
}
```

- [ ] **Step 3: Add final verification passes**

Run:

```bash
swiftc -parse /Users/nox/Desktop/luma/leanring-buddy/CompanionManager.swift /Users/nox/Desktop/luma/leanring-buddy/Agent/ClaudeAgentRuntime.swift /Users/nox/Desktop/luma/leanring-buddy/Agent/AgentExecutionCoordinator.swift /Users/nox/Desktop/luma/leanring-buddy/Agent/AgentManager.swift /Users/nox/Desktop/luma/leanring-buddy/Agent/AgentSettingsManager.swift
```

Expected:
- No syntax errors in the runtime integration files.

Then in Xcode:
- build the `Luma by Nox` scheme with `Cmd+B`
- run the app
- verify push-to-talk still works
- verify agent spawning works from UI and voice
- verify only Claude Opus is allowed in Agent Mode
- verify fully autonomous continuation works
- verify hesitation states stop risky actions
- verify the execution lock prevents agent conflict

- [ ] **Step 4: Update `AGENTS.md` only after the rebuild is real**

```md
- `leanring-buddy/Agent/ClaudeAgentRuntime.swift` | ~220 | Claude Opus-backed autonomous agent runtime with per-agent session state.
- `leanring-buddy/Agent/AgentExecutionCoordinator.swift` | ~90 | Shared keyboard/pointer lock coordinator for multiple visible agents.
- `leanring-buddy/Agent/AgentRuntimeSafetyPolicy.swift` | ~60 | Hesitation and confirmation policy for risky agent actions.
- `leanring-buddy/Agent/AgentSessionMemoryStore.swift` | ~70 | Persists per-agent active memory and completion summaries.
```

- [ ] **Step 5: Commit the integration and doc updates**

```bash
git add leanring-buddy/CompanionManager.swift leanring-buddy/Agent/AgentManager.swift leanring-buddy/Agent/AgentSettingsManager.swift AGENTS.md leanring-buddy/AGENTS.md
git commit -m "feat: integrate Claude autonomous Agent Mode into rebuilt Luma shell"
```

---

## Self-Review

### Spec coverage

- The plan covers the new Claude Opus runtime in Tasks 2 through 5.
- The plan covers execution lock arbitration and interruptions in Tasks 3 and 8.
- The plan covers safety hesitation behavior in Task 4.
- The plan covers the rebuilt professional shell in Task 6.
- The plan covers the preserved visible multi-agent method in Task 7.
- The plan covers documentation updates after implementation in Task 8.

### Placeholder scan

- No `TODO`, `TBD`, or “similar to previous task” placeholders remain.
- Every code-editing task includes concrete snippet examples.
- Verification steps use exact terminal parse commands where terminal verification is allowed and explicit Xcode actions where `xcodebuild` is forbidden.

### Type consistency

- The plan consistently uses `ClaudeAgentRuntime`, `AgentExecutionCoordinator`, `ClaudeAgentExecutionState`, `AgentHesitationReason`, and `AgentSessionMemoryStore`.
- The plan consistently treats `LumaAgent` as the visible surface model backed by runtime sessions.

