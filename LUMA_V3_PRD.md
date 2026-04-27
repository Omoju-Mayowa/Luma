# Luma v3.0 — Product Requirements Document

## Directive

Rebuild Luma's UI and agent system to match OpenClicky exactly. This is a clean rebuild — every visual element, interaction pattern, and agent behavior must replicate OpenClicky's design language and architecture. The voice pipeline, screen capture, and core companion logic stay, but the shell around them changes completely.

---

## Progress Tracking Legend
- `[ ]` — Not started
- `[~]` — In progress
- `[x]` — Complete

---

## PHASE 1 — Design System Overhaul

### 1.1 Replace LumaTheme with OpenClicky Design System
**Progress:** `[x]` — DesignSystem.swift complete (1,462 lines)

Replace `LumaTheme.swift` with a new `DesignSystem.swift` (alias `DS`) containing these exact tokens:

**Color Palette**

| Token | Hex | Usage |
|-------|-----|-------|
| `background` | `#101211` | Deepest background layer |
| `surface1` | `#171918` | Cards, sidebar |
| `surface2` | `#202221` | Elevated surfaces, button resting |
| `surface3` | `#272A29` | Hover states, tooltips |
| `surface4` | `#2E3130` | Pressed states |
| `borderSubtle` | `#373B39` | Card outlines, dividers |
| `borderStrong` | `#444947` | Focused states |
| `textPrimary` | `#ECEEED` | Main text |
| `textSecondary` | `#ADB5B2` | Descriptions, hints |
| `textTertiary` | `#6B736F` | Labels, muted text |
| `textOnAccent` | `#FFFFFF` | Text on accent backgrounds |
| `success` | `#34D399` | Granted indicators, success states |
| `destructive` | `#E5484D` | Danger, close actions |
| `destructiveHover` | `#F2555A` | Destructive hover |
| `destructiveText` | `#FF6369` | Destructive text |
| `warning` | `#FFB224` | Warning states |
| `warningText` | `#F1A10D` | Warning text |
| `info` | `#70B8FF` | Info states |

**Accent Theme System (4 themes, user-switchable)**

| Theme | Accent | Hover | Text | Cursor |
|-------|--------|-------|------|--------|
| Blue (default) | `#2563EB` | `#1D4ED8` | `#60A5FA` | `#3380FF` |
| Mint | `#059669` | `#047857` | `#34D399` | `#35D39A` |
| Amber | `#D97706` | `#B45309` | `#FBBF24` | `#FACC15` |
| Rose | `#E11D48` | `#BE123C` | `#FB7185` | `#FF4F5E` |

Store selected theme in UserDefaults key `lumaAccentTheme`. Default is Blue.

**Floating Gradient (Jewel Effect)**
- Purple: `#8F46EB` → Pink: `#E84D9E` → Orange: `#FF8C33`

**Spacing**
- xs: 4pt, sm: 8pt, md: 12pt, lg: 16pt, xl: 20pt, xxl: 24pt, xxxl: 32pt

**Corner Radii**
- small: 6pt (tags, badges)
- medium: 8pt (buttons, inputs)
- large: 10pt (cards, chat bubbles)
- extraLarge: 12pt (panels, permission cards)
- pill: Capsule (infinite)

**Animation Durations**
- fast: 0.15s (hover, press feedback)
- normal: 0.25s (standard transitions)
- slow: 0.4s (fade-ins, celebrations)

**State Layer Opacities**
- hover: 0.08
- focus: 0.12
- pressed: 0.12
- dragged: 0.16

**Acceptance:** All existing views compile with DS tokens. No references to old LumaTheme remain. App launches with new dark palette.

---

### 1.2 Button Style System (7 Variants)
**Progress:** `[x]` — All 7 styles implemented in DesignSystem.swift

Implement all seven button styles as SwiftUI `ButtonStyle` conformances inside `DesignSystem.swift`:

**1. DSPrimaryButtonStyle** (Accent CTA)
- Font: 16pt, medium weight
- Padding: V 14pt, full width
- Background: Accent color
- Capsule shape
- Hover: Scale 1.0→1.03 over 0.6s + breathing glow (2.5s easeInOut loop, oscillates shadow radius 10→16pt, opacity 0.18→0.32)
- Press: Scale 0.97, brighten slightly
- Glow uses accent color as shadow color

**2. DSSecondaryButtonStyle** (Supporting)
- Font: 16pt, medium weight
- Padding: V 12pt, H 16pt
- Background: surface2 → surface3 (hover) → surface4 (press)
- Press: Scale 0.97

**3. DSTertiaryButtonStyle** (Ghost)
- Font: 16pt, medium weight
- Padding: V 8pt, H 12pt
- Text: textSecondary → accentText (hover) → accentHover (press)
- Background: transparent → surface2 (hover) → surface3 (press)

**4. DSTextButtonStyle** (Minimal inline)
- Font: 14pt, medium weight
- No background ever
- Text: textTertiary → textPrimary (hover/press)

