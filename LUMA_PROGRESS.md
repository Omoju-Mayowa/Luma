## LUMA REBUILD PROGRESS
### Session state — 2026-04-08 (resume here after recharge)

#### Files Analyzed
- `leanring_buddyApp.swift` — App entry point, CompanionAppDelegate,
  Sparkle, login item
- `CompanionManager.swift` — Central state machine, worker base URL
  hardcoded, ClaudeAPI/TTS/overlay lifecycle
- `ClaudeAPI.swift` — OpenRouter-compatible streaming chat client, routes
  through Cloudflare worker
- `ElevenLabsTTSClient.swift` (actual file: NativeTTSClient) —
  AVSpeechSynthesizer, keep as-is
- `CompanionPanelView.swift` — Dark theme panel UI, "Clicky"/"Farza" strings
  throughout
- `DesignSystem.swift` — Dark color tokens (DS namespace), needs full
  replacement with LumaTheme
- `MenuBarPanelManager.swift` — NSStatusItem + NSPanel, "clickyDismissPanel"
  notification
- `AssemblyAIStreamingTranscriptionProvider.swift` — Fetches token from
  Cloudflare worker proxy
- `OpenRouterModelFetcher.swift` — Fetches models from Cloudflare worker proxy
- `ClickyAnalytics.swift` — PostHog analytics, hardcoded API key
- `AppBundleConfiguration.swift` — Info.plist reader
- `Info.plist` — "Clicky" usage strings,
  VoiceTranscriptionProvider=assemblyai
- `worker/src/index.ts` — Cloudflare Worker (3 routes: /chat, /models,
  /transcribe-token) — DELETE ENTIRE worker/ dir
- `leanring-buddy.entitlements` — entitlements file
- `OverlayWindow.swift` — Full-screen transparent overlay, blue cursor,
  bezier arcs

---

#### EXECUTION ORDER (easiest → hardest, optimizes credit usage)

Claude Code must work in this exact order. Complete and confirm each
section before moving to the next. If session ends, resume from the
next uncompleted section.

**TIER 1 — Pure string/config changes (fastest, no logic)**
- [ ] Section 1 — Rebrand (string replacements, Info.plist, CLAUDE.md)
- [ ] Section 2a — Delete worker/ directory
- [ ] Delete DesignSystem.swift, rename ClickyAnalytics → LumaAnalytics

**TIER 2 — New isolated files (no dependencies on other new files)**
- [ ] Section 3 — LumaTheme.swift + LumaStrings.swift
- [ ] Section 4 — KeychainManager.swift
- [ ] Section 6 — AccountManager.swift

**TIER 3 — Files that depend on Tier 2**
- [ ] Section 5 — PINManager.swift + PINEntryView.swift
  (depends on KeychainManager)
- [ ] Section 10a — ProfileManager.swift
  (depends on KeychainManager)
- [ ] Section 10b — APIClient.swift
  (depends on ProfileManager + KeychainManager)

**TIER 4 — Worker removal + direct API wiring**
- [ ] Section 2b — Remove workerBaseURL from CompanionManager,
  wire APIClient.sendMessage() everywhere
- [ ] Section 11 — AssemblyAI Keychain migration + direct token fetch
- [ ] Section 2c — OpenRouterModelFetcher: call OpenRouter directly
  with key from Keychain

**TIER 5 — UI rebuilds (most complex)**
- [ ] Section 9 — Companion Panel bottom bar rebuild
- [ ] Section 8 — SettingsPanelView.swift (tabbed settings)
- [ ] Section 7 — OnboardingWizardView.swift (5-step wizard)

**TIER 6 — Overlay + cursor (most complex Swift, last)**
- [ ] Section 12 — macOS TTS (verify no changes needed)
- [ ] Section 13 — CustomCursorManager + CompanionBubbleWindow
- [ ] Section 14 — WalkthroughEngine (NEW — see below)

---

#### Plan Summary (Sections 1–14)

**Section 1 — Rebrand**
- All "Clicky"/"clicky" → "Luma"/"luma" in every Swift file
- "Farza"/"farzaa" → "Omoju Oluwamayowa"/"Nox"
- Info.plist: CFBundleName→Luma, usage strings updated
- Notification name `.clickyDismissPanel` → `.lumaDismissPanel`
- `isClickyCursorEnabled` → `isLumaCursorEnabled` in UserDefaults
- Menu bar tooltip → "Luma", Quit button → "Quit Luma"
- Xcode project/target/scheme rename done MANUALLY in Xcode
- CLAUDE.md rewritten for Luma

