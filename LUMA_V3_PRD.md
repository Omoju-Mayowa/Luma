# Luma v3.0 — Product Requirements Document

## Overview
This document outlines all changes for Luma v3.0. Tasks are ordered from easiest to hardest. Each task has a progress state so Claude Code can resume from any checkpoint if paused.

---

## Progress Tracking Legend
- `[ ]` — Not started
- `[~]` — In progress
- `[x]` — Complete

---

## PHASE 1 — Settings & Configuration (Easiest)

### 1.1 Voice Settings Panel
**Progress:** `[x]`

Add a new **Voice** tab in SettingsPanelView with the following controls:

- Gender toggle — Male / Female (maps to AVSpeechSynthesisVoice identifiers)
- Pitch slider — range 0.5 to 2.0 (AVSpeechUtterance.pitchMultiplier)
- Rate/Tempo slider — range 0.1 to 1.0 (AVSpeechUtterance.rate)
- Volume slider — range 0.0 to 1.0 (AVSpeechUtterance.volume)
- "Preview Voice" button — speaks a short test string with current settings
- All values persist to UserDefaults under keys: `luma.voice.gender`, `luma.voice.pitch`, `luma.voice.rate`, `luma.voice.volume`
- NativeTTSClient must read these values before every utterance

**Acceptance:** Voice changes apply immediately on next Luma response. Preview button works.

---

### 1.2 Agent Limit Setting
**Progress:** `[x]`

Add to the **Agent Mode** settings tab:

- "Maximum Agents" stepper — min 1, max 10, default 3
- Persists to UserDefaults under `luma.agents.maxCount`
- When limit is reached and a new agent is requested, auto-dismiss the agent with the oldest `lastUsedAt` timestamp that is not currently processing
- Show a brief macOS notification: "Agent limit reached. Removed idle agent."

**Acceptance:** Creating agents beyond the limit auto-removes the oldest inactive one.

---

### 1.3 Supported Models Configuration
**Progress:** `[x]`

In Agent Mode settings, add a **Model** picker per agent profile. Supported models only:

- `claude-sonnet-4-6` (Anthropic)
- `claude-opus-4-6` (Anthropic)
- `gpt-4o` (OpenAI)
- `gpt-4o-mini` (OpenAI)

Model selection persists per agent in a new `AgentProfile` struct stored in UserDefaults/Keychain. Default is `claude-sonnet-4-6`.

**Acceptance:** Each agent can have a different model. Model is used in all API calls for that agent.

---

### 1.4 Real-Time Log Window
**Progress:** `[x]`

Add a **Log** button in the main settings page (General tab).

- Clicking opens a new NSWindow titled "Luma Activity Log"
- Window is non-modal, resizable, minimum 700x400px
- Contains a scrollable NSTextView with monospaced font (SF Mono or Menlo)
- Log entries are appended in real time with timestamp: `[HH:mm:ss] message`
- A `LumaLogger` singleton handles all log writes — replace all existing `print()` statements with `LumaLogger.shared.log()`
- "Clear" button at top right clears the view (does not delete file logs)
- Auto-scrolls to bottom on new entries

**Acceptance:** Log window shows all Luma activity in real time. Existing print statements migrated.

---

## PHASE 2 — Cursor Customizer

### 2.1 Cursor State Model
**Progress:** `[x]`

Define a `LumaCursorState` enum with cases:
- `.idle` — default resting state
- `.pointing` — when Luma is targeting an element
- `.listening` — when voice input is active
- `.processing` — when agent is working autonomously
- `.hover` — when cursor hovers a UI element

Create a `CursorProfile` struct:
```swift
struct CursorProfile: Codable {
    var idleShape: CursorShape
    var idleColor: String // hex
    var idleSize: CGFloat
    var pointingShape: CursorShape
    var pointingColor: String
    var pointingSize: CGFloat
    var listeningShape: CursorShape
    var listeningColor: String
    var listeningSize: CGFloat
    var processingShape: CursorShape
    var processingColor: String
    var processingSize: CGFloat
}

enum CursorShape: String, Codable, CaseIterable {
    case teardrop, circle, roundedTriangle, diamond, cross, dot
}
```

Persist `CursorProfile` to Keychain under `luma.cursor.profile`.

**Acceptance:** Model compiles. Default profile matches current Luma cursor behavior.