**5. DSOutlinedButtonStyle** (Bordered)
- Font: 16pt, medium weight
- Padding: V 12pt, H 16pt
- Capsule with 1pt border
- Background: surface1 → surface2 (hover) → surface3 (press)
- Border: borderSubtle → borderStrong (hover/press)

**6. DSDestructiveButtonStyle** (Danger)
- Font: 16pt, medium weight
- Padding: V 10pt, H 16pt
- Background: destructive @10% → @30% (hover) → @40% (press)
- Border: destructive @15% → @40%
- Text: destructiveText → white (hover/press)

**7. DSIconButtonStyle** (Circular utility)
- Base size: 28pt (configurable)
- Icon: 43% of button size
- Circle: surface2 → surface3 (hover) → surface4 (press)
- Border: 1pt, borderSubtle @50% → borderStrong (hover/press)
- Press: Scale 0.93
- Tooltip support: 11pt font, surface3 @85%, 0.6s delay
- Tooltip shadow: black @42% radius 14 y:8 + black @26% radius 4 y:2

**Cursor Helpers**
- `PointerCursorView` — NSViewRepresentable that sets pointing-hand cursor via NSView cursor rects
- `IBeamCursorView` — NSViewRepresentable for text selection cursor
- `NativeTooltipView` — macOS-native tooltip system
- `.pointerOnHover()` view modifier wrapping PointerCursorView

**Acceptance:** All 7 styles render correctly. Breathing glow animates on primary buttons. Tooltips appear with delay. Pointer cursor shows on interactive elements.

---

### 1.3 Typography & Shadows
**Progress:** `[x]` — Done in DesignSystem.swift

**Typography** — System font (San Francisco) throughout:
- Headers: 14pt semibold
- Body: 11–12pt medium
- Labels: 10–11pt medium
- Monospaced: SF Mono or Menlo for keyboard hints and code
- Weights: semibold (default emphasis), bold (strong emphasis), medium (secondary text)

**Shadow Definitions**
- Panel Shadow: black @50% radius 20 y:10 + black @30% radius 4 y:2 (layered)
- Tooltip Shadow: black @42% radius 14 y:8 + black @26% radius 4 y:2
- HUD Shadow: black @34% radius 22 y:14
- Icon Glow: accent @72% radius 8

**Acceptance:** All text uses system font at correct sizes. Shadows match spec on all panels.

---

## PHASE 2 — Panel & Window Rebuild

### 2.1 Menu Bar Panel Manager
**Progress:** `[~]` — Modified by Codex, needs verification against spec

Rebuild `MenuBarPanelManager.swift` to match OpenClicky exactly:

**Status Item**
- NSStatusItem with programmatic triangle icon (rotated 35°, template image for system tint)
- Icon size: 18×18pt, triangle fills 70% of icon

**Panel Specs**
- Width: 356pt (fixed)
- Default height: 318pt
- Minimum size: 356×300pt
- Max transient height: 720pt
- Screen edge padding: 12pt
- Gap below menu bar icon: 4pt

**Panel Behavior**
- Borderless `NSPanel` with `.nonactivatingPanel` style
- Can become key but does not steal focus
- Transparent background (backgroundColor = .clear)
- Full-size content view (no titlebar padding)
- Click-outside-to-dismiss with 300ms delay (avoids closing on system permission dialogs)

**Pin/Unpin Mode**
- Pin: Switches to standard window style (titled, closable, miniaturizable, shadow)
- Unpin: Back to floating panel (borderless, no shadow, transparent)
- Pin button in header toggles between modes

**Positioning**
- Centers horizontally beneath status item
- Clamps to screen bounds with 12pt edge padding
- Content height change triggers panel resize (30ms debounce)

**Acceptance:** Panel appears below menu bar icon, auto-dismisses on click outside (unless pinned), resizes with content.

---

### 2.2 Companion Panel View — Full Rebuild
**Progress:** `[~]` — Partially converted to DS tokens, needs full rebuild to match spec

Rebuild `CompanionPanelView.swift` to match OpenClicky's layout exactly:

**Overall Container**
- Background: DS.background
- Corner radius: 12pt (continuous)
- Shadow: Panel shadow (black @50% radius 20 + black @30% radius 4)
- Border: white @10%, 0.5pt

**Section 1 — Header** (12pt vertical padding, 14pt horizontal)
- Left: "Luma" text (14pt, bold) + status dot (7×7pt) with glow + status text (11pt, semibold, tertiary)
- Right: Pin button (20×20pt circle, 8pt icon) + Close button (20×20pt circle, 9pt icon)
- Status dot colors: green (idle), blue (listening/processing), success (ready)
- Onboarding mode: Show only title + close button

**Divider** — 0.5pt horizontal line, borderSubtle

**Section 2 — Permissions** (T:15pt, H:14pt)
- Compact copy rows showing hotkey hints:
  - Voice mode: "Hold ⌃ + ⌥ to talk" with keyboard chip styling
  - Agent mode: "Say 'Hey Agent...' to spawn agents"
  - Text mode: "Control twice to enter text mode"