**Section 2 — Remove Cloudflare Worker**
- Delete `worker/` directory entirely
- Remove `workerBaseURL` from CompanionManager
- ClaudeAPI init: takes direct API URL + key header instead of proxy URL
- AssemblyAIStreamingTranscriptionProvider: call AssemblyAI token
  endpoint directly with API key from Keychain
- OpenRouterModelFetcher: call OpenRouter directly with key from Keychain

**Section 3 — LumaTheme.swift (Light Theme)**
- New file replaces DesignSystem.swift
- Colors: white bg, #F5F5F7 surface, #1D1D1F primary text, #000000 accent
- Typography constants, spacing, corner radii, animation durations
- Zero magic numbers anywhere — all views reference LumaTheme
- Menu bar icon: SF Symbol "lightbulb.fill" in black
- Also create LumaStrings.swift — all user-facing strings as constants

**Section 4 — KeychainManager.swift**
- Security framework, kSecClassGenericPassword
- Service: "com.nox.luma"
- save(key:data:), load(key:) throws Data, delete(key:)

**Section 5 — PINManager.swift + PINEntryView.swift**
- 6-digit PIN stored in Keychain via KeychainManager
- PINEntryView.swift: numeric keypad, shake animation,
  "Incorrect PIN" red label
- Settings requires PIN check; if no PIN set, opens freely
- "Reset Luma" clears all UserDefaults + Keychain + restarts onboarding

**Section 6 — AccountManager.swift**
- LumaAccount model: username, displayName, createdAt,
  avatarInitials (first 2 chars uppercase)
- Stored in UserDefaults (not sensitive)
- Avatar: black circle, white initials, bottom-left of CompanionPanelView

**Section 7 — OnboardingWizardView.swift**
- Full-screen SwiftUI wizard, 5 steps
- Step 1: Welcome (lightbulb icon, "Light by Darkness", Get Started)
- Step 2: Account creation (username + displayName)
- Step 3: PIN setup (optional, numeric keypad, confirm PIN)
- Step 4: API Profile (provider picker, key field masked with eye icon,
  Test Connection button, AssemblyAI key field optional)
- Step 5: Done (checkmark scale animation, "Start Learning →")
- Shown when UserDefaults "hasCompletedOnboarding" == false

**Section 8 — SettingsPanelView.swift**
- Tabbed: Account | API Profiles | Model | General
- Account tab: avatar + username, edit displayName, Reset Luma button
- API Profiles tab: list profiles, add/edit/delete inline,
  Test Connection, Set Default
- Model tab: OpenRouter picker using active profile's key
- General tab: AssemblyAI key (Keychain), Launch at Login,
  PIN management, About (Luma v1.0, © 2026 Omoju Oluwamayowa (Nox))
- Opened via gear icon in CompanionPanelView bottom bar with PIN check

**Section 9 — Companion Panel Bottom Bar**
- Left: avatar circle (initials, black bg, white text) from AccountManager
- Right: gear icon (Settings + PIN check) + power icon
  (Quit Luma with confirmation alert)
- Remove all Farza/Clicky bottom bar content

**Section 10 — APIClient.swift + ProfileManager.swift**
- ProfileManager: stores/retrieves LumaAPIProfile array in Keychain
  (JSON encoded)
- LumaAPIProfile: id, name, provider enum (OpenRouter/Anthropic/
  Google/Custom), apiKey (stored in Keychain separately per profile),
  baseURL, isDefault, selectedModel
- APIClient: reads active profile, routes to correct base URL,
  sets correct auth header:
  - OpenRouter/Custom/Google: Authorization: Bearer {key}
  - Anthropic: x-api-key: {key}
- sendMessage() replaces all direct ClaudeAPI calls in CompanionManager
- Multiple profiles, one default active at a time
- Profile switching instantly swaps active API config

**Section 11 — AssemblyAI Keychain Migration**
- Fetch API key from Keychain key "com.nox.luma.assemblyai"
- Remove proxy token fetch; call AssemblyAI token endpoint directly
- Key stored/retrieved via KeychainManager

**Section 12 — macOS TTS**
- NativeTTSClient.swift kept exactly as-is
- Verify no Clicky/Farza strings remain

**Section 13 — Custom Cursor + Companion Bubble**
- CustomCursorManager.swift: NSCursor from Assets "Luma-cursor",
  set on activate / restore system cursor on hide
