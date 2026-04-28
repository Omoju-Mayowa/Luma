# Luma v3 — OpenClicky UI & Agent Rebuild

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild Luma's design system, panel UI, settings, overlay, and agent architecture to exactly match OpenClicky's visual design and session-based agent model.

**Architecture:** Replace LumaTheme with OpenClicky's DS token system. Replace bubble-based multi-agent with session-based agents (AgentSession + HUD + Dock + ResponseCards). Rebuild all panels and overlays to match OpenClicky dimensions/colors/animations exactly. Keep voice pipeline, screen capture, element detection, and API clients unchanged.

**Tech Stack:** SwiftUI + AppKit hybrid, macOS 14.0+, Swift 5.9, NSPanel for floating windows, CGEvent for agent cursor control.

**Reference Codebase:** `/Users/nox/Desktop/openclicky/leanring-buddy/` — port UI code from here, adapting names (OpenClicky→Luma, Clicky→Luma).

---

## Task 1: Create DesignSystem.swift

**Files:**
- Create: `leanring-buddy/DesignSystem.swift`
- Reference: `/Users/nox/Desktop/openclicky/leanring-buddy/DesignSystem.swift`

- [ ] **Step 1: Port the design system file**

Copy `/Users/nox/Desktop/openclicky/leanring-buddy/DesignSystem.swift` to `leanring-buddy/DesignSystem.swift`. Then make these search-and-replace changes:
- Replace `openClicky` → `luma` in UserDefaults keys
- Replace `ClickyAccentTheme` → `LumaAccentTheme`
- Replace `clickyAccentTheme` → `lumaAccentTheme`
- Replace `BuddyComposerVisualStyle` → `LumaComposerVisualStyle`
- Keep ALL color hex values, spacing, corner radii, animation durations, and button styles exactly as-is
- Keep ALL 7 button styles: DSPrimaryButtonStyle, DSSecondaryButtonStyle, DSTertiaryButtonStyle, DSTextButtonStyle, DSOutlinedButtonStyle, DSDestructiveButtonStyle, DSIconButtonStyle
- Keep PointerCursorView, IBeamCursorView, NativeTooltipView
- Keep all view modifier extensions (.pointerCursor, .nativeTooltip, etc.)

The file should be ~966 lines, containing:
- `LumaAccentTheme` enum (blue/mint/amber/rose) with accent/hover/text/cursor colors
- `DS` enum namespace with Colors, Spacing, CornerRadius, Animation, StateLayer
- All 7 ButtonStyle conformances with exact hover/press/glow animations
- `LumaComposerVisualStyle` waveform colors
- `PointerCursorView`, `IBeamCursorView`, `NativeTooltipView` (NSViewRepresentable)
- `Color.init(hex:)` and `Color.blendedWithWhite(fraction:)` extensions

- [ ] **Step 2: Add to Xcode project**

Open `leanring-buddy.xcodeproj` in Xcode and add `DesignSystem.swift` to the leanring-buddy target. Verify it compiles with no errors.

- [ ] **Step 3: Commit**

```bash
git add leanring-buddy/DesignSystem.swift
git commit -m "feat: add OpenClicky-style design system (DS tokens, 7 button styles, accent themes)"
```

---

## Task 2: Migrate All LumaTheme References to DS

**Files:**
- Modify: `leanring-buddy/CompanionPanelView.swift`
- Modify: `leanring-buddy/SettingsPanelView.swift`
- Modify: `leanring-buddy/MenuBarPanelManager.swift`
- Modify: `leanring-buddy/OverlayWindow.swift`
- Modify: `leanring-buddy/CompanionResponseOverlay.swift`
- Modify: `leanring-buddy/CompanionBubbleWindow.swift`
- Modify: `leanring-buddy/OnboardingWizardView.swift`
- Modify: `leanring-buddy/LumaWriteEngine.swift`
- Modify: `leanring-buddy/AccountManager.swift`
- Modify: `leanring-buddy/PINEntryView.swift`
- Modify: `leanring-buddy/Agent/AgentStackView.swift`
- Remove: `leanring-buddy/LumaTheme.swift`

- [ ] **Step 1: Create migration mapping**

Map old LumaTheme tokens to new DS tokens:

```
LumaTheme.Colors.background (#0A0A0F)      → DS.Colors.background (#101211)
LumaTheme.Colors.surface (#141414)          → DS.Colors.surface1 (#171918)
LumaTheme.Colors.surfaceElevated (#1C1C1C)  → DS.Colors.surface2 (#202221)
LumaTheme.Colors.textPrimary (white)        → DS.Colors.textPrimary (#ECEEED)
LumaTheme.Colors.textSecondary (#B0B0B0)    → DS.Colors.textSecondary (#ADB5B2)
LumaTheme.Colors.textPlaceholder (#656565)  → DS.Colors.textTertiary (#6B736F)
LumaTheme.Colors.accent (white)             → DS.Colors.accent (theme-based)
LumaTheme.Colors.accentForeground (black)   → DS.Colors.textOnAccent (white)
LumaTheme.Colors.destructive               → DS.Colors.destructive (#E5484D)
LumaTheme.Colors.success                   → DS.Colors.success (#34D399)
LumaTheme.Colors.warning                   → DS.Colors.warning (#FFB224)
LumaTheme.Colors.companionColor (#0A84FF)   → DS.Colors.overlayCursorBlue (theme cursor)
LumaTheme.Spacing.xs (4)                   → DS.Spacing.xs (4)
LumaTheme.Spacing.sm (8)                   → DS.Spacing.sm (8)
LumaTheme.Spacing.md (16)                  → DS.Spacing.md (12) ← NOTE: different value
LumaTheme.Spacing.lg (24)                  → DS.Spacing.lg (16) ← NOTE: different value
LumaTheme.Spacing.xl (32)                  → DS.Spacing.xl (20)
LumaTheme.Spacing.xxl (40)                 → DS.Spacing.xxl (24)
LumaTheme.CornerRadius.sm (6)              → DS.CornerRadius.small (6)
LumaTheme.CornerRadius.md (10)             → DS.CornerRadius.large (10)
LumaTheme.CornerRadius.lg (16)             → DS.CornerRadius.extraLarge (12) ← NOTE: different
LumaTheme.CornerRadius.full (999)          → DS.CornerRadius.pill (infinity)
LumaTheme.Animation.fast (0.15)            → DS.Animation.fast (0.15)
LumaTheme.Animation.normal (0.25)          → DS.Animation.normal (0.25)
LumaTheme.Animation.slow (0.4)             → DS.Animation.slow (0.4)
LumaTheme.Typography.caption (11)          → Font.system(size: 11)
LumaTheme.Typography.body (13)             → Font.system(size: 13)
LumaTheme.Typography.headline (15)         → Font.system(size: 15, weight: .semibold)
LumaTheme.Typography.title (20)            → Font.system(size: 20, weight: .semibold)
```

- [ ] **Step 2: Replace references in each file**

For each of the 11 files listed, do a systematic find-and-replace:
- `LumaTheme.Colors.` → appropriate `DS.Colors.` token
- `LumaTheme.Spacing.` → appropriate `DS.Spacing.` token
- `LumaTheme.CornerRadius.` → appropriate `DS.CornerRadius.` token
- `LumaTheme.Animation.` → appropriate `DS.Animation.` token
- `LumaTheme.Typography.caption` → `Font.system(size: 11)`
- `LumaTheme.Typography.body` → `Font.system(size: 13)`
- etc.

Where `DS.Colors.accent` is needed (theme-aware), use:
```swift
LumaAccentTheme.current.accent
LumaAccentTheme.current.accentHover
LumaAccentTheme.current.accentText
```

- [ ] **Step 3: Handle companion-specific tokens**

Replace companion shape/morph references:
- `LumaTheme.CompanionShape` usage → remove (no longer needed, cursor is always triangle)
- `LumaTheme.companionColor` → `LumaAccentTheme.current.cursorColor`
- `LumaTheme.companionBorderColor` → `DS.Colors.borderSubtle`
- `NoiseTextureView` — keep if used in overlays, but move to DesignSystem.swift if referenced

- [ ] **Step 4: Delete LumaTheme.swift**

Remove `leanring-buddy/LumaTheme.swift` from the project and filesystem.

- [ ] **Step 5: Build and verify**