- Keyboard chip: H:6 V:4 padding, 4pt corner radius, white @10% background, white @14% border 1pt, 10–11pt monospaced font
- 4 permission rows (Microphone, Accessibility, Screen Recording, Screen Content):
  - 6pt vertical padding per row
  - Icon: 16pt width
  - Text: 13pt medium, secondary color
  - Granted state: 6pt green dot + "Granted" label (11pt, success color)
  - Action: "Grant" button (11pt semibold, accent background) + "Find App" drag-assist button
- Onboarding progress: "1 of 3" with progress bar, three-step flow

**Section 3 — Agent Mode Panel** (12pt top spacing, H:14pt)
- Only visible when agent mode is enabled
- Uses `AgentModePanelSection` component (see Task 4.2)

**Section 4 — Bottom Controls** (T:13pt, B:10pt, H:14pt)
- Cursor color selector: 4 theme buttons (Rose, Blue, Amber, Mint)
  - Each button: 28×28pt with small triangle cursor preview + colored glow
  - Selected: colored background + colored border
  - Unselected: white @5.5% background
- Footer: Memory button, Settings button, Quit button
- Version text (10pt, tertiary)

**Acceptance:** Panel matches OpenClicky pixel-for-pixel. All existing functionality preserved. Permissions flow works.

---

### 2.3 Settings Window — Full Rebuild
**Progress:** `[~]` — Sidebar layout started, has syntax errors from Codex code-gen (.font malformed)

Replace `SettingsPanelView.swift` and `LumaSettingsWindowManager.swift` with `LumaSettingsWindowManager.swift`:

**Window**
- Default: 860×580pt
- Minimum: 760×500pt
- Centered on screen
- Unified toolbar style

**Layout**
- Sidebar: 190pt width, regularMaterial background
- 1pt divider
- Content: Scrollable, max 660pt width, padding H:28 V:24

**Sidebar Tab Buttons** (7 tabs)

| Tab | Icon (SF Symbol) | Content |
|-----|------------------|---------|
| General | gearshape | Core behavior, cursor appearance, companion controls |
| Voice | waveform | Speech input, response model, TTS voice, API keys |
| Pointing | cursorarrow.rays | Screen capture, pointing model |
| Computer Use | macwindow.and.cursorarrow | CUA swift control, app discovery |
| Agent Mode | terminal | Background agents, model, working directory |
| Memory | books.vertical | Persistent memory, learned skills |
| App | app.badge | Onboarding, support, app actions |

- Selected: accent @18% background
- Hover: surface2 background
- Icon: 14pt, 20pt width
- Label: 12pt medium

**Section Headers**
- Title: 26pt semibold
- Subtitle: 13pt, secondary color

**Settings Groups**
- Background: controlBackgroundColor with 1pt border @8% opacity
- Corner radius: 10pt
- Spacing: 14pt between groups

**UI Elements**
- Toggle rows: H:12 spacing, icon 14pt (20pt width), V:11 padding
- Input fields: 12pt font, roundedBorder style
- Action buttons: 13pt medium with chevron indicator
- Model grids: 2 columns with 8pt spacing

**Voice Tab Contents** (from old SettingsPanelView)
- Gender toggle (Male/Female)
- Pitch slider (0.5–2.0)
- Rate/Tempo slider (0.1–1.0)
- Volume slider (0.0–1.0)
- Preview Voice button
- API key fields (AssemblyAI, OpenRouter)
- All values persist to UserDefaults

**General Tab Contents**
- Cursor color picker (4 accent themes with triangle preview)
- Cursor state customizer (shape, color, size per state — carry over from v2 cursor work)
- Log button → opens Log window

**Agent Mode Tab Contents**
- Enable/disable toggle
- Maximum agents stepper (1–10, default 3)
- Model picker per agent profile
- Working directory path

**Acceptance:** Settings window has 7 sidebar tabs. All existing settings relocated to correct tabs. Window is resizable, scrollable content.

---

## PHASE 3 — Overlay & Cursor System

### 3.1 Overlay Window Rebuild
**Progress:** `[ ]`

Rebuild `OverlayWindow.swift` to match OpenClicky exactly:

**Overlay Window**
- One per connected screen (covers entire screen)
- Level: `.screenSaver` (always on top)
- Click-through: `ignoresMouseEvents = true`
- Collection behavior: `canJoinAllSpaces`, `stationary`, `fullScreenAuxiliary`
- canBecomeKey: false
- Background: transparent
- No shadow, no halos

**Blue Cursor View (Triangle)**
- Size: 16×16pt
- Default rotation: -35°
- Color: Theme cursor color (default `#3380FF` for blue theme)
- Glow shadow: 8pt radius @100% opacity + dynamic `(scale-1)*20` extra radius

**Waveform View (Listening State)**
- 5 bars, 2pt width each, 2pt spacing
- Height profile: [0.4, 0.7, 1.0, 0.7, 0.4]
- Animation interval: 1/36s (28ms)
- Glow: 6pt radius @60% opacity
- Colors: Leading `#F3FBFF`, Trailing `#8FD2FF`, Glow `#AEE3FF`