- CompanionBubbleWindow.swift: NSPanel (.nonactivatingPanel),
  tracks mouse via NSEvent.addGlobalMonitorForEvents(.mouseMoved)
- Bubble appearance:
  - Rounded rect, corner radius 16pt
  - Black #000000 at 88% opacity
  - NSVisualEffectView backdrop blur (.dark material)
  - Subtle glow: shadow radius 12, opacity 0.4
  - Border: 0.5pt white at 10% opacity
  - Min width 120pt, max width 320pt
  - Padding: 12pt horizontal, 8pt vertical
- Typography: SF Pro Text regular 13pt, white #FFFFFF
- Animates in: scale 0.8→1.0 + fade, 0.15s ease-out
- Animates out: fade, 0.1s
- Follows cursor with spring interpolation (stiffness 200, damping 20)
- Offset 20pt right/below cursor
- Auto-repositions to opposite side near screen edges
- Never steals focus (nonactivatingPanel)
- Cursor image: 8369109.png → Assets.xcassets/Luma-cursor.imageset
- Settings → General: "Custom Cursor" toggle, enabled by default

**Section 14 — WalkthroughEngine (NEW)**

This is Luma's core learning feature. An interactive guided walkthrough
system that uses the macOS Accessibility API to watch screen state and
guide users step by step through any task.

ACTIVATION:
- User presses Ctrl+Option to activate walkthrough mode
- Luma companion bubble shows: "What do you want to learn?"
- User speaks or types their goal
- Luma's AI (via APIClient) breaks the goal into ordered steps
- Luma shows the full step plan in the companion panel for review
- User confirms → walkthrough begins
- User can say "cancel" or press Ctrl+Option again to exit at any time

ARCHITECTURE — create these files:

WalkthroughEngine.swift — central coordinator:
- State machine: idle → planning → confirming → active → complete
- Holds current goal, step array, currentStepIndex
- Coordinates TaskPlanner, AccessibilityWatcher, StepValidator,
  CursorGuide, FeedbackEngine
- Exposed as @Published singleton on CompanionManager

TaskPlanner.swift — AI step generator:
- Takes user goal string + active app name (from NSWorkspace)
- Sends to APIClient with system prompt instructing it to return
  JSON array of steps:
  {
    stepIndex: Int,
    instruction: String,        // what to tell the user
    expectedElement: String?,   // accessibility element to watch (optional)
    expectedAction: String?,    // "click", "focus", "valueChange", "open"
    appBundleID: String?,       // which app this step happens in
    timeoutSeconds: Int         // how long before nudge (default 30)
  }
- Parse JSON response into [WalkthroughStep] array
- If AI returns non-JSON, retry once then show error

AccessibilityWatcher.swift — Accessibility API monitor:
- Request accessibility permission on first use
  (AXIsProcessTrusted(), prompt if not granted)
- Watch focused app via NSWorkspace.shared.frontmostApplication
- Use AXObserver to monitor:
  - AXFocusedUIElementChanged — element focus changes
  - AXSelectedTextChanged — text selection
  - AXValueChanged — field value changes
  - AXWindowCreated — new window opened
  - kAXApplicationActivatedNotification — app switch
- Publish state changes as AccessibilityEvent:
  {
    type: AccessibilityEventType,
    elementRole: String?,     // AXRole of element
    elementTitle: String?,    // AXTitle or AXDescription
    elementValue: String?,    // AXValue
    appBundleID: String,
    timestamp: Date
  }
- Fallback: if accessibility permission denied, use screenshot
  comparison every 2s via ScreenWatcher

ScreenWatcher.swift — vision fallback:
- Only activates if Accessibility API permission not granted
- Takes screenshot every 2s using CGWindowListCreateImage
- Sends to APIClient vision endpoint to detect UI state changes
- Much less accurate than Accessibility API — show warning to user
  "For best results, grant Luma accessibility access in
  System Settings → Privacy → Accessibility"

StepValidator.swift — validates state changes against expected step:
- Takes current AccessibilityEvent + current WalkthroughStep
- Returns ValidationResult: .correct | .incorrect(reason) | .unrelated
- Validation logic:
  - If expectedElement is nil: any meaningful state change = correct
  - If expectedElement set: check if elementTitle/elementRole matches
  - If expectedAction set: check event type matches
  - If appBundleID set: check frontmost app matches
- Wrong action detection:
  - AccessibilityEvent fires but doesn't match expected step
  - → FeedbackEngine tells user what they did wrong and repeats instruction

CursorGuide.swift — points cursor at target element:
- Given an AXUIElement, get its screen frame via
  AXUIElementCopyAttributeValue(kAXFrameAttribute)