---

### 2.2 Cursor Customizer Settings UI
**Progress:** `[x]`


Add a **Cursor** tab in SettingsPanelView:

- Section per state: Idle, Pointing, Listening, Processing
- Each section has:
  - Shape picker (segmented control or grid of shape previews)
  - Color picker (NSColorWell)
  - Size slider (8pt to 32pt)
- Live preview canvas at top of tab — 200x200px dark rounded rect showing the cursor shape in real time as user adjusts
- "Reset to Default" button restores original teardrop profile
- Changes apply immediately to CustomCursorManager

**Acceptance:** Changing cursor shape/color/size in settings updates the live cursor visually.

---

### 2.3 CustomCursorManager Update
**Progress:** `[x]`

Update `CustomCursorManager.swift` to:

- Read `CursorProfile` from Keychain on init
- Expose `func setState(_ state: LumaCursorState)` — switches active cursor appearance
- Redraw cursor NSImage based on current state's shape, color, and size
- Called by:
  - VoiceEngine on listening start/stop → `.listening` / `.idle`
  - WalkthroughEngine on step point → `.pointing` / `.idle`
  - AgentEngine on autonomous task start/stop → `.processing` / `.idle`

**Acceptance:** Cursor visually changes per state using customized profile values.

---

## PHASE 3 — Memory & Conversation Storage

### 3.1 LumaMemoryManager
**Progress:** `[x]`

Create `LumaMemoryManager.swift`:

- Manages two file types in `~/Library/Application Support/Luma/`:
  - `memory.md` — global markdown file, AI persona + remembered preferences
  - `history/agent_{id}_{timestamp}.json` — per-agent conversation history
- When a JSON history file exceeds 2MB, create a new timestamped file automatically
- `func appendToHistory(agentId: String, entry: ConversationEntry)` — appends to current JSON file
- `func loadMemory() -> String` — returns full contents of memory.md
- `func searchHistory(query: String) -> [ConversationEntry]` — basic keyword search across all JSON files
- `func updateMemory(newFact: String)` — appends to memory.md with timestamp

```swift
struct ConversationEntry: Codable {
    let timestamp: Date
    let agentId: String
    let agentTitle: String
    let role: String // "user" or "luma"
    let content: String
    let taskStatus: String? // "complete", "failed", "in_progress"
}
```

**Acceptance:** Files are created correctly. History appends per agent. Memory loads as string.

---

### 3.2 Memory Integration with Agents
**Progress:** `[x]`

- On agent init, load `memory.md` and prepend as system context in the first API call
- After every completed task, call `LumaMemoryManager.shared.appendToHistory()`
- If a user asks "have I done this before" or similar — search history files and summarise results in the agent bubble
- Memory file is never sent raw to API — it is summarised to max 500 tokens before prepending

**Acceptance:** Agent has context from memory. History is searchable. Memory is summarised before API call.

---

## PHASE 4 — Agent Bubble UI (Core)

### 4.1 Agent Data Model
**Progress:** `[x]`

Create `LumaAgent.swift`:

```swift
struct LumaAgent: Identifiable {
    let id: UUID
    var title: String // generated from first task
    var color: Color // random on creation
    var shape: AgentShape // random on creation
    var isAnimating: Bool // random — some animate, some don't
    var position: CGPoint // screen position, persisted
    var state: AgentState
    var lastUsedAt: Date
    var model: String
    var conversationHistory: [ConversationEntry]
    var processingText: String? // "researching metal cups"
    var completionText: String? // one-liner result
    var taskStatus: TaskStatus?
}

enum AgentShape: CaseIterable {
    case square, rhombus, triangle, hexagon, circle
}

enum AgentState {
    case idle
    case expanded
    case processing
    case complete
}

enum TaskStatus {
    case complete, failed, inProgress
}
```

Create `AgentManager.swift` — singleton that holds `[LumaAgent]`, handles spawn/dismiss/update.

**Acceptance:** Model compiles. AgentManager can add/remove agents. Agent positions persist to UserDefaults.

---

### 4.2 Agent Shape Rendering
**Progress:** `[x]`

Create `AgentShapeView.swift` — SwiftUI view that renders a shape inside a rounded rect button:

- Shape fills ~60% of button area
- Shape color matches agent color
- Button background: dark translucent (`Color.black.opacity(0.75)`) with agent color glow (shadow with agent color, radius 8)
- Agent color hint as subtle tinted border (2pt, agent color at 40% opacity)
- Supports `.square`, `.rhombus`, `.triangle`, `.hexagon`, `.circle`
- Shape is drawn with SwiftUI `Path` or `Shape` protocol

**Acceptance:** Each shape renders correctly inside the button. Glow matches agent color.

---

### 4.3 Idle Bubble Animation
**Progress:** `[x]`

Add idle bounce animation to minimized agent bubbles:

- Agents with `isAnimating == true` get a continuous vertical ease-in-out bounce (amplitude ~4pt, duration ~2.0s, repeat forever, `autoreverse: true`)
- Agents with `isAnimating == false` are static
- When `state == .processing` — all agents shake horizontally (amplitude ~3pt, duration ~0.08s, repeat) and neighbours within 80pt wobble at 50% amplitude
- Use SwiftUI `.animation(.easeInOut(duration: 2).repeatForever(autoreverses: true))` for idle
- Use `withAnimation(.spring(response: 0.1, dampingFraction: 0.3))` for processing shake

**Acceptance:** Animated agents bounce continuously. Processing shake triggers on task start. Neighbours wobble.

---

### 4.4 Minimized Agent Stack & Drag
**Progress:** `[x]`

Create `AgentStackView.swift` — an overlay view that positions all agent bubbles:

- Default layout: vertical stack on right edge of screen, 16pt from edge, 12pt gap between bubbles, starting 60pt from top
- Each bubble is 56x56pt in minimized state
- Draggable — use `DragGesture` to update `agent.position` on drag end
- Position persists to UserDefaults per agent ID
- Hover over bubble → show X button (circle with x, 18pt, top-right of bubble, white on dark)
- X button tap → dismiss agent with fade out animation, remove from AgentManager

**Acceptance:** Bubbles stack on right. Drag repositions and persists. Hover shows X. X dismisses with animation.

---

### 4.5 Expanded Agent Bubble
**Progress:** `[x]`

When agent bubble is tapped, expand to engaged state:

- Animate from 56x56pt to ~500x400pt using SwiftUI `.matchedGeometryEffect` or spring animation
- Expand in whichever direction has more screen space (check screen bounds)
- Expanded view has three sections:

**Section 1 — Header (fixed height ~48pt)**
- Agent title (auto-generated, truncated if long)
- Small colored shape icon left of title
- Background: agent color at 8% opacity

**Section 2 — Status Area (fixed height ~280pt, scrollable)**
- When processing: show text "processing text here" + macOS-style indeterminate progress bar in agent color below it
- When complete: show one-liner result + status badge ("✓ Complete" or "✗ Failed") in agent color
- No conversation history in this view (scrap convo history per spec)

**Section 3 — Input (fixed height ~72pt)**
- Voice button (mic icon) + Text button (keyboard icon), both in agent color
- Tapping Text reveals multiline NSTextView/TextField with:
  - X in circle button to dismiss text field
  - Up-arrow in circle submit button
  - Enter key submits
  - Textbox clears immediately on submit then disappears

- Click outside expanded bubble → animate back to minimized state

**Acceptance:** Expand/collapse animation works. All three sections render correctly. Input works.

---

## PHASE 5 — Agent Voice & Text Input

### 5.1 Per-Agent Voice Input
**Progress:** `[x]`

- Voice button in expanded bubble starts listening immediately (no hotkey required)
- `Ctrl + Option` also starts/stops listening for the last active agent
- When listening:
  - Luma cursor switches to `.listening` state
  - Voice button pulses in agent color
  - Agent shape in minimized bubble pulses
- On speech end → transcribe (raw, no compression for agent mode) → send to agent API
- Stop listening: press voice button again, or `Ctrl + Option`

**Acceptance:** Voice button triggers listening. Cursor updates. Transcription uses raw text.

---

### 5.2 Agent Title Generation
**Progress:** `[x]`

- On first task submission to any agent:
  - Send a separate lightweight API call: `"Generate a 3-5 word title for this task: {task}. Return only the title, nothing else."`
  - Use the cheapest available model for this call (gpt-4o-mini or claude-haiku if available, else default model)
  - Set `agent.title` to result
  - Update bubble header immediately