**Spinner View (Processing State)**
- Size: 14×14pt
- Line width: 2.5pt
- Trim: 15% to 85%
- Rotation: 0.8s loop
- Glow: 6pt radius @60% opacity

**Cursor Following**
- 60fps timer (0.016s interval)
- Spring animation: response 0.2s, dampingFraction 0.6
- Offset from mouse: x+35, y+25

**Bezier Flight Arc**
- Duration: distance/800, clamped 0.6–1.4s
- Frame rate: 60fps timer-driven (NOT SwiftUI implicit animation)
- Arc height: distance × 0.2, max 80pt
- Scale pulse: sin curve 1.0→1.3× at apex
- Easing: smoothstep (3t²−2t³)
- Rotation: tangent to curve (cursor faces direction of travel)

**Speech Bubbles (Welcome & Navigation)**
- Font: 11pt, medium weight
- Text: white
- Padding: H:8, V:4
- Corner radius: 6pt
- Background: cursor color
- Glow: 6pt radius @50% opacity
- Position: 8px right, 12px below cursor

**Navigation Bubble Pop-In**
- Initial scale: 0.5×
- Final scale: 1.0×
- Spring: response 0.4s, dampingFraction 0.6
- Character streaming: 30–60ms per character
- Hold: 3 seconds after text completes, then 0.5s fade

**Welcome Animation**
- Text: "hey! i'm luma"
- 30ms per character, 2s hold, 0.5s fade

**Pointer Phrases** (random selection)
- "right here!", "this one!", "over here!", "click this!", "here it is!", "found it!"

**Return Flight Cancellation**
- Cancel by moving cursor >100px during return flight only (not forward flight)

**Acceptance:** Cursor follows mouse with spring physics. Flight arcs render with bezier curves. Waveform and spinner states match spec.

---

### 3.2 Companion Response Overlay
**Progress:** `[ ]`

Rebuild `CompanionResponseOverlay.swift`:

**Response Bubble**
- Background: rgba(10, 10, 15, 0.85) with backdrop blur
- Animated gradient border: 8s hue cycle through accent colors
- Max width: 380pt, min width: 200pt
- Corner radius: large (10pt)
- Markdown rendering via `AttributedString`
- Spring animation on height change (smooth resize as content streams)
- Scroll for overflow content
- Step indicators (dots) for walkthrough mode

**Acceptance:** Response bubble renders markdown, resizes smoothly, gradient border animates.

---

## PHASE 4 — Agent System Rebuild (OpenClicky-style)

### 4.1 Agent Session Model
**Progress:** `[ ]`

Replace the current `LumaAgent` bubble model with OpenClicky's session-based agent architecture.

Create `AgentSession.swift`:

```swift
struct AgentSession: Identifiable {
    let id: UUID
    var title: String
    var accentTheme: AccentTheme // Blue, Mint, Amber, Rose
    var status: AgentSessionStatus
    var workingDirectoryPath: String
    var model: String
    var entries: [AgentTranscriptEntry]
    var latestResponseCard: ResponseCard?
}

enum AgentSessionStatus {
    case stopped, starting, ready, running, failed
}

struct AgentTranscriptEntry: Identifiable {
    let id: UUID
    let role: TranscriptRole
    let text: String
    let createdAt: Date
}

enum TranscriptRole {
    case user, assistant, system, command, plan
}
```

**Role Colors:**
- user: accentText
- assistant: textSecondary
- system: destructiveText
- command: yellow @90%
- plan: purple @90%

**Acceptance:** Model compiles. Sessions can be created, updated, dismissed. Status transitions work.

---

### 4.2 Agent Mode Panel Section
**Progress:** `[ ]`

Create `AgentModePanelSection.swift` — the agent controls that appear inline in the companion panel:

**Container**
- Padding: 9pt all sides
- Background: white @4.5%
- Border: borderSubtle, 0.5pt
- Corner radius: large (10pt)

**Header Row**
- Status dot: 7×7pt, colored by session status:
  - stopped: tertiary
  - starting: warning (amber pulse)
  - ready: success (green)
  - running: accent (blue pulse)
  - failed: destructive (red)
- Status label: 12pt semibold (e.g. "AGENT", "STARTING", "WORKING", "NEEDS ATTENTION", "OFFLINE")
- Right side: Settings icon button + Model name (10pt, tertiary)

**Summary Text**
- Font: 11pt, tertiary color
- Fixed size with wrapping
- Shows current agent task or status description

**Agent Prompt Input**
- Placeholder: "Ask Luma to do something..."
- Font: 12pt
- Line limit: 1–3 lines
- Padding: H:10, V:7
- Background: white @7%
- Border: borderSubtle, 0.5pt (→ borderStrong on focus)
- Corner radius: medium (8pt)

**Error Display**
- Font: 10pt, destructiveText color
- Max 3 lines with wrapping