Open in Xcode, build (Cmd+B). Fix any remaining compile errors from missed references. The app should launch with the new darker color palette (#101211 background instead of #0A0A0F).

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "refactor: migrate all LumaTheme references to DS design system, remove LumaTheme.swift"
```

---

## Task 3: Rebuild MenuBarPanelManager

**Files:**
- Modify: `leanring-buddy/MenuBarPanelManager.swift`
- Reference: `/Users/nox/Desktop/openclicky/leanring-buddy/MenuBarPanelManager.swift`

- [ ] **Step 1: Rewrite MenuBarPanelManager**

Port the OpenClicky `MenuBarPanelManager` structure. Key specs:

```swift
// Panel dimensions
private let panelWidth: CGFloat = 356
private let defaultPanelHeight: CGFloat = 318
private let minimumPanelWidth: CGFloat = 356
private let minimumPanelHeight: CGFloat = 300
private let transientMaxHeight: CGFloat = 720
private let screenEdgePadding: CGFloat = 12
private let gapBelowMenuBar: CGFloat = 4
```

Status item icon: Programmatic triangle (rotated 35°, template image, 18×18pt, triangle fills 70%).

Panel: Borderless `NSPanel` with:
- `.nonactivatingPanel` style mask
- `canBecomeKey = true` (for text fields)
- `backgroundColor = .clear`
- `isMovableByWindowBackground = false` (transient mode)
- Full-size content view
- Click-outside monitor with 300ms delay

Pin/unpin toggle:
- Pinned: `.titled`, `.closable`, `.miniaturizable`, `.resizable` + shadow
- Unpinned: `.nonactivatingPanel`, `.fullSizeContentView` + no shadow + transparent

Positioning: Center horizontally beneath status item, clamp to screen bounds with 12pt edge padding.

Content height observation: Use SwiftUI `PreferenceKey` to report height, resize panel (30ms debounce).

- [ ] **Step 2: Build and verify**

Panel should appear below menu bar icon on click. Click outside dismisses. Pin button toggles window chrome.

- [ ] **Step 3: Commit**

```bash
git add leanring-buddy/MenuBarPanelManager.swift
git commit -m "feat: rebuild MenuBarPanelManager with OpenClicky panel behavior (pin/unpin, click-outside-dismiss)"
```

---

## Task 4: Rebuild CompanionPanelView

**Files:**
- Modify: `leanring-buddy/CompanionPanelView.swift`
- Reference: `/Users/nox/Desktop/openclicky/leanring-buddy/CompanionPanelView.swift`

- [ ] **Step 1: Rebuild header section**

```swift
// Header: 12pt vertical, 14pt horizontal padding
HStack(spacing: DS.Spacing.sm) {
    // "Luma" title
    Text("Luma")
        .font(.system(size: 14, weight: .bold))
        .foregroundColor(DS.Colors.textPrimary)

    // Status dot (7x7) with glow
    Circle()
        .fill(statusDotColor)
        .frame(width: 7, height: 7)
        .shadow(color: statusDotColor.opacity(0.6), radius: 4)

    // Status text
    Text(statusText)
        .font(.system(size: 11, weight: .semibold))
        .foregroundColor(DS.Colors.textTertiary)

    Spacer()

    // Pin button (20x20)
    Button(action: togglePin) {
        Image(systemName: isPinned ? "pin.fill" : "pin")
            .font(.system(size: 8))
    }
    .dsIconButtonStyle(size: 20)

    // Close button (20x20)
    Button(action: closePanel) {
        Image(systemName: "xmark")
            .font(.system(size: 9, weight: .semibold))
    }
    .dsIconButtonStyle(size: 20)
}
.padding(.vertical, 12)
.padding(.horizontal, 14)
```

Status dot colors:
- idle: `DS.Colors.success` (green)
- listening/processing: `LumaAccentTheme.current.accent` (blue)
- ready: `DS.Colors.success`

- [ ] **Step 2: Rebuild permissions section**

Copy display rows (T:15, H:14 padding):
- Hotkey hint chips with monospaced font:
  ```swift
  Text("⌃").font(.system(size: 10, design: .monospaced))
      .padding(.horizontal, 6).padding(.vertical, 4)
      .background(Color.white.opacity(0.10))
      .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.14), lineWidth: 1))
  ```
- 4 permission rows: icon (16pt), text (13pt medium, secondary), status badge (6pt dot + "Granted" 11pt success)
- Grant buttons: 11pt semibold, accent background

- [ ] **Step 3: Add agent mode panel section placeholder**

Add a conditional section that shows `AgentModePanelSection` when agent mode is enabled:
```swift
if companionManager.isAgentModeEnabled {
    AgentModePanelSection(/* bindings */)
        .padding(.top, 12)
        .padding(.horizontal, 14)
}
```
This will be implemented fully in Task 9. For now, just reserve the space with a placeholder view.

- [ ] **Step 4: Rebuild bottom controls**

Cursor color selector (T:13, B:10, H:14 padding):
```swift
HStack(spacing: DS.Spacing.sm) {
    ForEach(LumaAccentTheme.allCases, id: \.self) { theme in
        Button(action: { setAccentTheme(theme) }) {
            // 28x28 button with small triangle preview + glow
            ZStack {
                Circle()
                    .fill(isSelected ? theme.accent.opacity(0.2) : Color.white.opacity(0.055))
                    .frame(width: 28, height: 28)
                // Triangle cursor preview
                Image(systemName: "arrowtriangle.up.fill")
                    .font(.system(size: 10))
                    .foregroundColor(theme.cursorColor)
                    .rotationEffect(.degrees(-35))
            }
            .overlay(Circle().stroke(isSelected ? theme.accent : Color.clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .pointerCursor()
    }
}
```

Footer: Memory button, Settings button (→ opens settings window), Quit button. Version text (10pt, tertiary).

- [ ] **Step 5: Wire up overall layout**

Full panel structure:
```swift
VStack(spacing: 0) {
    headerSection        // Step 1
    Divider().background(DS.Colors.borderSubtle)
    permissionsSection   // Step 2
    agentModeSection     // Step 3 (conditional)
    Spacer(minLength: 0)
    bottomControls       // Step 4
}
.frame(width: 356)
.background(DS.Colors.background)
.clipShape(RoundedRectangle(cornerRadius: DS.CornerRadius.extraLarge, style: .continuous))
.shadow(color: .black.opacity(0.5), radius: 20, y: 10)
.shadow(color: .black.opacity(0.3), radius: 4, y: 2)
.overlay(RoundedRectangle(cornerRadius: DS.CornerRadius.extraLarge, style: .continuous)
    .stroke(Color.white.opacity(0.10), lineWidth: 0.5))
```

- [ ] **Step 6: Build and verify**

Panel renders with dark background, header with status dot, permissions rows, cursor color picker, footer buttons.

- [ ] **Step 7: Commit**

```bash
git add leanring-buddy/CompanionPanelView.swift
git commit -m "feat: rebuild CompanionPanelView with OpenClicky layout (header, permissions, color picker)"
```

---

## Task 5: Create Settings Window

**Files:**
- Create or Modify: `leanring-buddy/LumaSettingsWindowManager.swift`
- Remove: `leanring-buddy/SettingsPanelView.swift` (after migration)
- Reference: `/Users/nox/Desktop/openclicky/leanring-buddy/OpenClickySettingsWindowManager.swift`

- [ ] **Step 1: Create LumaSettingsWindowManager**

Port from OpenClicky's `OpenClickySettingsWindowManager`. Key specs:

```swift
@MainActor
final class LumaSettingsWindowManager {
    private var window: NSWindow?

    func show(companionManager: CompanionManager) {
        if let existingWindow = window {
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }
        let contentView = LumaSettingsView(companionManager: companionManager)
        let hostingView = NSHostingView(rootView: contentView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 580),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 760, height: 500)
        window.contentView = hostingView
        window.center()
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.backgroundColor = NSColor(DS.Colors.background)
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }
}
```

- [ ] **Step 2: Create LumaSettingsView with sidebar**

```swift
struct LumaSettingsView: View {
    @ObservedObject var companionManager: CompanionManager
    @State private var selectedTab: SettingsTab = .general

    enum SettingsTab: String, CaseIterable {
        case general, voice, pointing, computerUse, agentMode, memory, app

        var title: String { /* General, Voice, Pointing, Computer Use, Agent Mode, Memory, App */ }
        var icon: String { /* gearshape, waveform, cursorarrow.rays, macwindow.and.cursorarrow, terminal, books.vertical, app.badge */ }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar (190pt, regularMaterial)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    Button(action: { selectedTab = tab }) {
                        HStack(spacing: DS.Spacing.md) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 14))
                                .frame(width: 20)
                            Text(tab.title)
                                .font(.system(size: 12, weight: .medium))
                        }
                        .padding(.vertical, 11)
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(selectedTab == tab ?
                            LumaAccentTheme.current.accent.opacity(0.18) :
                            Color.clear)
                        .cornerRadius(DS.CornerRadius.medium)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(DS.Spacing.sm)
            .frame(width: 190)
            .background(.regularMaterial)

            Divider()

            // Content (scrollable, max 660pt, padding H:28 V:24)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    settingsContent(for: selectedTab)
                }
                .frame(maxWidth: 660, alignment: .leading)
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
```

- [ ] **Step 3: Migrate Voice tab content**

Move voice settings from old `SettingsPanelView` voice section:
- Gender toggle, Pitch slider, Rate slider, Volume slider, Preview button
- API key fields (AssemblyAI, OpenRouter)
- All UserDefaults keys stay the same

Section header: 26pt semibold title + 13pt secondary subtitle.
Settings groups: controlBackgroundColor with 1pt border @8%, 10pt corner radius.

- [ ] **Step 4: Migrate General tab content**

- Cursor color picker (4 accent themes with triangle preview)
- Cursor state customizer (shape/color/size per state from old cursor settings)
- Log button → `LumaLogWindowManager.shared.show()`

- [ ] **Step 5: Create Agent Mode tab**

- Enable/disable toggle (persists `luma.agentMode.enabled`)
- Max agents stepper (1–10, default 3)
- Model picker (grid, 2 columns, 8pt spacing)
- Working directory path field

- [ ] **Step 6: Create remaining tabs**

- **Pointing**: Screen capture model selection
- **Computer Use**: Placeholder for CUA controls
- **Memory**: Memory viewer button, memory stats
- **App**: Quit button (destructive), version info

- [ ] **Step 7: Remove old SettingsPanelView.swift**

Delete `leanring-buddy/SettingsPanelView.swift`. Update any references to open settings to use `LumaSettingsWindowManager.shared.show()` instead.

- [ ] **Step 8: Build and verify**

Settings window opens with 7-tab sidebar. Content scrolls. All migrated settings work.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "feat: create 7-tab settings window replacing old SettingsPanelView"
```

---

## Task 6: Rebuild OverlayWindow

**Files:**
- Modify: `leanring-buddy/OverlayWindow.swift`
- Reference: `/Users/nox/Desktop/openclicky/leanring-buddy/OverlayWindow.swift`

- [ ] **Step 1: Update overlay window configuration**

Ensure window properties match:
```swift
window.level = .screenSaver
window.ignoresMouseEvents = true
window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
window.canBecomeKey = false  // CRITICAL: must not steal focus
window.backgroundColor = .clear
window.hasShadow = false
```

- [ ] **Step 2: Update BlueCursorView triangle rendering**

Triangle cursor specs:
```swift
// Size: 16x16, rotation: -35°, color: theme cursor
let cursorSize: CGFloat = 16
let cursorRotation: Angle = .degrees(-35)
let cursorColor = LumaAccentTheme.current.cursorColor

// Glow shadow
.shadow(color: cursorColor, radius: 8)
.shadow(color: cursorColor.opacity(max(0, scale - 1) * 20 / 20), radius: max(0, (scale - 1) * 20))
```

- [ ] **Step 3: Update waveform view**

```swift
// 5 bars, 2pt width, 2pt spacing
private let barCount = 5
private let barWidth: CGFloat = 2
private let barSpacing: CGFloat = 2
private let heightProfile: [CGFloat] = [0.4, 0.7, 1.0, 0.7, 0.4]
// Animation: 1/36s interval
// Colors:
private let waveformLeadingColor = Color(hex: "#F3FBFF")
private let waveformTrailingColor = Color(hex: "#8FD2FF")
private let waveformGlowColor = Color(hex: "#AEE3FF")
// Glow: 6pt radius @60% opacity
```

- [ ] **Step 4: Update spinner view**

```swift
// Size: 14x14, lineWidth: 2.5, trim 0.15 to 0.85
// Rotation: 0.8s loop
// Glow: 6pt radius @60% opacity
Circle()
    .trim(from: 0.15, to: 0.85)
    .stroke(cursorColor, lineWidth: 2.5)
    .frame(width: 14, height: 14)
    .rotationEffect(.degrees(spinnerRotation))
    .shadow(color: cursorColor.opacity(0.6), radius: 6)
```

- [ ] **Step 5: Update cursor following**

```swift
// 60fps timer (0.016s interval)
// Spring: response 0.2s, dampingFraction 0.6
// Offset from mouse: x+35, y+25
```

- [ ] **Step 6: Update bezier flight arc**

```swift
// Duration: distance/800, clamped 0.6-1.4s
// Arc height: distance * 0.2, max 80pt
// Scale pulse: sin curve 1.0-1.3x at apex
// Easing: smoothstep (3t²-2t³)
// Rotation: tangent to curve
func smoothstep(_ t: CGFloat) -> CGFloat {
    return t * t * (3 - 2 * t)
}
```

- [ ] **Step 7: Update speech bubbles**

```swift
// Font: 11pt medium, white text
// Padding: H:8, V:4
// Corner radius: 6pt
// Background: cursor color
// Glow: 6pt radius @50%
// Position: 8px right, 12px below cursor

// Welcome text: "hey! i'm luma" (30ms/char, 2s hold, 0.5s fade)
// Pointer phrases: ["right here!", "this one!", "over here!", "click this!", "here it is!", "found it!"]

// Navigation bubble pop-in: scale 0.5→1.0, spring(response: 0.4, dampingFraction: 0.6)
// Character streaming: 30-60ms per char
// Hold: 3s, then 0.5s fade

// Return flight cancellation: >100px mouse movement during return only
```

- [ ] **Step 8: Build and verify**

Cursor follows mouse with spring. Triangle renders at correct size/rotation. Waveform shows during listening. Spinner during processing. Flight arcs work.

- [ ] **Step 9: Commit**

```bash
git add leanring-buddy/OverlayWindow.swift
git commit -m "feat: rebuild OverlayWindow with OpenClicky cursor/waveform/flight specs"
```

---

## Task 7: Rebuild CompanionResponseOverlay

**Files:**
- Modify: `leanring-buddy/CompanionResponseOverlay.swift`

- [ ] **Step 1: Update response bubble styling**

```swift
// Background: rgba(10, 10, 15, 0.85) with backdrop blur
// Animated gradient border: 8s hue cycle
// Max width: 380pt, min width: 200pt
// Corner radius: DS.CornerRadius.large (10pt)
// Markdown: AttributedString
// Spring animation on height change
// Scroll for overflow
// Step indicators (dots) for walkthrough

VStack(alignment: .leading, spacing: DS.Spacing.sm) {
    if let text = responseText {
        ScrollView {
            Text(try! AttributedString(markdown: text))
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(DS.Colors.textPrimary)
                .textSelection(.enabled)
        }
        .frame(minWidth: 200, maxWidth: 380)
    }
    if totalSteps > 0 {
        HStack(spacing: 4) {
            ForEach(0..<totalSteps, id: \.self) { step in
                Circle()
                    .fill(step == currentStep ?
                        LumaAccentTheme.current.accent :
                        DS.Colors.textTertiary.opacity(0.4))
                    .frame(width: 6, height: 6)
            }
        }
    }
}
.padding(DS.Spacing.md)
.background(
    RoundedRectangle(cornerRadius: DS.CornerRadius.large, style: .continuous)
        .fill(Color(red: 10/255, green: 10/255, blue: 15/255).opacity(0.85))
        .background(.ultraThinMaterial)
)
.overlay(
    RoundedRectangle(cornerRadius: DS.CornerRadius.large, style: .continuous)
        .stroke(
            AngularGradient(
                gradient: Gradient(colors: [.blue, .purple, .pink, .orange, .yellow, .green, .blue]),
                center: .center,
                angle: .degrees(gradientRotation)
            ),
            lineWidth: 1.5
        )
)
.animation(.spring(response: 0.4, dampingFraction: 0.75), value: responseText)
```

Gradient rotation: `@State private var gradientRotation: Double = 0`, animated with:
```swift
.onAppear {
    withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
        gradientRotation = 360
    }
}
```

- [ ] **Step 2: Build and verify**

Response bubble shows with dark background, gradient border cycles, markdown renders, step dots show.

- [ ] **Step 3: Commit**

```bash
git add leanring-buddy/CompanionResponseOverlay.swift
git commit -m "feat: rebuild response overlay with gradient border and markdown rendering"
```

---

## Task 8: Create AgentSession Model

**Files:**
- Create: `leanring-buddy/Agent/AgentSession.swift`
- Reference: `/Users/nox/Desktop/openclicky/leanring-buddy/CodexAgentSession.swift`

- [ ] **Step 1: Create AgentSession model**

Port from CodexAgentSession, adapting names:

```swift
import AppKit
import Combine
import Foundation

// MARK: - Transcript Entry

struct LumaTranscriptEntry: Identifiable {
    let id: String
    let role: TranscriptRole
    let text: String
    let createdAt: Date

    init(role: TranscriptRole, text: String) {
        self.id = UUID().uuidString
        self.role = role
        self.text = text
        self.createdAt = Date()
    }
}

enum TranscriptRole: String {
    case user, assistant, system, command, plan

    var displayLabel: String {
        switch self {
        case .user: return "YOU"
        case .assistant: return "LUMA"
        case .system: return "SYSTEM"
        case .command: return "COMMAND"
        case .plan: return "PLAN"
        }
    }

    func displayColor(theme: LumaAccentTheme) -> Color {
        switch self {
        case .user: return theme.accentText
        case .assistant: return DS.Colors.textSecondary
        case .system: return DS.Colors.destructiveText
        case .command: return Color.yellow.opacity(0.9)
        case .plan: return Color.purple.opacity(0.9)
        }
    }
}

// MARK: - Session Status

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

    var dotColor: Color {
        switch self {
        case .stopped: return DS.Colors.textTertiary
        case .starting: return DS.Colors.warning
        case .ready: return DS.Colors.success
        case .running: return LumaAccentTheme.current.accent
        case .failed: return DS.Colors.destructive
        }
    }
}

// MARK: - Agent Session

@MainActor
final class AgentSession: ObservableObject, Identifiable {
    let id: UUID
    @Published var title: String
    @Published var accentTheme: LumaAccentTheme
    @Published var status: AgentSessionStatus = .stopped
    @Published var entries: [LumaTranscriptEntry] = []
    @Published var latestResponseCard: ResponseCard?
    @Published var lastErrorMessage: String?

    var model: String {
        didSet { UserDefaults.standard.set(model, forKey: "luma.agent.\(id.uuidString).model") }
    }
    var workingDirectoryPath: String

    init(title: String = "New Agent", accentTheme: LumaAccentTheme = .blue) {
        self.id = UUID()
        self.title = title
        self.accentTheme = accentTheme
        self.model = UserDefaults.standard.string(forKey: "luma.agent.defaultModel") ?? "claude-sonnet-4-6"
        self.workingDirectoryPath = NSHomeDirectory()
    }

    func warmUp() {
        status = .starting
        // Initialization logic — set to .ready when done
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.status = .ready
        }
    }

    func submitPrompt(_ prompt: String) {
        entries.append(LumaTranscriptEntry(role: .user, text: prompt))
        status = .running
        // Execution handled by LumaAgentEngine
    }

    func appendAssistantText(_ text: String) {
        entries.append(LumaTranscriptEntry(role: .assistant, text: text))
    }

    func appendSystemEntry(_ text: String) {
        entries.append(LumaTranscriptEntry(role: .system, text: text))
    }

    func dismissLatestResponseCard() {
        latestResponseCard = nil
    }

    func stop() {
        status = .stopped
        entries.removeAll()
        latestResponseCard = nil
        lastErrorMessage = nil
    }

    var latestActivitySummary: String? {
        entries.last(where: { $0.role != .user })?.text
    }

    var hasVisibleActivity: Bool {
        !entries.isEmpty || latestResponseCard != nil
    }
}
```

- [ ] **Step 2: Build and verify**

Model compiles. Can create sessions, append entries, change status.

- [ ] **Step 3: Commit**

```bash
git add leanring-buddy/Agent/AgentSession.swift
git commit -m "feat: create AgentSession model (session-based agent architecture)"
```

---

## Task 9: Create ResponseCard System

**Files:**
- Create: `leanring-buddy/Agent/ResponseCard.swift`
- Create: `leanring-buddy/Agent/ResponseCardView.swift`
- Reference: `/Users/nox/Desktop/openclicky/leanring-buddy/ClickyNextStageParityModels.swift`
- Reference: `/Users/nox/Desktop/openclicky/leanring-buddy/ClickyNextStageParityViews.swift`

- [ ] **Step 1: Create ResponseCard model**

```swift
import Foundation

enum ResponseCardSource: String {
    case voice, agent, handoff
}

struct ResponseCard: Identifiable {
    let id: UUID
    let source: ResponseCardSource
    let rawText: String
    var contextTitle: String?
    let createdAt: Date

    private static let maximumDisplayCharacters = 220

    init(source: ResponseCardSource, rawText: String, contextTitle: String? = nil) {
        self.id = UUID()
        self.source = source
        self.rawText = rawText
        self.contextTitle = contextTitle
        self.createdAt = Date()
    }

    var displayText: String {
        let sanitized = sanitizedDisplayText()
        if sanitized.count <= Self.maximumDisplayCharacters { return sanitized }
        let truncated = String(sanitized.prefix(Self.maximumDisplayCharacters))
        if let lastSpace = truncated.lastIndex(of: " ") {
            return String(truncated[..<lastSpace]) + "…"
        }
        return truncated + "…"
    }

    var displayTitle: String? {
        guard let title = contextTitle else { return nil }
        let upper = title.uppercased()
        return upper.count > 28 ? String(upper.prefix(28)) + "…" : upper
    }

    var completionLabel: String {
        switch source {
        case .voice: return "VOICE"
        case .agent: return "AGENT"
        case .handoff: return "HANDOFF"
        }
    }

    var suggestedNextActions: [String] {
        guard let range = rawText.range(of: "<NEXT_ACTIONS>"),
              let endRange = rawText.range(of: "</NEXT_ACTIONS>") else { return [] }
        let block = String(rawText[range.upperBound..<endRange.lowerBound])
        let actions = block.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("- ") }
            .map { String($0.dropFirst(2)) }
        return Array(actions.prefix(2))
    }

    private func sanitizedDisplayText() -> String {
        var text = rawText
        // Remove NEXT_ACTIONS blocks
        if let range = text.range(of: "<NEXT_ACTIONS>"),
           let endRange = text.range(of: "</NEXT_ACTIONS>") {
            text.removeSubrange(range.lowerBound...endRange.upperBound)
        }
        // Remove code blocks
        text = text.replacingOccurrences(of: "```[\\s\\S]*?```", with: "", options: .regularExpression)
        // Clean whitespace
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text
    }
}
```

- [ ] **Step 2: Create ResponseCardCompactView**

```swift
import SwiftUI

struct ResponseCardCompactView: View {
    let card: ResponseCard
    var onDismiss: (() -> Void)?
    var onRunSuggestedAction: ((String) -> Void)?
    var onTextFollowUp: (() -> Void)?
    var onVoiceFollowUp: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            // Header: title + completion label + dismiss
            HStack {
                if let title = card.displayTitle {
                    Text(title)
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .foregroundColor(DS.Colors.textSecondary)
                }
                Spacer()
                Text(card.completionLabel)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(LumaAccentTheme.current.accentText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(LumaAccentTheme.current.accent.opacity(0.2)))
                if let onDismiss {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .dsIconButtonStyle(size: 20)
                }
            }

            // Response text
            Text(card.displayText)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(DS.Colors.textPrimary)
                .lineSpacing(4)
                .lineLimit(4)
                .minimumScaleFactor(0.82)

            // Suggested next actions
            if !card.suggestedNextActions.isEmpty {
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text("Suggested next:")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(DS.Colors.textTertiary)
                    FlowLayout(spacing: 8, rowSpacing: 8) {
                        ForEach(card.suggestedNextActions, id: \.self) { action in
                            Button(action: { onRunSuggestedAction?(action) }) {
                                Text(action)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(DS.Colors.textPrimary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(Capsule().fill(Color.white.opacity(0.08)))
                            }
                            .buttonStyle(.plain)
                            .pointerCursor()
                        }
                    }
                }
            }

            // Follow up buttons
            if onTextFollowUp != nil || onVoiceFollowUp != nil {
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text("Follow up:")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(DS.Colors.textTertiary)
                    HStack(spacing: DS.Spacing.sm) {
                        if let onTextFollowUp {
                            Button(action: onTextFollowUp) {
                                Label("AI Text", systemImage: "character.cursor.ibeam")
                                    .font(.system(size: 10, weight: .semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(Capsule().fill(Color.white.opacity(0.08)))
                            }
                            .buttonStyle(.plain).pointerCursor()
                        }
                        if let onVoiceFollowUp {
                            Button(action: onVoiceFollowUp) {
                                Label("Voice", systemImage: "mic")
                                    .font(.system(size: 10, weight: .semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(Capsule().fill(Color.white.opacity(0.08)))
                            }
                            .buttonStyle(.plain).pointerCursor()
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 22)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(red: 0.10, green: 0.13, blue: 0.20),
                             Color(red: 0.09, green: 0.11, blue: 0.17)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .shadow(color: LumaAccentTheme.current.cursorColor.opacity(0.32), radius: 24, y: 12)
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .stroke(Color.white.opacity(0.10), lineWidth: 1))
    }
}
```

- [ ] **Step 3: Create FlowLayout**

```swift
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var rowSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += rowHeight + rowSpacing
                rowHeight = 0
            }
            currentX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: currentY + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX: CGFloat = bounds.minX
        var currentY: CGFloat = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX && currentX > bounds.minX {
                currentX = bounds.minX
                currentY += rowHeight + rowSpacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: currentX, y: currentY), proposal: .unspecified)
            currentX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
```

- [ ] **Step 4: Build and verify**

ResponseCard model creates, truncates, extracts actions. Compact view renders with gradient background.

- [ ] **Step 5: Commit**

```bash
git add leanring-buddy/Agent/ResponseCard.swift leanring-buddy/Agent/ResponseCardView.swift
git commit -m "feat: create ResponseCard model and compact view with suggested actions"
```

---

## Task 10: Create AgentModePanelSection

**Files:**
- Create: `leanring-buddy/Agent/AgentModePanelSection.swift`
- Reference: `/Users/nox/Desktop/openclicky/leanring-buddy/CodexAgentModePanelSection.swift`

- [ ] **Step 1: Create AgentModePanelSection view**

```swift
import SwiftUI

struct AgentModePanelSection: View {
    @ObservedObject var session: AgentSession
    var onOpenDashboard: () -> Void
    var onSubmitPrompt: (String) -> Void

    @State private var promptText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            // Header: status dot + label + settings
            HStack(spacing: DS.Spacing.sm) {
                Circle()
                    .fill(session.status.dotColor)
                    .frame(width: 7, height: 7)
                    .shadow(color: session.status.dotColor.opacity(0.6), radius: 3)

                Text(session.status.displayLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DS.Colors.textPrimary)

                Spacer()

                Text(session.model)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(DS.Colors.textTertiary)
            }

            // Summary
            Text("Ask for coding, research, writing, or app tasks.")
                .font(.system(size: 11))
                .foregroundColor(DS.Colors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            // Prompt input
            TextField("Ask Luma to do something...", text: $promptText, axis: .vertical)
                .font(.system(size: 12))
                .lineLimit(1...3)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.07))
                .overlay(RoundedRectangle(cornerRadius: DS.CornerRadius.medium)
                    .stroke(DS.Colors.borderSubtle, lineWidth: 0.5))
                .cornerRadius(DS.CornerRadius.medium)
                .onSubmit { submitPrompt() }

            // Error message
            if let error = session.lastErrorMessage {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundColor(DS.Colors.destructiveText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Inline response
            if session.status == .running || session.hasVisibleActivity,
               let summary = session.latestActivitySummary {
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text(session.status.displayLabel)
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundColor(DS.Colors.textTertiary)
                        .kerning(0.45)
                        .textCase(.uppercase)
                    Text(summary)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(DS.Colors.textPrimary)
                        .lineLimit(5)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.055))
                .overlay(RoundedRectangle(cornerRadius: DS.CornerRadius.medium)
                    .stroke(DS.Colors.borderSubtle.opacity(0.75), lineWidth: 0.5))
                .cornerRadius(DS.CornerRadius.medium)
            }

            // Button row
            HStack(spacing: DS.Spacing.sm) {
                // Dashboard button
                Button(action: onOpenDashboard) {
                    Label("Dashboard", systemImage: "rectangle.grid.2x2")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(DS.Colors.textSecondary)
                }
                .buttonStyle(.plain)
                .pointerCursor()

                Spacer()

                // Send button
                Button(action: submitPrompt) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.white)
                        .frame(width: 42, height: 30)
                        .background(promptText.isEmpty ?
                            LumaAccentTheme.current.accent.opacity(0.35) :
                            LumaAccentTheme.current.accent)
                        .cornerRadius(DS.CornerRadius.medium)
                }
                .buttonStyle(.plain)
                .disabled(promptText.isEmpty)
                .pointerCursor(isEnabled: !promptText.isEmpty)
            }
        }
        .padding(9)
        .background(Color.white.opacity(0.045))
        .overlay(RoundedRectangle(cornerRadius: DS.CornerRadius.large)
            .stroke(DS.Colors.borderSubtle, lineWidth: 0.5))
        .cornerRadius(DS.CornerRadius.large)
    }

    private func submitPrompt() {
        let text = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        onSubmitPrompt(text)
        promptText = ""
    }
}
```

- [ ] **Step 2: Wire into CompanionPanelView**

Replace the placeholder from Task 4 Step 3 with the actual `AgentModePanelSection`:

```swift
if companionManager.isAgentModeEnabled,
   let activeSession = companionManager.activeAgentSession {
    AgentModePanelSection(
        session: activeSession,
        onOpenDashboard: { companionManager.showAgentHUD() },
        onSubmitPrompt: { prompt in companionManager.submitAgentPrompt(prompt) }
    )
    .padding(.top, 12)
    .padding(.horizontal, 14)
}
```

- [ ] **Step 3: Build and verify**

Agent panel section renders in companion panel when agent mode is on. Status dot reflects session state. Input submits text.

- [ ] **Step 4: Commit**

```bash
git add leanring-buddy/Agent/AgentModePanelSection.swift leanring-buddy/CompanionPanelView.swift
git commit -m "feat: create AgentModePanelSection with status, prompt input, and dashboard button"
```

---

## Task 11: Create Agent HUD Window

**Files:**
- Create: `leanring-buddy/Agent/LumaAgentHUDWindowManager.swift`
- Reference: `/Users/nox/Desktop/openclicky/leanring-buddy/CodexHUDWindowManager.swift`

- [ ] **Step 1: Create window manager**

```swift
import AppKit
import SwiftUI

@MainActor
final class LumaAgentHUDWindowManager {
    static let shared = LumaAgentHUDWindowManager()
    private var panel: NSPanel?

    private let hudWidth: CGFloat = 594
    private let hudHeight: CGFloat = 452

    func show(companionManager: CompanionManager) {
        if let existingPanel = panel {
            existingPanel.makeKeyAndOrderFront(nil)
            return
        }
        let contentView = LumaAgentHUDView(companionManager: companionManager)
        let hostingView = NSHostingView(rootView: contentView)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: hudWidth, height: hudHeight),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.minSize = NSSize(width: hudWidth, height: hudHeight)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.contentView = hostingView
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
    }

    func hide() { panel?.orderOut(nil) }
    func destroy() { panel?.close(); panel = nil }
}
```

- [ ] **Step 2: Create HUD content view**

```swift
struct LumaAgentHUDView: View {
    @ObservedObject var companionManager: CompanionManager

    var body: some View {
        VStack(spacing: 0) {
            hudHeader
            agentTeamStrip
            if let card = companionManager.activeAgentSession?.latestResponseCard {
                ResponseCardCompactView(
                    card: card,
                    onDismiss: { companionManager.activeAgentSession?.dismissLatestResponseCard() }
                )
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            Divider().background(DS.Colors.borderSubtle.opacity(0.7))
            transcriptArea
            Divider().background(DS.Colors.borderSubtle.opacity(0.7))
            composerSection
        }
        .frame(minWidth: 594, minHeight: 452)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(red: 0.067, green: 0.075, blue: 0.071).opacity(0.98))
        )
        .shadow(color: .black.opacity(0.34), radius: 22, y: 14)
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(Color.white.opacity(0.10), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
```

- [ ] **Step 3: Implement header**

```swift
@ViewBuilder
private var hudHeader: some View {
    HStack(spacing: DS.Spacing.sm) {
        // Icon
        Image(systemName: "cursorarrow.motionlines.click")
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(LumaAccentTheme.current.accentText)
            .frame(width: 24, height: 24)
            .background(Circle().fill(LumaAccentTheme.current.accent.opacity(0.12)))

        Text("Luma")
            .font(.system(size: 13, weight: .heavy))
            .foregroundColor(DS.Colors.textPrimary)

        Spacer()

        // Memory button
        Button(action: { /* open memory viewer */ }) {
            Image(systemName: "books.vertical")
                .font(.system(size: 12))
        }
        .dsIconButtonStyle(size: 28, tooltip: "Memory")

        // Warm up button
        Button(action: { companionManager.activeAgentSession?.warmUp() }) {
            Image(systemName: "bolt")
                .font(.system(size: 12))
        }
        .dsIconButtonStyle(size: 28, tooltip: "Warm up")

        // Close button
        Button(action: { LumaAgentHUDWindowManager.shared.hide() }) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .semibold))
        }
        .dsIconButtonStyle(size: 28, tooltip: "Close")
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 7)
}
```

- [ ] **Step 4: Implement agent team strip**

```swift
@ViewBuilder
private var agentTeamStrip: some View {
    ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: DS.Spacing.sm) {
            ForEach(companionManager.agentSessions) { session in
                agentTeamButton(session: session)
            }
            // Add button
            Button(action: { companionManager.spawnAgentSession() }) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundColor(DS.Colors.textSecondary)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(DS.Colors.surface2))
                    .overlay(Circle().stroke(DS.Colors.borderSubtle, lineWidth: 0.8))
            }
            .buttonStyle(.plain).pointerCursor()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

@ViewBuilder
private func agentTeamButton(session: AgentSession) -> some View {
    let isSelected = companionManager.activeAgentSessionID == session.id
    Button(action: { companionManager.activeAgentSessionID = session.id }) {
        ZStack {
            Circle()
                .fill(DS.Colors.surface2)
                .frame(width: 30, height: 30)
            Image(systemName: "cursorarrow")
                .font(.system(size: 13, weight: .heavy))
                .foregroundColor(session.accentTheme.cursorColor)
                .rotationEffect(.degrees(-18))
            // Status dot
            Circle()
                .fill(session.status.dotColor)
                .frame(width: 7, height: 7)
                .overlay(Circle().stroke(.black, lineWidth: 1.5))
                .offset(x: 10, y: -10)
        }
        .overlay(Circle().stroke(
            isSelected ? session.accentTheme.accent.opacity(0.82) : DS.Colors.borderSubtle.opacity(0.55),
            lineWidth: isSelected ? 1.4 : 0.8))
        .shadow(color: isSelected ? session.accentTheme.accent.opacity(0.34) : .clear,
                radius: isSelected ? 7 : 3)
    }
    .buttonStyle(.plain).pointerCursor()
    .scaleEffect(isSelected ? 1.0 : 0.95)
}
```

- [ ] **Step 5: Implement transcript area**

```swift
@ViewBuilder
private var transcriptArea: some View {
    ScrollViewReader { proxy in
        ScrollView {
            if let session = companionManager.activeAgentSession {
                if session.entries.isEmpty {
                    // Empty state
                    Text("Ask Luma a question or give it a task to get started.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(DS.Colors.textTertiary)
                        .padding(16)
                        .frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: 9)
                            .stroke(DS.Colors.borderSubtle, lineWidth: 0.5))
                        .padding(10)
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(session.entries) { entry in
                            transcriptRow(entry: entry, theme: session.accentTheme)
                                .id(entry.id)
                        }
                    }
                    .padding(10)
                }
            }
        }
        .onChange(of: companionManager.activeAgentSession?.entries.count) { _ in
            if let lastEntry = companionManager.activeAgentSession?.entries.last {
                withAnimation { proxy.scrollTo(lastEntry.id, anchor: .bottom) }
            }
        }
    }
}

@ViewBuilder
private func transcriptRow(entry: LumaTranscriptEntry, theme: LumaAccentTheme) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        Text(entry.role.displayLabel)
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(entry.role.displayColor(theme: theme))
            .textCase(.uppercase)
        Text(entry.text)
            .font(.system(size: 11))
            .foregroundColor(DS.Colors.textPrimary)
            .textSelection(.enabled)
    }
    .padding(9)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: 9)
        .fill(entry.role == .user ?
            theme.accent.opacity(0.08) :
            Color.white.opacity(0.05)))
}
```

- [ ] **Step 6: Implement composer**

```swift
@ViewBuilder
private var composerSection: some View {
    HStack(spacing: DS.Spacing.sm) {
        @State var composerText: String = ""
        TextField("Ask Agent HUD...", text: $composerText, axis: .vertical)
            .font(.system(size: 11, weight: .medium))
            .lineLimit(1...4)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(Color.white.opacity(0.07))
            .overlay(RoundedRectangle(cornerRadius: DS.CornerRadius.medium)
                .stroke(DS.Colors.borderSubtle, lineWidth: 0.5))
            .cornerRadius(DS.CornerRadius.medium)
            .onSubmit {
                companionManager.submitAgentPrompt(composerText)
                composerText = ""
            }

        Button(action: {
            companionManager.submitAgentPrompt(composerText)
            composerText = ""
        }) {
            HStack(spacing: 4) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 10, weight: .bold))
                Text("Run")
                    .font(.system(size: 10, weight: .heavy))
            }
            .foregroundColor(composerText.isEmpty ? DS.Colors.textTertiary : .white)
            .frame(width: 76, height: 32)
            .background(RoundedRectangle(cornerRadius: DS.CornerRadius.large)
                .fill(composerText.isEmpty ?
                    Color.white.opacity(0.06) :
                    LumaAccentTheme.current.accent))
            .overlay(RoundedRectangle(cornerRadius: DS.CornerRadius.large)
                .stroke(Color.white.opacity(composerText.isEmpty ? 0.10 : 0.22), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(composerText.isEmpty)
        .pointerCursor(isEnabled: !composerText.isEmpty)
    }
    .padding(10)
}
```

Note: The composer `@State` must be lifted to the parent view since `@ViewBuilder` properties don't support `@State` inline. Move `composerText` to be a `@State` property on `LumaAgentHUDView`.

- [ ] **Step 7: Build and verify**

HUD opens from dashboard button. Shows team strip, transcript, composer. Can switch between agent sessions.

- [ ] **Step 8: Commit**

```bash
git add leanring-buddy/Agent/LumaAgentHUDWindowManager.swift
git commit -m "feat: create Agent HUD window with team strip, transcript, and composer"
```

---

## Task 12: Create Agent Dock Window

**Files:**
- Create: `leanring-buddy/Agent/LumaAgentDockWindowManager.swift`

- [ ] **Step 1: Create dock item model**

```swift
import SwiftUI

struct AgentDockItem: Identifiable {
    let id: UUID
    var title: String
    var accentTheme: LumaAccentTheme
    var status: AgentSessionStatus
    var caption: String?
}
```

- [ ] **Step 2: Create dock window manager**

```swift
@MainActor
final class LumaAgentDockWindowManager {
    static let shared = LumaAgentDockWindowManager()
    private var panel: NSPanel?

    func show(companionManager: CompanionManager) {
        if let existing = panel { existing.makeKeyAndOrderFront(nil); return }
        let contentView = LumaAgentDockView(companionManager: companionManager)
        let hostingView = NSHostingView(rootView: contentView)
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 190),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.contentView = hostingView
        // Position bottom-right
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: screenFrame.maxX - 520 - 20,
                y: screenFrame.minY + 20
            ))
        }
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
    }

    func hide() { panel?.orderOut(nil) }
    func destroy() { panel?.close(); panel = nil }
}
```

- [ ] **Step 3: Create dock view**

```swift
struct LumaAgentDockView: View {
    @ObservedObject var companionManager: CompanionManager

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(companionManager.agentDockItems) { item in
                    dockItemView(item: item)
                }
            }
            .padding(10)
        }
        .frame(height: 90)
    }

    @ViewBuilder
    private func dockItemView(item: AgentDockItem) -> some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(DS.Colors.surface2)
                    .frame(width: 54, height: 54)
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(item.accentTheme.accent.opacity(0.5), lineWidth: 1.1))
                    .shadow(color: item.accentTheme.accent.opacity(0.3), radius: 24)
                    .shadow(color: item.accentTheme.accent.opacity(0.62), radius: 15)
                    .shadow(color: .black.opacity(0.5), radius: 10)

                Image(systemName: "cursorarrow")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(item.accentTheme.cursorColor)
                    .rotationEffect(.degrees(-18))

                // Status dot
                Circle()
                    .fill(item.status.dotColor)
                    .frame(width: 9, height: 9)
                    .overlay(Circle().stroke(.black, lineWidth: 1))
                    .offset(x: 0, y: 0)
            }
            .frame(width: 66, height: 66)

            Text(item.title)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(DS.Colors.textSecondary)
                .lineLimit(1)
        }
        .pointerCursor()
    }
}
```

- [ ] **Step 4: Build and verify**

Dock appears showing active agent sessions. Items show accent color and status.

- [ ] **Step 5: Commit**

```bash
git add leanring-buddy/Agent/LumaAgentDockWindowManager.swift
git commit -m "feat: create agent dock window with floating session indicators"
```

---

## Task 13: Integrate Agent Sessions into CompanionManager

**Files:**
- Modify: `leanring-buddy/CompanionManager.swift`

- [ ] **Step 1: Add agent session properties**

Add these published properties to CompanionManager:

```swift
// Agent session management
@Published var agentSessions: [AgentSession] = []
@Published var activeAgentSessionID: UUID?
@Published var isAgentModeEnabled: Bool = UserDefaults.standard.bool(forKey: "luma.agentMode.enabled") {
    didSet { UserDefaults.standard.set(isAgentModeEnabled, forKey: "luma.agentMode.enabled") }
}

var activeAgentSession: AgentSession? {
    agentSessions.first(where: { $0.id == activeAgentSessionID })
}

var agentDockItems: [AgentDockItem] {
    agentSessions.map { session in
        AgentDockItem(
            id: session.id,
            title: session.title,
            accentTheme: session.accentTheme,
            status: session.status,
            caption: session.latestActivitySummary
        )
    }
}
```

- [ ] **Step 2: Add agent session lifecycle methods**

```swift
private let accentThemeCycle: [LumaAccentTheme] = [.blue, .mint, .amber, .rose]

func spawnAgentSession() {
    let maxAgents = UserDefaults.standard.integer(forKey: "luma.agents.maxCount")
    let limit = maxAgents > 0 ? maxAgents : 3

    if agentSessions.count >= limit {
        // Remove oldest non-running session
        if let oldestIdle = agentSessions
            .filter({ $0.status != .running })
            .first {
            agentSessions.removeAll(where: { $0.id == oldestIdle.id })
        }
    }

    let themeIndex = agentSessions.count % accentThemeCycle.count
    let session = AgentSession(
        title: "New Agent",
        accentTheme: accentThemeCycle[themeIndex]
    )
    session.warmUp()
    agentSessions.append(session)
    activeAgentSessionID = session.id
}

func dismissAgentSession(_ sessionID: UUID) {
    agentSessions.first(where: { $0.id == sessionID })?.stop()
    agentSessions.removeAll(where: { $0.id == sessionID })
    if activeAgentSessionID == sessionID {
        activeAgentSessionID = agentSessions.first?.id
    }
}

func submitAgentPrompt(_ prompt: String) {
    guard let session = activeAgentSession else { return }
    session.submitPrompt(prompt)
    // Trigger engine execution (Task 14)
    Task {
        await LumaAgentEngine.shared.executeTask(prompt: prompt, session: session)
    }
}

func showAgentHUD() {
    LumaAgentHUDWindowManager.shared.show(companionManager: self)
}
```

- [ ] **Step 3: Build and verify**

Can spawn sessions, switch between them, submit prompts. Active session tracks correctly.

- [ ] **Step 4: Commit**

```bash
git add leanring-buddy/CompanionManager.swift
git commit -m "feat: integrate agent session lifecycle into CompanionManager"
```

---

## Task 14: Rebuild LumaAgentEngine for Sessions

**Files:**
- Modify: `leanring-buddy/Agent/LumaAgentEngine.swift`

- [ ] **Step 1: Update engine for session model**

Update `LumaAgentEngine` to work with `AgentSession` instead of `LumaAgent`:

```swift
@MainActor
final class LumaAgentEngine {
    static let shared = LumaAgentEngine()

    private let cursorLock = NSLock()
    private var cursorOwnerSessionID: UUID?

    enum AgentAction {
        case click(coordinate: CGPoint)
        case type(text: String)
        case keyPress(key: String, modifiers: [String])
        case screenshot
        case wait(seconds: Double)
        case openApp(bundleId: String)
        case search(query: String)
    }

    func executeTask(prompt: String, session: AgentSession) async {
        await MainActor.run {
            session.status = .running
        }

        // Build action plan via Claude API
        // Execute actions sequentially
        // Update session transcript per action
        // Create response card on completion
        // Save to LumaMemoryManager

        do {
            // 1. Plan actions
            let actions = try await planActions(prompt: prompt, session: session)

            // 2. Execute each action
            for action in actions {
                await MainActor.run {
                    session.appendSystemEntry("Executing: \(describeAction(action))")
                }
                try await executeAction(action, sessionID: session.id)
            }

            // 3. Complete
            await MainActor.run {
                let responseText = "Task completed: \(prompt)"
                session.appendAssistantText(responseText)
                session.latestResponseCard = ResponseCard(
                    source: .agent,
                    rawText: responseText,
                    contextTitle: session.title
                )
                session.status = .ready

                // Persist to memory
                LumaMemoryManager.shared.appendToHistory(
                    agentId: session.id.uuidString,
                    entry: ConversationEntry(
                        timestamp: Date(),
                        agentId: session.id.uuidString,
                        agentTitle: session.title,
                        role: "luma",
                        content: responseText,
                        taskStatus: "complete"
                    )
                )
            }
        } catch {
            await MainActor.run {
                session.lastErrorMessage = error.localizedDescription
                session.status = .failed(error.localizedDescription)
            }
        }
    }

    private func acquireCursor(sessionID: UUID) -> Bool {
        cursorLock.lock()
        defer { cursorLock.unlock() }
        if cursorOwnerSessionID == nil || cursorOwnerSessionID == sessionID {
            cursorOwnerSessionID = sessionID
            return true
        }
        return false
    }

    private func releaseCursor(sessionID: UUID) {
        cursorLock.lock()
        defer { cursorLock.unlock() }
        if cursorOwnerSessionID == sessionID {
            cursorOwnerSessionID = nil
        }
    }

    private func describeAction(_ action: AgentAction) -> String {
        switch action {
        case .click(let coord): return "Click at (\(Int(coord.x)), \(Int(coord.y)))"
        case .type(let text): return "Type: \(text.prefix(30))"
        case .keyPress(let key, _): return "Key: \(key)"
        case .screenshot: return "Capture screenshot"
        case .wait(let secs): return "Wait \(secs)s"
        case .openApp(let bundle): return "Open: \(bundle)"
        case .search(let query): return "Search: \(query)"
        }
    }

    // Keep existing planActions and executeAction implementations,
    // updating references from LumaAgent to AgentSession
}
```

- [ ] **Step 2: Build and verify**

Engine compiles with session model. Cursor lock works. Action descriptions render in transcript.

- [ ] **Step 3: Commit**

```bash
git add leanring-buddy/Agent/LumaAgentEngine.swift
git commit -m "feat: rebuild LumaAgentEngine for session-based agent architecture"
```

---

## Task 15: Update Hotkey and Voice Integration

**Files:**
- Modify: `leanring-buddy/Agent/AgentHotkeyHandler.swift`
- Modify: `leanring-buddy/Agent/AgentVoiceIntegration.swift`

- [ ] **Step 1: Update AgentHotkeyHandler**

Replace `AgentManager` references with `CompanionManager` session methods:

```swift
// Ctrl+Cmd+N: Spawn new agent session
// Old: AgentManager.shared.spawnAgent()
// New: companionManager.spawnAgentSession()

// Ctrl+Option+Tab: Cycle active agent
// Old: AgentManager.shared.cycleAgent()
// New: cycle through companionManager.agentSessions

// Ctrl+Option+1-9: Switch to session at index
// Old: AgentManager.shared.focusAgent(at: index)
// New: set companionManager.activeAgentSessionID = agentSessions[index].id
```

Update the monitor setup to use `companionManager` reference instead of `AgentManager.shared`.

- [ ] **Step 2: Update AgentVoiceIntegration**

Replace agent spawning logic:

```swift
// Old: AgentManager.shared.spawnAgent()
// New: companionManager.spawnAgentSession()

// Keep regex patterns for spawn detection:
// "spawn agent", "create agent", "new agent", "open agent", "hey agent"

// Keep title generation heuristic
// Update to set session.title instead of agent.title
```

- [ ] **Step 3: Build and verify**

Ctrl+Cmd+N spawns a session. Tab cycles. Number keys switch. Voice "spawn agent" works.

- [ ] **Step 4: Commit**

```bash
git add leanring-buddy/Agent/AgentHotkeyHandler.swift leanring-buddy/Agent/AgentVoiceIntegration.swift
git commit -m "feat: update hotkey and voice integration for session-based agents"
```

---

## Task 16: Update Memory Integration

**Files:**
- Modify: `leanring-buddy/Agent/AgentMemoryIntegration.swift`
- Modify: `leanring-buddy/LumaMemoryManager.swift`

- [ ] **Step 1: Update AgentMemoryIntegration for sessions**

Replace `LumaAgent` references with `AgentSession`:

```swift
// Old: func recordUserMessage(agent: LumaAgent, message: String)
// New: func recordUserMessage(session: AgentSession, message: String)

// Old: func recordAgentResponse(agent: LumaAgent, response: String)
// New: func recordAgentResponse(session: AgentSession, response: String)

// Old: func summarizeMemoryForAgent(_ agent: LumaAgent) -> String
// New: func summarizeMemoryForSession(_ session: AgentSession) -> String

// Use session.id.uuidString as the agentId parameter for LumaMemoryManager
```

- [ ] **Step 2: Update LumaMemoryManager**

Ensure `appendToHistory` uses sessionId consistently:

```swift
// File naming: history/agent_{sessionId}_{timestamp}.json
// Keep 2MB rotation logic
// Keep searchHistory and loadMemory unchanged
```

- [ ] **Step 3: Build and verify**

Memory records per session. History files create and rotate. Memory loads for session context.

- [ ] **Step 4: Commit**

```bash
git add leanring-buddy/Agent/AgentMemoryIntegration.swift leanring-buddy/LumaMemoryManager.swift
git commit -m "feat: update memory integration for session-based agent model"
```

---

## Task 17: Remove Old Agent Bubble Code

**Files:**
- Remove: `leanring-buddy/Agent/AgentStackView.swift`
- Remove: `leanring-buddy/Agent/AgentShapeView.swift`
- Remove: `leanring-buddy/Agent/AgentBubblePhysics.swift`
- Remove: `leanring-buddy/Agent/AgentProfile.swift`
- Remove: `leanring-buddy/Agent/LumaAgent.swift` (old model)
- Remove: `leanring-buddy/Agent/AgentManager.swift` (old manager)
- Remove: `leanring-buddy/Agent/AgentSettingsManager.swift` (merged into settings)
- Remove: `leanring-buddy/CompanionBubbleWindow.swift`
- Modify: Any files that reference removed files

- [ ] **Step 1: Remove old agent UI files**

Delete these files from the filesystem and Xcode project:
- `Agent/AgentStackView.swift` — replaced by Agent Dock + HUD
- `Agent/AgentShapeView.swift` — no longer needed (no shape rendering)
- `Agent/AgentBubblePhysics.swift` — no physics simulation needed
- `Agent/AgentProfile.swift` — replaced by session accent themes

- [ ] **Step 2: Remove old agent model files**

Delete:
- `Agent/LumaAgent.swift` — replaced by `AgentSession.swift`
- `Agent/AgentManager.swift` — replaced by session management in CompanionManager

- [ ] **Step 3: Merge and remove AgentSettingsManager**

Move settings from `AgentSettingsManager` into the Settings window Agent Mode tab (already done in Task 5):
- `maxAgentCount` → UserDefaults `luma.agents.maxCount` (read directly)
- `isAgentModeEnabled` → already on CompanionManager
- Agent profiles → replaced by session model/accent theme

Delete `Agent/AgentSettingsManager.swift`.

- [ ] **Step 4: Remove CompanionBubbleWindow**

Delete `leanring-buddy/CompanionBubbleWindow.swift`. Its functionality (response bubble) is now in `CompanionResponseOverlay.swift`.

- [ ] **Step 5: Fix all broken references**

Search for references to deleted types and fix:
- `AgentManager.shared` → `companionManager.agentSessions` / session methods
- `LumaAgent` → `AgentSession`
- `AgentStackView` → remove from overlay setup
- `AgentSettingsManager.shared` → direct UserDefaults reads
- `CompanionBubbleWindow` → remove from window management

- [ ] **Step 6: Build and verify**

Clean compile with no references to removed types. App launches without bubble overlay.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "refactor: remove old agent bubble system (AgentStackView, physics, shapes, old model)"
```

---

## Task 18: Final Integration & Testing

**Files:**
- Modify: `leanring-buddy/CLAUDE.md` (update key files table)
- Modify: `LUMA_V3_PRD.md` (mark phases complete)

- [ ] **Step 1: Update CLAUDE.md**

Update the Key Files table:
- Remove entries for deleted files (AgentStackView, AgentShapeView, AgentBubblePhysics, AgentProfile, LumaAgent, AgentManager, AgentSettingsManager, CompanionBubbleWindow, LumaTheme, SettingsPanelView)
- Add entries for new files:
  - `DesignSystem.swift` — DS design tokens, 7 button styles, accent themes
  - `Agent/AgentSession.swift` — Agent session model with status, transcript, response cards
  - `Agent/AgentModePanelSection.swift` — Inline agent controls for companion panel
  - `Agent/LumaAgentHUDWindowManager.swift` — Agent HUD dashboard window
  - `Agent/LumaAgentDockWindowManager.swift` — Floating agent dock
  - `Agent/ResponseCard.swift` — Response card model
  - `Agent/ResponseCardView.swift` — Response card compact view
- Update line counts for modified files

- [ ] **Step 2: Verify all hotkeys**

Test each hotkey:
- `Ctrl+Option` — push-to-talk voice
- `Ctrl+Cmd+N` — spawn new agent session
- `Ctrl+Option+Tab` — cycle agents
- `Ctrl+Option+1-9` — switch to agent at index

- [ ] **Step 3: Verify guide mode isolation**

With Agent Mode OFF, verify:
- Voice pipeline works (record → transcribe → Claude → TTS)
- Cursor follows mouse, flights work
- Response overlay shows
- No agent UI elements visible

- [ ] **Step 4: Verify agent mode**

With Agent Mode ON:
- Agent panel section shows in companion panel
- Dashboard button opens HUD
- Agent dock shows active sessions
- Prompt submission creates transcript entries
- Response cards display

- [ ] **Step 5: Mark PRD phases complete**

Update `LUMA_V3_PRD.md` — change all `[ ]` to `[x]` for completed phases.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: complete Luma v3 OpenClicky rebuild — final integration and docs update"
```

---

## Execution Order Summary

| Task | Description | Dependencies |
|------|-------------|--------------|
| 1 | Create DesignSystem.swift | None |
| 2 | Migrate LumaTheme → DS | Task 1 |
| 3 | Rebuild MenuBarPanelManager | Task 2 |
| 4 | Rebuild CompanionPanelView | Task 2, 3 |
| 5 | Create Settings Window | Task 2 |
| 6 | Rebuild OverlayWindow | Task 2 |
| 7 | Rebuild CompanionResponseOverlay | Task 2 |
| 8 | Create AgentSession Model | Task 1 |
| 9 | Create ResponseCard System | Task 1 |
| 10 | Create AgentModePanelSection | Task 8, 9 |
| 11 | Create Agent HUD Window | Task 8, 9 |
| 12 | Create Agent Dock Window | Task 8 |
| 13 | Integrate Sessions into CompanionManager | Task 8, 11, 12 |
| 14 | Rebuild LumaAgentEngine | Task 8, 13 |
| 15 | Update Hotkey & Voice Integration | Task 13 |
| 16 | Update Memory Integration | Task 8, 13 |
| 17 | Remove Old Agent Bubble Code | Tasks 13-16 |
| 18 | Final Integration & Testing | All tasks |

**Parallelizable groups:**
- Tasks 3, 4, 5, 6, 7 can run in parallel (all depend on Task 2 only)
- Tasks 8, 9 can run in parallel (depend on Task 1 only)
- Tasks 10, 11, 12 can run in parallel (depend on Tasks 8, 9)
- Tasks 14, 15, 16 can run in parallel (depend on Task 13)