**Acceptance:** Agent title appears in header after first task. Title is short and relevant.

---

### 5.3 New Agent via Voice Command
**Progress:** `[x]`

- Add intent detection to the task classifier: if user says "open a new agent" or "create a new agent" or "spawn agent" → call `AgentManager.shared.spawnAgent()`
- New agent spawns with random color + shape
- If a task follows the spawn command in the same utterance (e.g. "open a new agent and research metal cups"), extract the task and immediately start it in the new agent
- Hotkey `Ctrl + Cmd` also spawns a new agent

**Acceptance:** Voice command spawns agent. Hotkey spawns agent. Inline task starts immediately.

---

### 5.4 Agent Switching via Hotkeys
**Progress:** `[x]`

- `Ctrl + Option + 1` through `Ctrl + Option + 9` — switch focus to agent at that index in the stack
- `Ctrl + Option + Tab` — cycle to next agent
- "Focus" means: expand that agent's bubble, collapse any currently expanded bubble
- Register global NSEvent monitors for these key combos

**Acceptance:** Hotkeys switch agent focus correctly. Only one bubble expanded at a time.

---

## PHASE 6 — Autonomous Agent Mode

### 6.1 Agent Mode Toggle
**Progress:** `[x]`

- Add "Agent Mode" toggle to the main companion panel (not per-agent, global toggle)
- When OFF → Luma behaves as current guided walkthrough mode
- When ON → Luma operates Mac autonomously
- Toggle state persists to UserDefaults `luma.agentMode.enabled`
- Show a subtle indicator in the menu bar icon when agent mode is ON (e.g. colored dot)

**Acceptance:** Toggle switches between guide and autonomous mode. State persists.

---

### 6.2 Autonomous Task Execution Engine
**Progress:** `[x]`

Create `LumaAgentEngine.swift`:

- Receives task string + agent context
- Builds a multi-step action plan via Claude API (system prompt instructs Claude to return JSON array of actions)
- Action types:
  ```swift
  enum AgentAction {
      case click(coordinate: CGPoint)
      case type(text: String)
      case keyPress(key: String, modifiers: [String])
      case screenshot
      case wait(seconds: Double)
      case openApp(bundleId: String)
      case search(query: String)
  }
  ```
- Executes actions sequentially using CGEvent for clicks/keypresses, AX API for app interaction
- Updates `agent.processingText` on each action start
- On completion: sets `agent.completionText` + `agent.taskStatus`
- Saves to LumaMemoryManager history

**Acceptance:** Agent can click, type, open apps. Processing text updates per action.

---

### 6.3 Cursor Behaviour During Autonomous Mode
**Progress:** `[x]`

- When agent starts autonomous task: hide system cursor, show Luma cursor in `.processing` state
- Luma cursor moves to each click target with smooth animation (0.15s ease)
- If user moves physical mouse → detect via NSEvent global monitor → pause agent, restore system cursor, set agent to continue under the hood (no cursor) until user stops moving mouse for 2 seconds → resume cursor control
- On task complete: restore system cursor, hide Luma processing cursor

**Acceptance:** Luma cursor takes over during autonomous tasks. Mouse interruption handled gracefully.

---

### 6.4 Multi-Agent Conflict Resolution
**Progress:** `[x]`

In `LumaAgentEngine`:

- Before any click/type action, check `AgentManager.shared.isMouseInUse`
- If mouse is in use by another agent: find alternative (AX API direct interaction, keyboard shortcut, or wait 500ms and retry)
- `isMouseInUse` flag is set/cleared by whichever agent currently controls the cursor
- Only one agent may control the cursor at a time — queue-based lock

**Acceptance:** Two simultaneous agents do not conflict on cursor. Both complete their tasks.

---

### 6.5 Task Completion Notification
**Progress:** `[x]`

On agent task complete:

- Send macOS `UNUserNotification` with title = agent title, body = completion one-liner
- If task result involves a file (detected by checking if completion text contains a file path): add action button "Open Now" to notification
- Tapping "Open Now" opens the file after 3-10 second delay (configurable, default 5s)
- Agent bubble updates to show completion state

**Acceptance:** Notification fires on completion. File open action works.

---

## PHASE 7 — UI Polish & Animations (Hardest)