**Inline Response Box** (shows latest agent response)
- Padding: H:10, V:9
- Background: white @5.5%
- Border: borderSubtle @75%, 0.5pt
- Corner radius: medium (8pt)
- Label: 9pt, heavy weight, tertiary, uppercase, 0.45pt kerning ("AGENT RESPONSE")
- Text: 11pt, medium, max 5 lines

**Button Row** (8pt spacing)
- Dashboard button: Label style, 11pt semibold, secondary text → opens HUD window
- Send button: 42×30pt, icon only (paperplane.fill 12pt), accent background
- Disabled send: accent @35% opacity

**Acceptance:** Agent section renders in companion panel. Input submits to agent. Response box streams text. Status dot reflects session state.

---

### 4.3 Agent HUD Window (Dashboard)
**Progress:** `[ ]`

Create `LumaAgentHUDWindowManager.swift` — the full agent dashboard window:

**Window**
- Size: 594×452pt
- Minimum: 594×452pt
- Corner radius: 18pt
- Background: RGB(0.067, 0.075, 0.071) @98% opacity
- Border: white @10%, 1pt
- Shadow: black @34% radius 22 y:14
- Level: floating
- Non-activating panel

**Header** (H:12, V:7 padding)
- Left: Icon (12pt semibold, 24×24 circle background @12% opacity) + Title "Luma" (13pt, heavy weight)
- Right: Memory button (28pt icon) + Warm-up button (28pt icon) + Close button (28pt icon)

**Agent Team Strip** (horizontal scroll, 8pt spacing)
- Agent session buttons: 30pt circles
- Border: 0.8–1.4pt depending on selection state
- Shadow: theme-dependent opacity 0.10–0.34, radius 3–7pt
- Selected: thicker border + stronger shadow
- Add button: Plus icon (12pt heavy), 30×30pt circle
- Each agent uses its accent theme color

**Response Card** (below team strip)
- Shows latest response card from active agent
- Compact view: truncated text + source badge
- Action buttons: Dismiss, Run suggested action, Text follow-up, Voice follow-up

**Transcript Area** (scrollable)
- Spacing: 10pt between entries
- Padding: 10pt all sides
- Entry: 9pt padding, 9pt corner radius
- Entry text: 11pt
- Role label: 9pt bold, uppercase
- Auto-scrolls to bottom on new entries

**Composer Section** (10pt padding)
- Input: 11pt medium weight, 1–4 line limit
- Padding: H:10, V:9
- Run button: 76×32pt, 10pt corner radius
- Icon: 10pt bold, Text: 10pt heavy weight
- Accent background

**Acceptance:** HUD window opens from dashboard button. Shows agent team, transcript, composer. Multi-agent switching works.

---

### 4.4 Response Card System
**Progress:** `[ ]`

Create `ResponseCard.swift` and `ResponseCardView.swift`:

**ResponseCard Model**
```swift
struct ResponseCard: Identifiable {
    let id: UUID
    let source: ResponseCardSource
    var rawText: String
    var contextTitle: String?
    var suggestedActions: [String] // max 2
}

enum ResponseCardSource {
    case voice, agent, handoff
}
```

**Text Processing:**
- Strip `<NEXT_ACTIONS>...</NEXT_ACTIONS>` tags → extract as suggestedActions (max 2)
- Remove code blocks, excess markdown
- Truncate at 220 characters on word boundary for compact display

**ResponseCardCompactView**
- Shows truncated text + source badge
- Action buttons: Dismiss, Run suggested action (accent), Text follow-up, Voice follow-up
- Compact layout for HUD and panel embedding

**Integration Points:**
- Voice responses create response cards (source: `.voice`)
- Agent responses create response cards (source: `.agent`)
- Cards display in: overlay cursor area, agent HUD, companion panel agent section

**Acceptance:** Response cards display in all three contexts. Suggested actions extract correctly. Truncation works.

---

### 4.5 Agent Dock Window
**Progress:** `[ ]`

Create `LumaAgentDockWindowManager.swift` — floating dock showing active agents:

**Dock Item Model**
```swift
struct AgentDockItem: Identifiable {
    let id: UUID
    var title: String
    var accentTheme: AccentTheme
    var status: AgentSessionStatus
    var caption: String? // current task name
}
```

**Dock Window**
- Size: 520×190pt
- Floating, non-activating
- Transparent background

**Dock Item Rendering**
- Button size: 54×54pt, total frame 66×66pt with status indicator
- Border: 1.1pt with gradient (accent theme)
- Shadow: 24pt @30% + 15pt @62% + 10pt @50% black (layered)
- Status indicator: 9pt center dot with pulse halo animation
- Icon spacing: 10pt

**Hover Card**
- Width: 390pt
- Shows: title, status, caption, accent color
- Trailing inset: 10pt

**Acceptance:** Dock appears when agents are active. Items reflect session status. Hover cards show detail.

---

## PHASE 5 — Agent Engine & Execution

### 5.1 Agent Session Lifecycle
**Progress:** `[ ]`

Integrate agent sessions into `CompanionManager`:

- `agentSessions: [AgentSession]` — array of active sessions
- `activeAgentSessionID: UUID?` — currently selected session
- `agentDockItems: [AgentDockItem]` — derived from sessions for dock display

