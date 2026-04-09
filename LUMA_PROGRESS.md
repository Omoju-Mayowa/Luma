## LUMA REBUILD PROGRESS
### Session state — 2026-04-09 (resume here after recharge)

---

#### ✅ Completed this session (2026-04-09)

- [x] DS. → LumaTheme. migration across all view files (OverlayWindow, CompanionPanelView, CompanionResponseOverlay)
- [x] Removed `typealias DS = LumaTheme` from LumaTheme.swift
- [x] Entitlements: added `com.apple.security.temporary-exception.apple-events`
- [x] Info.plist: hardcoded `CFBundleIdentifier = com.nox.luma`
- [x] Added `AXIsProcessTrusted()` prompt in `applicationDidFinishLaunching`
- [x] LumaTheme.swift: **FULL DARK REWRITE** — flat struct with dark colors (`#0A0A0A` bg, `#FFFFFF` text, etc.) + backward-compat nested enum aliases so all existing views keep compiling
- [x] Menu bar icon: replaced custom triangle drawing with SF Symbol `lightbulb.fill` (isTemplate = true, adapts to light/dark menu bar)
- [x] MenuBarPanelManager: added `panel.appearance = NSAppearance(named: .darkAqua)` and `.preferredColorScheme(.dark)` on hosted SwiftUI view
- [x] OnboardingWizardView: fixed button hover state (white button no longer flashes black on hover)
- [x] AssemblyAI isConfigured bug fixed — now checks Keychain instead of always returning true
- [x] GlobalPushToTalkShortcutMonitor: added debug logging for tap registration success/failure
- [x] BuddyTranscriptionProvider + BuddyDictationManager: added provider selection logging at startup
- [x] Text input fallback: `CompanionManager.showTextInputFallback` observes `currentPermissionProblem`, `submitTextInput()` feeds typed text through same AI pipeline as voice
- [x] CompanionPanelView: text field + send button shown when voice unavailable; hint text updates accordingly
- [x] Dark theme sheets: `.preferredColorScheme(.dark)` added to OnboardingWizardView and SettingsPanelView sheet presentations

#### 🔴 Pending — Next session priorities

- [x] Post-onboarding tutorial: `PostOnboardingTutorialManager.swift` — 5 steps, auto-advance 4s, progress dots, pulse ring on shortcut hint, stored in `UserDefaults "hasCompletedTutorial"`. Triggered from `CompanionPanelView.onAppear`. Overlay card covers panel content while active.

**Remaining**
- [ ] Product → Clean Build Folder (⌘⇧K) in Xcode, rebuild, smoke test

---

#### Previous Sessions — All Completed (2026-04-08)

**TIER 1 — Pure string/config changes**
- [x] Section 1 — Rebrand (string replacements, Info.plist, CLAUDE.md)
- [x] Section 2a — Delete worker/ directory
- [x] Delete DesignSystem.swift, rename ClickyAnalytics → LumaAnalytics

**TIER 2 — New isolated files**
- [x] Section 3 — LumaTheme.swift + LumaStrings.swift
- [x] Section 4 — KeychainManager.swift
- [x] Section 6 — AccountManager.swift

**TIER 3 — Files that depend on Tier 2**
- [x] Section 5 — PINManager.swift + PINEntryView.swift
- [x] Section 10a — ProfileManager.swift
- [x] Section 10b — APIClient.swift

**TIER 4 — Worker removal + direct API wiring**
- [x] Section 2b — Remove workerBaseURL from CompanionManager, wire APIClient
- [x] Section 11 — AssemblyAI Keychain migration + direct token fetch
- [x] Section 2c — OpenRouterModelFetcher removed

**TIER 5 — UI rebuilds**
- [x] Section 9 — Companion Panel bottom bar rebuild
- [x] Section 8 — SettingsPanelView.swift (tabbed settings)
- [x] Section 7 — OnboardingWizardView.swift (5-step wizard)

**TIER 6 — Overlay + cursor**
- [x] Section 12 — macOS TTS (NativeTTSClient with AVSpeechSynthesizer)
- [x] Section 13 — CustomCursorManager + CompanionBubbleWindow
- [x] Section 14 — WalkthroughEngine (complete)

---

#### Key Files Reference

| File | Purpose |
|------|---------|
| `leanring_buddyApp.swift` | App entry point, CompanionAppDelegate |
| `CompanionManager.swift` | Central state machine, voice pipeline |
| `MenuBarPanelManager.swift` | NSStatusItem + NSPanel lifecycle |
| `CompanionPanelView.swift` | Main panel SwiftUI UI |
| `LumaTheme.swift` | Dark design system (flat struct + compat aliases) |
| `BuddyTranscriptionProvider.swift` | Provider factory: AssemblyAI → Apple Speech fallback |
| `AssemblyAIStreamingTranscriptionProvider.swift` | ⚠️ isConfigured MUST check Keychain |
| `AppleSpeechTranscriptionProvider.swift` | Built-in fallback, works offline |
| `GlobalPushToTalkShortcutMonitor.swift` | CGEvent tap for Ctrl+Option (requires Accessibility) |
| `BuddyDictationManager.swift` | Push-to-talk voice pipeline |
| `OnboardingWizardView.swift` | 5-step onboarding wizard |
| `SettingsPanelView.swift` | Tabbed settings sheet |
| `CompanionBubbleWindow.swift` | Dark floating tooltip bubble |
| `OverlayWindow.swift` | Full-screen cursor overlay |
| `leanring-buddy.entitlements` | Entitlements (sandbox off, apple-events on) |
| `Info.plist` | CFBundleIdentifier = com.nox.luma (hardcoded) |

---

#### Resume Instructions
1. Read this file
2. Start from topmost item in **P0** pending list
3. Fix AssemblyAI isConfigured first — it's the root cause of silent voice failure
4. Run Product → Clean Build Folder (⌘⇧K), then build
5. Test hotkey: grant Accessibility in System Settings, relaunch, press Ctrl+Option