### 7.1 Physics-Based Bubble Interactions
**Progress:** `[ ]`

Implement physics simulation for agent bubbles:

- Use a simple spring physics model (not full SceneKit/SpriteKit — implement manually with a display link timer)
- Each bubble has velocity + position
- When a bubble enters processing state (violent shake), nearby bubbles within 80pt receive a force impulse proportional to distance
- Bubbles that are dragged and released have momentum (decay over 0.5s)
- Bubbles gently repel each other if overlapping (minimum 8pt separation)
- All physics updates run on a `CADisplayLink` at 60fps

**Acceptance:** Bubbles feel physically real. Processing shake propagates to neighbours. Drag has momentum.

---

### 7.2 Expanded Bubble Ease Animation
**Progress:** `[x]`

- Minimized → Expanded: spring animation (`response: 0.4, dampingFraction: 0.75`) scaling from 56x56 to full size, origin stays anchored to bubble position
- Expanded → Minimized: spring animation reverse, fade out content before scale down
- Background dim: when any bubble is expanded, add a subtle 20% black overlay behind it (not blocking other bubbles)
- All three sections inside the expanded bubble stagger-reveal with 80ms delay between each

**Acceptance:** Expand/collapse feels natural and polished. Stagger reveal works.

---

### 7.3 Full UI Overhaul — Companion Panel
**Progress:** `[x]`

Redesign `CompanionPanelView.swift`:

- Dark base: `#0A0A0F` background
- Subtle noise texture overlay (use a generated grain pattern via Core Image)
- Rounded corners (16pt), shadow with 30% opacity
- Typography: SF Pro Display for headers, SF Pro Text for body
- All buttons use agent/accent color with subtle glow on hover
- Smooth tab switching animation (cross-fade, 0.2s)
- Settings icon, close button — use SF Symbols with proper sizing
- Panel open/close: slide down from menu bar with spring animation

**Acceptance:** Panel looks premium and polished. All existing functionality intact.

---

### 7.4 Companion Bubble Overhaul
**Progress:** `[x]`

Redesign `CompanionBubbleWindow.swift`:

- Bubble background: `rgba(10, 10, 15, 0.85)` with backdrop blur
- Subtle animated gradient border (cycles through hues slowly, 8s loop)
- Response text renders markdown — use `AttributedString` with markdown support or embed a `WKWebView` for rich rendering
- Bubble resizes smoothly as content changes (spring animation on height change)
- Max width 380pt, min width 200pt
- Scroll for overflow content
- Step indicators (dots) for walkthrough mode showing current step / total

**Acceptance:** Bubble renders markdown. Resizes smoothly. Gradient border animates.

---

### 7.5 Final Integration & Regression Testing
**Progress:** `[x]`

- Run all existing `leanring-buddyTests` — fix any failures caused by new code
- Test guide mode (Agent Mode OFF) is completely unaffected by new agent system
- Test all hotkeys: `Ctrl+Option`, `Ctrl+Cmd`, `Ctrl+Option+Tab`, `Ctrl+Option+1-9`
- Test memory file creation, growth, and rotation
- Test autonomous mode with at least 3 simultaneous agents
- Test cursor customizer across all states
- Test voice settings apply correctly to TTS
- Performance check: Luma must remain under 150MB RAM with 3 active agents

**Acceptance:** All tests pass. No regressions. Memory under 150MB with 3 agents.

---

## Notes for Claude Code

- Work through phases in order. Do not start Phase 2 until all Phase 1 tasks are `[x]`.
- After completing each task, mark it `[x]` in this file and commit with message: `feat: complete task {number} — {task name}`
- If paused mid-task, mark it `[~]` and add a comment below it: `// PAUSED: {what was done, what remains}`
- Never modify existing walkthrough engine or guide mode behavior unless explicitly required by a task
- All new Swift files go in their logical folder: Core/, ML/, Walkthrough/, UI/, Overlay/, Agent/ (new folder)
- Create `Agent/` folder for: `LumaAgent.swift`, `AgentManager.swift`, `LumaAgentEngine.swift`, `AgentStackView.swift`, `AgentShapeView.swift`
- API keys for OpenAI agents go through the existing `ProfileManager` — add OpenAI as a new provider type
- Target: macOS 14.0+, Swift 5.9, SwiftUI + AppKit hybrid (existing pattern)