**Session Lifecycle:**
- Create: Spawns new session with random accent theme (cycles through Blue, Mint, Amber, Rose)
- Warm-up: Initializes connection, sets status to `.ready`
- Submit prompt: Sets status to `.running`, sends to API, streams response
- Complete: Sets status to `.ready`, creates response card
- Fail: Sets status to `.failed`, shows error in panel
- Dismiss: Removes session, cleans up

**Voice Integration:**
- "Hey Agent..." or "spawn agent" → creates new session
- Voice input routes to active agent session
- Agent voice commands use regex detection (carry over from `AgentVoiceIntegration`)

**Hotkeys:**
- Ctrl+Cmd+N: Spawn new agent session
- Ctrl+Option+Tab: Cycle active agent
- Ctrl+Option+1–9: Switch to agent at index

**Acceptance:** Sessions create, run, complete, dismiss. Voice spawning works. Hotkeys work.

---

### 5.2 Agent Runtime — Claude Code CLI + Claude API Hybrid
**Progress:** `[ ]`

Replace old `LumaAgentEngine.swift` with a dual-runtime agent system that mirrors OpenClicky's architecture.

**Runtime Detection (on app launch + periodic refresh):**
- Check for `claude` CLI via `Process("/bin/zsh", ["-c", "which claude"])` and common paths (`/usr/local/bin/claude`, `~/.claude/bin/claude`, `/opt/homebrew/bin/claude`)
- If found → `ClaudeCodeAgentRuntime` (default)
- If not found → `ClaudeAPIAgentRuntime` (fallback)
- Expose `activeRuntimeType` in Settings → Agent Mode tab so user can override
- Show runtime indicator in Agent Mode panel section (e.g., "Claude Code" badge or "Claude API" badge)
- Persist override to UserDefaults key `luma.agentRuntime.override` (values: `auto`, `claudeCode`, `claudeAPI`)

**Shared Protocol:**
```swift
protocol AgentRuntime: AnyObject {
    /// Start a new agent session. Transitions status to .starting then .ready.
    func startSession(id: UUID, task: String, workingDirectory: String, systemContext: String) async throws

    /// Submit a follow-up prompt to an existing session.
    func submitPrompt(sessionId: UUID, prompt: String) async throws

    /// Stop and tear down a session. Kills subprocess or cancels API task.
    func stopSession(sessionId: UUID) async

    /// Combine publisher for transcript entries (user, assistant, system, command, plan roles)
    var transcriptPublisher: AnyPublisher<AgentTranscriptEntry, Never> { get }

    /// Combine publisher for session status changes
    var statusPublisher: AnyPublisher<(UUID, AgentSessionStatus), Never> { get }
}
```

