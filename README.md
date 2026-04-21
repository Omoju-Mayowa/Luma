<div align="center">

<img src="assets/luma-icon.png" alt="Luma" width="96" />

# Luma

**Light by Darkness**

A native macOS AI teaching assistant that lives beside your cursor.  
Watches your screen, guides you step by step, and teaches you anything — right where you work.

![macOS](https://img.shields.io/badge/macOS-14.0%2B-black?style=flat-square)
![Swift](https://img.shields.io/badge/Swift-5.9-black?style=flat-square)
![Claude](https://img.shields.io/badge/Powered%20by-Claude%20AI-black?style=flat-square)
![License](https://img.shields.io/badge/License-Proprietary-black?style=flat-square)
![Status](https://img.shields.io/badge/Status-v2.2.1-green?style=flat-square)

<img src="assets/luma-demo.png" alt="Luma Demo" width="720" />

</div>

---

## What is Luma?

Luma is a native macOS AI companion built for learners, developers, creatives, and everyone in between. It sits in your menu bar, follows your cursor with a floating companion bubble, and uses the macOS Accessibility API alongside real-time screen analysis to watch what's happening on your screen.

Tell Luma what you want to do. It breaks the task into steps, points at exactly what to click, watches for your actions, validates each one, and corrects you if you go off track — until the task is complete. Like having a senior developer or designer sitting right next to you, except it's always there, it never judges you, and it works with your own API keys so your data stays yours.

The entire system is built to be frugal with API calls. Most of what Luma does — nudging you, detecting elements, compressing your voice input — runs completely on-device with zero API cost. Claude is reserved for reasoning: planning your steps, verifying progress, and locating elements when on-device methods fall short.

---

## Features

### Core Experience
- **Interactive Walkthroughs** — Press `Ctrl + Option`, speak your goal naturally, and Luma generates a step-by-step guided walkthrough. It watches your screen in real time, validates each action, corrects wrong moves offline, and nudges you if you go idle — with minimal API usage throughout.
- **Voice Input** — Speak to Luma via Apple Speech (SFSpeechRecognizer). Fully on-device, instant, no third-party transcription service or API key required.
- **Prompt Compression** — Before sending anything to Claude, Luma strips filler words from your transcript using an offline keyword filter. "Hey Luma can you please like help me compress my downloads folder" becomes "compress downloads folder" — reducing token usage by up to 60% per request.
- **Native TTS** — Luma speaks back using macOS AVSpeechSynthesizer. Coordinate strings like "point 400, 200" are automatically stripped before speaking so responses always sound natural. No ElevenLabs, no credits, no limits.
- **Request Override** — Speak a new request at any time. Luma immediately cancels the active walkthrough and responds to what you just said — no need to wait or manually cancel.
- **Custom Cursor** — A minimal black teardrop cursor replaces your system cursor while Luma is active — a subtle signal that your AI teacher is watching and ready.
- **Companion Bubble** — A floating translucent black bubble follows your cursor across the entire screen, showing Luma's responses and step instructions right where you're working.

### Intelligence & Detection
- **Triple-Validation Architecture** — Every element Luma points at is verified three ways before the cursor moves: Accessibility API scan, MobileNetV2 visual detection, and Claude coordinate verification. If any layer is uncertain, Luma waits rather than guessing.
- **LumaImageProcessingEngine** — The dual-source element detection system. Runs an Accessibility API tree scan and a MobileNetV2 screenshot classification simultaneously, cross-validates results, and picks the highest-confidence coordinate. Falls back gracefully when one source fails.
- **MobileNetV2 (Core ML)** — Apple's pre-trained MobileNetV2 model runs fully on-device. It crops a 160×160px region around Claude's target coordinate and classifies what's there before the cursor moves. Loaded from `MobileNetV2.mlmodel` — no internet required after first build.
- **AXDockItem Priority** — When searching for app icons, Luma correctly targets Dock items (AXDockItem) over menu bar items (AXMenuBarItem). If both exist for the same label, Dock items are scored +100 and menu bar items are penalised −50.
- **Corrected Coordinate Conversion** — AX API returns coordinates in screen space (top-left origin). Luma correctly converts to AppKit space (bottom-left origin) before moving the cursor: `centerY = screenHeight − axFrame.origin.y − (axFrame.height / 2)`.
- **LumaTaskClassifier** — Offline keyword heuristic classifier that routes every request to the right handler before touching Claude. Detects multi-step requests ("open Safari and go to google.com"), single-step commands ("find the settings button"), and questions — with confidence scores logged for every decision.

### Walkthrough Engine
- **Step Planning** — Claude receives the compressed transcript and a screenshot, then returns a structured step plan. Steps are labeled, ordered, and each includes the exact AX element name to watch for.
- **Typing Step Detection** — When a step requires typing, Luma detects the quoted text in the step description, waits 1.5 seconds for the correct field to receive focus, then polls `AXValue` every 0.5 seconds. The step only advances when the typed text matches — case-insensitive. The nudge timer is completely blocked during typing steps.
- **NudgeEngine (Offline)** — All walkthrough corrections and nudges go through NudgeEngine — zero Claude API calls. Templates cover element not found, wrong app, timeout, retry, step complete, and stuck-after-three-nudges. Only the stuck escalation calls Claude, once.
- **Periodic Claude Verification** — Claude re-checks overall walkthrough progress every 5 completed steps. Between verifications, all guidance is offline.
- **Bundle ID Normalisation** — All app bundle ID comparisons use `.lowercased()` on both sides. `com.apple.Notes` and `com.apple.notes` are treated identically.
- **Frontmost App Validation** — Before taking a validation screenshot, Luma checks that the target app is frontmost. If it isn't, validation is skipped and logged rather than sending a screenshot of the wrong screen to Claude.

### API & Cost Management
- **Request Queue** — All Claude API calls go through a single queue with a minimum 15-second gap between requests. No concurrent calls, ever. Costs dropped from ~$0.04 to ~$0.02 per walkthrough after this fix.
- **429 Retry Logic** — On a rate limit response, Luma waits 60 seconds then retries once. If the retry also fails, the call is skipped gracefully — no crash, no loop.
- **Bring Your Own Keys** — Connect directly to OpenRouter, Anthropic, Google AI, or any custom OpenAI-compatible endpoint. No Luma servers involved in your conversations. Keys are never transmitted to Luma's infrastructure.
- **Multi-Profile System** — Create multiple API profiles for different providers or use cases. Set a default, switch instantly, manage everything from settings.
- **Smart Model Switcher** — Browse all OpenRouter models split into Free and Paid sections, searchable, with recommended badges. Model selection persists per profile in Keychain.

### Security & Privacy
- **Keychain Storage** — All API keys are stored in macOS Keychain with `kSecAttrAccessibleAfterFirstUnlock`. After granting access once, Luma reads keys silently — no repeated permission dialogs per session.
- **PIN Security** — Protect settings with a 6-digit PIN stored in Keychain. Numeric keypad UI with shake animation on wrong entry.
- **Zero Telemetry** — No analytics, no crash reporting, no usage data. Nothing leaves your Mac except your API calls to your chosen provider.
- **Permissions Recovery** — If screen recording or accessibility permission is granted after launch, Luma detects the change and re-initialises the overlay without requiring an app restart.

---

## Getting Started

**Requirements:** macOS 14.0+, Apple Silicon or Intel Mac, Xcode 15+ (to build from source), an API key from any supported provider.

```bash
git clone https://github.com/Omoju-Mayowa/luma.git
cd luma
open leanring-buddy.xcodeproj
```

Hit `⌘R` to build and run. The onboarding wizard walks you through everything:

1. **Username** — Sets your display name and avatar initials
2. **PIN** (optional) — Protects your settings panel
3. **API Profile** — Enter your provider, API key, and select a model
4. **Permissions** — Grant Accessibility and Screen Recording access

No Cloudflare worker, no backend deployment, no terminal commands beyond the clone.

**MobileNetV2 setup:**  
Download `MobileNetV2.mlmodel` from [Apple's Core ML model gallery](https://developer.apple.com/machine-learning/models/) and drag it into the Xcode project under `Resources/Models/`, ensuring it's added to the app target. Xcode compiles it to `.mlmodelc` on first build automatically. Without it, visual detection is disabled and Luma falls back to AX-only element finding — everything still works, just with lower confidence.

---

## How Luma Works

### The Full Pipeline

<img src="assets/luma_flowchart_v3.svg" alt="Luma Pipeline Flowchart" />

```
User speaks
  ↓
Apple Speech transcribes (on-device, offline)
  ↓
LumaMLEngine.compressPrompt() strips filler words (offline)
  [RAW]        "hey luma can you please help me open safari and go to google"
  [COMPRESSED] "open safari and go to google"
  ↓
LumaTaskClassifier routes the request (offline)
  .multiStep  confidence=0.80 → WalkthroughEngine
  .singleStep confidence=0.75 → direct Claude voice response
  .question   confidence=0.80 → direct Claude voice response
  ↓
Claude receives compressed prompt + screenshot (one API call)
  ↓
Claude returns structured step plan
  ↓
For each step:
  LumaImageProcessingEngine finds the target element
    → AX tree scan (offline)
    → MobileNetV2 region classification (offline, Core ML)
    → Cross-validate both results
    → If confidence < threshold → Claude screenshot fallback (API call)
  CursorGuide animates Luma cursor to verified coordinate
  AccessibilityWatcher monitors for user action
    ✓ Correct → NudgeEngine speaks "Got it" → advance
    ✗ Wrong   → NudgeEngine speaks correction offline → re-point
    ⏱ 30s idle → NudgeEngine nudges (×3 max)
    🔁 Stuck×3 → escalate to Claude once
  Every 5 steps → Claude re-verifies overall progress (API call)
  ↓
All steps complete → "You did it!" → idle
```

### Typing Step Flow

```
Step description: "Now type 'hello world' into the new note."
  ↓
isTypingStepActive = true
Nudge timer invalidated — no advances possible
AI validation blocked at result-handling site
  ↓
Wait 1.5 seconds (let correct field receive focus after navigation)
  ↓
[Luma] Typing poller: capturing focused element after delay
  ↓
Poll AXValue every 0.5s — case-insensitive match
  [Luma] Typing poll: current='' expected='hello world' match=false
  [Luma] Typing poll: current='hel' expected='hello world' match=false
  [Luma] Typing poll: current='hello world' expected='hello world' match=true
  ↓
[Luma] WalkthroughEngine: typing step complete — found after 7.0s
isTypingStepActive = false → advance step normally
Timeout = max(30s, charCount × 1.5s) if text never appears
```

---

## Supported Providers

| Provider | Auth Header | Free Tier | Recommended Model |
|---|---|---|---|
| OpenRouter | `Authorization: Bearer` | ✅ Yes | `google/gemini-2.5-flash:free` |
| Anthropic | `x-api-key` | ❌ No | `claude-sonnet-4-6` |
| Google AI | `Authorization: Bearer` | ✅ Yes | `gemini-2.5-flash` |
| Custom | `Authorization: Bearer` | Depends | Any OpenAI-compatible endpoint |

**Recommended free setup:** OpenRouter with `google/gemini-2.5-flash:free` — zero cost, solid reasoning, fast responses.

---

## Architecture

```
Luma/
├── Core/
│   ├── APIClient.swift                      # Unified API routing, request queue, 429 retry
│   ├── ProfileManager.swift                 # Multi-profile management + Keychain storage
│   ├── AccountManager.swift                 # Local account (username, avatar initials)
│   ├── KeychainManager.swift                # macOS Keychain wrapper
│   ├── PINManager.swift                     # 6-digit PIN security
│   └── VaultManager.swift                   # Single Keychain vault for all sensitive data
│
├── ML/
│   ├── LumaMLEngine.swift                   # Prompt compression + MobileNetV2 coordinate validation
│   ├── LumaMobileNetDetector.swift          # Core ML visual UI element detection
│   ├── LumaTaskClassifier.swift             # Offline single/multi-step/question classifier
│   ├── LumaOnDeviceAI.swift                 # On-device AI coordinator
│   └── LumaWhisperEngine.swift              # Whisper encoder (decoder pending, falls back to Apple Speech)
│
├── Walkthrough/
│   ├── WalkthroughEngine.swift              # Central state machine + typing step poller
│   ├── TaskPlanner.swift                    # Claude step generation
│   ├── NudgeEngine.swift                    # Offline correction templates (zero API calls)
│   ├── LumaImageProcessingEngine.swift      # Dual-source AX + MobileNet element finder
│   ├── CursorGuide.swift                    # Luma cursor animation + AI screenshot pointing
│   ├── AccessibilityWatcher.swift           # AX observer for user action detection
│   └── StepValidator.swift                  # Action validation + coordinate retry
│
├── UI/
│   ├── CompanionPanelView.swift             # Main companion panel
│   ├── CompanionBubbleWindow.swift          # Cursor-following floating bubble
│   ├── OnboardingWizardView.swift           # 4-step first launch wizard
│   ├── SettingsPanelView.swift              # Tabbed settings (Account, Profiles, Model, General)
│   └── PINEntryView.swift                   # Numeric PIN keypad with shake animation
│
├── Overlay/
│   ├── OverlayWindow.swift                  # Full-screen transparent overlay
│   └── CustomCursorManager.swift            # Black teardrop cursor
│
├── TTS/
│   └── NativeTTSClient.swift                # AVSpeechSynthesizer + coordinate string sanitizer
│
├── Theme/
│   ├── LumaTheme.swift                      # Design tokens (colors, typography, spacing, radii)
│   └── LumaStrings.swift                    # All user-facing strings as constants
│
└── Resources/
    └── Models/
        ├── MobileNetV2.mlmodel              # Apple Core ML model (download from Apple model gallery)
        └── whisper-tiny.mlmodelc            # Whisper encoder (on-device STT, decoder pending)
```

---

## Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| `Ctrl + Option` | Activate voice input / start walkthrough |
| `Ctrl + Option` (again while active) | Cancel active walkthrough |
| Click menu bar icon | Toggle companion panel |

---

## Cost Profile

Luma is engineered to minimise API spend without sacrificing capability. Most operations are free.

| Operation | Runs on | API cost |
|---|---|---|
| Voice transcription | Apple Speech (on-device) | Free |
| Prompt compression | Swift keyword filter (on-device) | Free |
| Task classification | LumaTaskClassifier (on-device) | Free |
| Element detection | AX API + MobileNetV2 (on-device) | Free |
| Walkthrough nudges | NudgeEngine templates (on-device) | Free |
| Step planning | Claude — one call per walkthrough | ~$0.01 |
| Coordinate fallback | Claude screenshot — rare | ~$0.005 |
| Periodic verification | Claude — every 5 steps | ~$0.005 |
| **Typical walkthrough total** | | **~$0.02** |

---

## Roadmap

**v1.0 — Local** ✅ Complete
- [x] Custom cursor + companion bubble
- [x] Multi-profile API config with Keychain storage
- [x] Smart model switcher (OpenRouter free/paid)
- [x] PIN-secured settings panel
- [x] 4-step onboarding wizard
- [x] Native TTS with coordinate string sanitization
- [x] Voice input via Apple Speech (fully on-device)
- [x] Prompt compression — 50-60% token reduction offline
- [x] LumaTaskClassifier — offline single/multi/question routing
- [x] WalkthroughEngine — full step-by-step guided walkthrough
- [x] LumaImageProcessingEngine — dual AX + MobileNet element detection
- [x] MobileNetV2 (Core ML) — on-device visual coordinate validation
- [x] NudgeEngine — offline corrections, zero API calls per nudge
- [x] Typing step poller — waits for actual typed text before advancing
- [x] Request queue — 15s spacing, 429 retry, ~$0.02 per walkthrough
- [x] Request override — new request instantly cancels active walkthrough
- [x] AXDockItem priority — Dock icons correctly scored over menu bar items
- [x] Y coordinate conversion — correct AppKit vs screen space math
- [x] Bundle ID normalisation — case-insensitive across all comparison paths
- [x] Keychain `kSecAttrAccessibleAfterFirstUnlock` — no repeated OS prompts
- [x] Permissions recovery — overlay reappears after grant without restart

**v2.0 — Accounts**
- [ ] Go backend (JWT auth, argon2id hashing)
- [ ] Cross-device profile sync
- [ ] Plan-based profile limits
- [ ] Full on-device STT via WhisperKit (encoder + decoder)

**v3.0 — SaaS**
- [ ] Stripe billing integration
- [ ] Free + Pro tiers
- [ ] Public release

---

## Privacy

API keys live exclusively in macOS Keychain — never in UserDefaults, never in plaintext, never logged. After the first access grant, keys are read silently with `kSecAttrAccessibleAfterFirstUnlock`. Conversations go directly from your Mac to your chosen provider — Luma has no servers that touch your messages. Voice transcription runs fully on-device via Apple Speech. Screen access via the Accessibility API is only active during a walkthrough. No analytics. No telemetry. No exceptions.

---

## Developer

**Omoju Oluwamayowa** (Nox) — Full-stack developer & UI/UX designer, Lagos, Nigeria.  
Built solo in Swift for the Claude AI Hackathon at UNILAG, April 2026.

---

## License

Copyright © 2026 Omoju Oluwamayowa (Nox). All rights reserved.  
This software is proprietary. You may not distribute, sublicense, or use it commercially without explicit written permission from the author.

---

<div align="center">
  <sub>Built by Nox · Lagos, Nigeria · 2026</sub>
</div>