- Draw bezier arc from current cursor to element center
  (reuse existing OverlayWindow arc drawing)
- Pulse animation on target element: draw highlight ring that
  pulses 3x then fades
- Support multiple sequential points in one walkthrough step
  (e.g. "first click File, then click New Project")
- Clear all overlays when step is validated as correct

FeedbackEngine.swift — user communication:
- Correct step: 
  - Brief green checkmark pulse on CompanionBubble
  - TTS: short confirmation e.g. "Good, now..." + next instruction
  - Auto-advance to next step after 0.5s delay
- Wrong step:
  - CompanionBubble shows red "That's not quite right"
  - TTS: "That's not the right step. [repeat current instruction]"
  - CursorGuide re-points at correct element
  - Does NOT advance step index
- Timeout (no action after timeoutSeconds):
  - Gentle nudge: "Still on step [N]. [repeat instruction]"
  - Re-point cursor at target
  - After 3 nudges: "Take your time, I'm here when you're ready"
- All complete:
  - CompanionBubble: "You did it! 🎉 [goal] complete"
  - TTS celebration message
  - WalkthroughEngine returns to idle state

WALKTHROUGH UI IN COMPANION PANEL:
- When walkthrough active, CompanionPanelView shows:
  - Progress bar: Step N of M
  - Current step instruction (large, clear text)
  - "Skip this step" button
  - "Cancel walkthrough" button
  - Step list (collapsed, expandable) showing all steps with
    ✓ done / → current / ○ upcoming indicators
- When idle: normal chat interface

PERMISSIONS HANDLING:
- On first walkthrough attempt, check AXIsProcessTrusted()
- If not trusted: show modal explaining why Luma needs
  accessibility access, with "Open System Settings" button
  that deep-links to Privacy & Security → Accessibility
- Don't proceed with walkthrough until permission granted
- Store permission state, don't re-prompt every session

ENTITLEMENTS:
- Add to leanring-buddy.entitlements if not present:
  com.apple.security.automation.apple-events: true
  (accessibility API requires this for sandboxed apps)

---

#### New Files to Create
- `leanring-buddy/LumaTheme.swift`
- `leanring-buddy/LumaStrings.swift`
- `leanring-buddy/KeychainManager.swift`
- `leanring-buddy/PINManager.swift`
- `leanring-buddy/PINEntryView.swift`
- `leanring-buddy/AccountManager.swift`
- `leanring-buddy/ProfileManager.swift`
- `leanring-buddy/APIClient.swift`
- `leanring-buddy/OnboardingWizardView.swift`
- `leanring-buddy/SettingsPanelView.swift`
- `leanring-buddy/CustomCursorManager.swift`
- `leanring-buddy/CompanionBubbleWindow.swift`
- `leanring-buddy/WalkthroughEngine.swift`
- `leanring-buddy/TaskPlanner.swift`
- `leanring-buddy/AccessibilityWatcher.swift`
- `leanring-buddy/ScreenWatcher.swift`
- `leanring-buddy/StepValidator.swift`
- `leanring-buddy/CursorGuide.swift`
- `leanring-buddy/FeedbackEngine.swift`

#### Files to Delete
- `worker/` — entire directory
- `leanring-buddy/DesignSystem.swift` — replaced by LumaTheme.swift
- `leanring-buddy/ClickyAnalytics.swift` — rename to LumaAnalytics.swift

#### Files to Modify
- Every existing Swift source file (rebrand strings)
- `Info.plist` (CFBundleName, usage strings)
- `leanring-buddy.entitlements` (add apple-events entitlement)
- `CLAUDE.md` (rewrite for Luma)

---

#### Resume Instructions for Claude Code
Read this file first every session.
Check which sections are marked [ ] incomplete.
Start from the lowest incomplete TIER number.
Within a tier, work easiest to hardest.
Mark each section [x] complete before moving to next.
Never skip a section — dependencies will break.
After all sections complete: list every file created/modified/deleted
and give exact Xcode steps to build the .app.

#### What NOT to do
- Do not rename the Xcode project/target/scheme in code —
  user will do this manually in Xcode
- Do not invent new UI patterns — match existing Clicky panel style
  updated to LumaTheme light colors
- Do not add analytics or tracking of any kind
- Do not hardcode any API keys, URLs, or secrets anywhere in Swift files
- Do not use magic numbers — everything via LumaTheme.swift
- Do not use inline styles — everything via ViewModifier structs