**ClaudeCodeAgentRuntime** (default — mirrors OpenClicky's Codex subprocess approach):
- Spawns `claude` CLI as a child process via Foundation `Process()`
- Launch arguments: `claude -p "<task>" --output-format stream-json --allowedTools "Bash,Read,Write,Edit,Glob,Grep" --dangerously-skip-permissions`
- Sets `currentDirectoryURL` to session working directory
- Pipes stdout → parse JSON stream for transcript entries (role, text, tool use)
- Pipes stderr → capture errors, set session to `.failed` on non-zero exit
- One `Process` per agent session, tracked by session UUID in `[UUID: Process]` dictionary
- `stopSession` sends `SIGTERM`, waits 2s, then `SIGKILL` if still running
- `startSession` validates `claude` binary exists before spawning (fall back to API runtime if gone)
- Session lifecycle: `.stopped` → `.starting` (process spawning) → `.ready` (first output received) → `.running` (actively producing output) → `.stopped`/`.failed`
- Environment: inherits user shell env, adds `CLAUDE_CODE_ENTRYPOINT=luma-agent`

**ClaudeAPIAgentRuntime** (fallback — tool-use loop):
- Uses existing `ClaudeAPI.swift` with extended tool definitions
- System prompt includes: memory summary, screenshot description (base64), working directory path
- Tool definitions sent to Claude:
  ```
  screenshot() → captures screen via CompanionScreenCaptureUtility, returns base64
  click(x: Int, y: Int) → CGEvent click at coordinates
  type(text: String) → CGEvent key-by-key typing
  key_press(key: String, modifiers: [String]) → CGEvent modified keypress
  open_app(bundleId: String) → NSWorkspace.open
  wait(seconds: Double) → Task.sleep
  bash(command: String) → Process() shell execution, returns stdout/stderr
  ```
- Execution loop: send message → receive tool_use → execute locally → send tool_result → repeat until no more tool calls
- Each tool execution emits a transcript entry (role: `.command`)
- Queue-based cursor lock for multi-agent conflict resolution (only one session controls cursor at a time)
- User mouse movement pauses agent cursor control (2s timeout to resume)
- Max 50 tool-use iterations per prompt (safety limit)

**AgentRuntimeManager** (singleton, owns runtime lifecycle):
- `@Published var detectedRuntime: RuntimeType` — `.claudeCode` or `.claudeAPI`
- `@Published var activeRuntime: any AgentRuntime`
- `func detectRuntime()` — runs on launch and when user opens Agent Mode settings
- `func createRuntime(for type: RuntimeType) -> any AgentRuntime`
- Subscribes to both publishers and re-emits on `@MainActor`

**Files to create:**
- `leanring-buddy/Agent/AgentRuntime.swift` — protocol + `AgentRuntimeManager`
- `leanring-buddy/Agent/ClaudeCodeAgentRuntime.swift` — CLI subprocess runtime
- `leanring-buddy/Agent/ClaudeAPIAgentRuntime.swift` — API tool-use runtime

**Files to remove (Codex abstractions that don't match OpenClicky):**
- `leanring-buddy/Agent/AgentExecutionModels.swift`
- `leanring-buddy/Agent/ClaudeAgentRuntime.swift`
- `leanring-buddy/Agent/AgentSessionMemoryStore.swift`
- `leanring-buddy/LumaTests/ClaudeAgentRuntimeStateTests.swift`
- `leanring-buddy/LumaTests/AgentExecutionCoordinatorTests.swift`

**Acceptance:** Claude Code CLI detected and used when available. Falls back to Claude API cleanly. Transcript streams in real-time. Sessions start/stop/fail correctly. Runtime indicator shows in panel.

---

### 5.3 Agent Title Generation
**Progress:** `[ ]`

On first prompt submitted to any agent session:
- Send lightweight API call: "Generate a 3–5 word title for this task: {task}. Return only the title."
- Use cheapest available model
- Update session title + dock item title immediately

**Acceptance:** Agent title appears after first task. Title is short and descriptive.

---

## PHASE 6 — Memory & Persistence

### 6.1 Memory Manager
**Progress:** `[ ]`

Carry over `LumaMemoryManager.swift` with updates for session model:

- `memory.md` — global markdown, AI persona + preferences
- `history/agent_{sessionId}_{timestamp}.json` — per-session conversation history
- Auto-rotate at 2MB
- `appendToHistory(sessionId:, entry:)` — appends transcript entry
- `loadMemory() -> String` — returns memory.md contents
- `searchHistory(query:) -> [ConversationEntry]` — keyword search across JSON files
- `updateMemory(newFact:)` — appends to memory.md with timestamp
- Memory summarized to max 500 tokens before prepending to API calls

**Storage:** `~/Library/Application Support/Luma/`

**Acceptance:** Files created correctly. History appends per session. Memory loads and summarizes.

---

### 6.2 Memory Integration
**Progress:** `[ ]`

- On session create: load memory.md, prepend summarized context to first API call
- After completed task: append to history
- Memory button in HUD header and companion panel footer → opens memory viewer
- Memory viewer: 1180×860pt default, 760×520pt minimum

**Acceptance:** Agent has memory context. History searchable. Memory viewer opens.

---

## PHASE 7 — Voice & Input

### 7.1 Voice Settings
**Progress:** `[ ]`

In Settings → Voice tab:
- Gender toggle (Male/Female) → maps to AVSpeechSynthesisVoice identifiers
- Pitch slider (0.5–2.0, AVSpeechUtterance.pitchMultiplier)
- Rate slider (0.1–1.0, AVSpeechUtterance.rate)
- Volume slider (0.0–1.0, AVSpeechUtterance.volume)
- Preview Voice button
- Persist to UserDefaults: `luma.voice.gender`, `.pitch`, `.rate`, `.volume`
- NativeTTSClient reads values before each utterance

**Acceptance:** Voice changes apply on next response. Preview works.

---

### 7.2 Agent Mode Toggle
**Progress:** `[ ]`

- Global toggle in companion panel (not per-agent)
- OFF: Luma behaves as guided walkthrough/companion mode
- ON: Agent mode panel section appears, autonomous operation enabled
- Persists to UserDefaults `luma.agentMode.enabled`
- Subtle indicator on menu bar icon when ON (colored dot on status item)

**Acceptance:** Toggle switches modes. Panel section visibility follows toggle. State persists.

---

### 7.3 Cursor State System
**Progress:** `[ ]`

Carry over `LumaCursorState` enum and `CursorProfile`:

**States:** idle, pointing, listening, processing, hover

**CursorProfile** (persisted to Keychain):
- Per-state: shape, color (hex), size
- Shapes: teardrop, circle, roundedTriangle, diamond, cross, dot
- Size range: 8–32pt
- Default matches blue accent theme cursor

**CustomCursorManager:**
- Reads profile from Keychain on init
- `setState(_:)` switches active cursor
- Redraws NSImage per state
- Renders glow per shape

**Cursor Customizer UI** in Settings → General:
- Section per state with shape picker, color picker (NSColorWell), size slider
- Live preview: 200×200pt dark rounded rect showing cursor in real time
- "Reset to Default" button

**Acceptance:** Cursor changes per state. Customizer updates live preview. Profile persists.

---

## PHASE 8 — Polish & Integration

### 8.1 Log Window
**Progress:** `[ ]`

`LumaLogWindowManager.swift`:
- Non-modal NSWindow titled "Luma Activity Log"
- Resizable, minimum 700×400pt
- Monospaced NSTextView (SF Mono or Menlo)
- Real-time log entries: `[HH:mm:ss] message`
- Auto-scroll to bottom
- Clear button (clears view, not file)
- LumaLogger singleton with Combine `liveLogEntryPublisher`
- All `print()` statements → `LumaLogger.shared.log()`
- File: `~/Library/Logs/Luma/luma.log`, auto-rotate at 2MB

**Acceptance:** Log window shows real-time activity. Clear works. Auto-scrolls.

---

### 8.2 Migration & Cleanup
**Progress:** `[ ]`

Remove all old agent bubble code that doesn't fit the new architecture:

**Remove (old v2 agent bubble code):**
- `AgentStackView.swift` (old bubble-based overlay) — replaced by Agent Dock
- `AgentShapeView.swift` (old shape rendering) — no longer needed
- `AgentBubblePhysics.swift` (old physics engine) — no longer needed
- `CompanionBubbleWindow.swift` — functionality merged into overlay + response card system
- Old `LumaAgent.swift` model — replaced by `AgentSession`
- Old `AgentManager.swift` — replaced by session management in CompanionManager
- Old `AgentProfile.swift` — replaced by session accent themes

**Remove (Codex rebuild abstractions that don't match OpenClicky):**
- `AgentExecutionModels.swift` — stubbed coordinator, hesitation states, not in OpenClicky
- `ClaudeAgentRuntime.swift` — replaced by `AgentRuntime` protocol + dual implementations
- `AgentSessionMemoryStore.swift` — merged into `LumaMemoryManager`
- `LumaTests/ClaudeAgentRuntimeStateTests.swift` — tests for removed code
- `LumaTests/AgentExecutionCoordinatorTests.swift` — tests for removed code

**Fix (Codex code-gen bugs):**
- `SettingsPanelView.swift` — fix all malformed `.font(.system(size: 13)Medium)` → `.font(.system(size: 13, weight: .medium))`
- Remove any `ClaudeAgentRuntimeAPI` protocol conformance from `ClaudeAPI.swift`
- Remove `ClaudeAgentRequest` struct from `ClaudeAPI.swift`

**Rename/Update:**
- All `LumaTheme.*` references → `DS.*`
- `AgentSettingsManager` → merge into settings window Agent Mode tab
- `AgentHotkeyHandler` → keep but update for session-based switching
- `AgentVoiceIntegration` → keep but update for session spawning
- `AgentMemoryIntegration` → keep but update for session model

**Keep Unchanged:**
- Voice pipeline (`BuddyDictationManager`, transcription providers, `GlobalPushToTalkShortcutMonitor`)
- Screen capture (`CompanionScreenCaptureUtility`)
- API clients (`ClaudeAPI`, `OpenAIAPI`)
- TTS (`ElevenLabsTTSClient`)
- Element detection (`ElementLocationDetector`, `LumaImageProcessingEngine`, `LumaMobileNetDetector`)
- Analytics (`LumaAnalytics`)
- Keychain management (`KeychainManager`)
- Account management (`AccountManager`)

**Acceptance:** Old bubble code removed. All DS references compile. No dead code remains.

---

### 8.3 Final Integration & Regression
**Progress:** `[ ]`

- All existing `leanring-buddyTests` pass
- Guide mode (Agent Mode OFF) works identically to before
- All hotkeys work: Ctrl+Option (voice), Ctrl+Cmd+N (spawn agent), Ctrl+Option+Tab (cycle), Ctrl+Option+1–9 (switch)
- Memory file creation, growth, rotation works
- Autonomous mode with 3 simultaneous agent sessions
- Cursor customizer across all states
- Voice settings apply to TTS
- Agent HUD: team strip, transcript, composer all functional
- Agent dock items reflect active sessions
- Response cards display in overlay, HUD, and panel
- Performance: under 150MB RAM with 3 active agents
- Settings window: all 7 tabs render correctly with correct content

**Acceptance:** All tests pass. No regressions. Performance target met.

---

## Notes for Claude Code

- Work through phases in order. Do not start Phase N+1 until all Phase N tasks are `[x]`.
- After completing each task, mark it `[x]` in this file and commit: `feat: complete task {number} — {task name}`
- If paused mid-task, mark `[~]` and add: `// PAUSED: {done, remaining}`
- Reference `/Users/nox/Desktop/openclicky` for exact visual implementation details when coding any UI component.
- All new Swift files go in logical locations: Agent/, UI/, Overlay/, Core/
- The "leanring" typo in the project directory and scheme is intentional/legacy — do NOT rename.
- Target: macOS 14.0+, Swift 5.9, SwiftUI + AppKit hybrid
- Do NOT run `xcodebuild` — it invalidates TCC permissions
- Do NOT fix known non-blocking warnings (Swift 6 concurrency, deprecated onChange)
