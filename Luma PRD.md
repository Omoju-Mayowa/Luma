# Luma — Product Requirements Document

**Version:** 2.2.1
**Last Updated:** 2026-04-21
**Bundle ID:** `com.nox.luma`
**Status:** Active development

---

## Table of Contents

1. [Product Overview](#1-product-overview)
2. [System Requirements](#2-system-requirements)
3. [Permissions Required](#3-permissions-required)
4. [Architecture Overview](#4-architecture-overview)
5. [First-Launch Onboarding](#5-first-launch-onboarding)
6. [Security Model](#6-security-model)
7. [Voice Input Pipeline](#7-voice-input-pipeline)
8. [AI & API Layer](#8-ai--api-layer)
9. [Walkthrough System](#9-walkthrough-system)
10. [Element Detection System (LIPE)](#10-element-detection-system-lipe)
11. [On-Device ML Layer](#11-on-device-ml-layer)
12. [Cursor Overlay System](#12-cursor-overlay-system)
13. [Text-to-Speech](#13-text-to-speech)
14. [Screen Capture](#14-screen-capture)
15. [UI Components](#15-ui-components)
16. [Design System](#16-design-system)
17. [Analytics](#17-analytics)
18. [Auto-Update](#18-auto-update)
19. [Data Storage Map](#19-data-storage-map)
20. [API Endpoints & Providers](#20-api-endpoints--providers)
21. [Hardcoded Configuration Values](#21-hardcoded-configuration-values)
22. [Key Files Reference](#22-key-files-reference)
23. [Known Limitations](#23-known-limitations)

---

## 1. Product Overview

Luma is a native macOS AI teaching assistant that lives entirely in the menu bar. It has no dock icon and no main application window. The user activates it via a push-to-talk keyboard shortcut (`ctrl+option`), speaks a question or task, and Luma responds with:

- Streamed text shown in a floating overlay on screen
- Voice response via macOS native TTS
- A blue animated cursor companion that flies to and points at UI elements referenced in the response
- Step-by-step guided walkthroughs for multi-step tasks (e.g., "how do I compress a folder?")

The app is designed for screen-reader-friendly, non-intrusive operation. It never moves the user's OS cursor. All visual feedback happens through a transparent full-screen overlay layer.

### Core Use Cases

| Use Case | How it Works |
|---|---|
| Quick question | Push-to-talk → transcribe → send to AI → stream spoken + visual response |
| Find a UI element | Push-to-talk → "where is the Bold button?" → cursor flies to it |
| Step-by-step walkthrough | Push-to-talk → "how do I set up Time Machine?" → Luma plans steps, speaks each one, points the cursor, watches for user action, advances automatically |
| One-off pointing | Voice query triggers screenshot → AI identifies element → cursor animates to location |

---

## 2. System Requirements

### Minimum Requirements

| Requirement | Minimum | Notes |
|---|---|---|
| **Operating System** | macOS 14.0 Sonoma | Required for ScreenCaptureKit APIs used for screen capture |
| **Architecture** | Apple Silicon (M1+) or Intel x86_64 | Universal binary |
| **RAM** | 4 GB | On-device ML models (MobileNetV2) load into memory |
| **Storage** | 150 MB free | App bundle + bundled ML models |
| **Internet** | Required at runtime | All AI inference calls external APIs |
| **Microphone** | Required | Built-in or external, for push-to-talk voice input |
| **Display** | Any resolution | Multi-monitor supported; overlay auto-sizes to each screen |

### Recommended Requirements

| Requirement | Recommended | Notes |
|---|---|---|
| **Operating System** | macOS 15.0 Sequoia or later | Better ScreenCaptureKit stability |
| **RAM** | 8 GB+ | Comfortable headroom when MobileNetV2 + Vision pipeline run concurrently |
| **Internet** | Low-latency broadband | SSE streaming responses feel real-time at <50ms latency |
| **Microphone** | Good SNR mic | Reduces transcription errors from AssemblyAI |

### macOS Frameworks Required at Runtime

These are not installed by the user — they ship with macOS — but they impose the OS version floor:

| Framework | Minimum macOS | Purpose |
|---|---|---|
| ScreenCaptureKit | macOS 12.3+ | Screen recording (14.2+ features used) |
| AVFoundation | macOS 10.7+ | Audio engine, push-to-talk capture |
| AVSpeechSynthesizer | macOS 10.14+ | Native TTS (Zoe Enhanced voice) |
| Vision | macOS 10.15+ | On-device text + rectangle detection |
| CoreML | macOS 10.13+ | MobileNetV2 visual validation |
| Speech | macOS 10.15+ | Apple Speech fallback transcription |
| ApplicationServices | macOS 10.0+ | Accessibility API (AX) tree scanning |
| ServiceManagement | macOS 10.6+ | Login item registration |

### API Key Requirements

The user must have at least one valid API key from a supported provider. The app cannot function without one:

| Provider | Key Type | Where to Get |
|---|---|---|
| OpenRouter | Bearer token | openrouter.ai (recommended — free models available) |
| Anthropic | API key | console.anthropic.com |
| Google AI | Bearer token | aistudio.google.com |
| Custom (OpenAI-compatible) | Bearer token | Provider-specific |

---

## 3. Permissions Required

Luma requests the following macOS permissions. The user is guided through granting them during onboarding. The app polls for permission state periodically and shows recovery UI if a permission is revoked.

| Permission | Purpose | When Requested | App Behavior if Denied |
|---|---|---|---|
| **Microphone** | Capture audio for push-to-talk | First use of voice | Push-to-talk button disabled; shows "Enable Microphone" toggle in panel |
| **Screen Recording** | Screenshot for AI vision + element location | First use | AI vision calls disabled; overlay still visible but no screenshots sent |
| **Accessibility** | AX tree scanning for element finding | First use of walkthrough | Element pointing falls back to visual/AI-only; walkthrough still runs |

### Entitlements (App Sandbox: OFF)

The app runs **without App Sandbox** (`com.apple.security.app-sandbox = false`). This is required to:

- Access the global CGEvent tap for push-to-talk hotkey detection
- Read the Accessibility API tree of arbitrary running applications
- Use ScreenCaptureKit with the system picker

Active entitlements:

```
com.apple.security.app-sandbox               = false
com.apple.security.network.client            = true   (outbound HTTPS/WSS)
com.apple.security.device.camera             = true   (declared; microphone is the audio-input)
com.apple.security.device.audio-input        = true   (microphone for push-to-talk)
com.apple.security.automation.apple-events   = true   (Apple Events for UI automation)
com.apple.security.temporary-exception.mach-lookup.global-name
  → com.apple.screencapturekit.picker        (ScreenCaptureKit system picker access)
```

---

## 4. Architecture Overview

### App Type

- **LSUIElement = true** — no Dock icon, no main window
- All UI surfaces are either: the menu bar status icon, the floating companion panel, or the full-screen transparent overlay

### Architectural Pattern

MVVM with `@StateObject` / `@Published` state management throughout. All UI state updates run on `@MainActor`. Async operations use Swift's `async/await` and structured concurrency.

### Component Layers

```
┌─────────────────────────────────────────────────────────────┐
│                    User Interaction Layer                    │
│  Menu bar icon → CompanionPanelView → SettingsPanelView      │
│  Overlay → OverlayWindow → CompanionResponseOverlay          │
└────────────────────────┬────────────────────────────────────┘
                         │
┌────────────────────────▼────────────────────────────────────┐
│                     Orchestration Layer                      │
│  CompanionManager (voice pipeline + overlay state)           │
│  WalkthroughEngine (step planning + execution state machine) │
└──────────────┬───────────────────────┬──────────────────────┘
               │                       │
┌──────────────▼────────┐  ┌───────────▼──────────────────────┐
│    Input / STT        │  │          AI / API                │
│  BuddyDictationMgr    │  │  APIClient (request queue)        │
│  GlobalPTTMonitor     │  │  ProfileManager (multi-provider) │
│  AssemblyAI Provider  │  │  TaskPlanner (step generation)   │
│  AppleSpeech Provider │  │  NudgeEngine (offline nudges)    │
└───────────────────────┘  └──────────────────────────────────┘
               │                       │
┌──────────────▼───────────────────────▼──────────────────────┐
│                  Element Detection Layer                     │
│  LumaImageProcessingEngine (AX + visual, parallel)          │
│  LumaOnDeviceAI → LumaMobileNetDetector (Layer 1+2)         │
│  APIClient visual fallback (Layer 3)                        │
│  CursorGuide (overlay notification dispatch)                │
└────────────────────────┬────────────────────────────────────┘
                         │
┌────────────────────────▼────────────────────────────────────┐
│                    Overlay / Output Layer                    │
│  OverlayWindow (one per display, .screenSaver level)        │
│  NativeTTSClient (AVSpeechSynthesizer)                      │
│  CompanionScreenCaptureUtility (ScreenCaptureKit)           │
└─────────────────────────────────────────────────────────────┘
```

### Key Singletons

| Singleton | Class | Purpose |
|---|---|---|
| `LumaImageProcessingEngine.shared` | `LumaImageProcessingEngine` | Element detection authority |
| `WalkthroughEngine.shared` | `WalkthroughEngine` | Walkthrough state machine |
| `LumaOnDeviceAI.shared` | `LumaOnDeviceAI` | On-device ML coordinator |
| `APIClient.shared` | `APIClient` | AI API request router |
| `NativeTTSClient.shared` | `NativeTTSClient` | Text-to-speech |
| `CursorGuide.shared` | `CursorGuide` | Cursor animation dispatcher |

---

## 5. First-Launch Onboarding

A 5-step wizard (`OnboardingWizardView`) runs on first launch, gated by the `hasCompletedOnboarding` flag in UserDefaults.

### Step 1 — Welcome
- Displays Luma branding and app description
- Single CTA: "Get Started"

### Step 2 — Account Creation
- User enters: **Username** (alphanumeric) + **Display Name** (free text)
- Stored locally in `AccountManager` → UserDefaults
- No server-side account; fully local

### Step 3 — PIN Setup (Optional)
- User can set a 6-digit numeric PIN for app protection
- PIN stored in `VaultManager` → macOS Keychain
- If skipped, no PIN protection is applied

### Step 4 — API Profile Setup
- User selects AI provider: OpenRouter, Anthropic, Google AI, or Custom
- User enters their API key
- User selects a model from a live-fetched list (or manually enters model ID for custom providers)
- Profile written to `ProfileManager`; API key written to `VaultManager`

### Step 5 — Done + Permissions Prompt
- Shows what Luma can do
- Prompts user to grant: Microphone, Screen Recording, Accessibility
- Dismisses onboarding and starts the post-onboarding tutorial

### Post-Onboarding Tutorial

A 5-step guided tutorial (`PostOnboardingTutorialManager`) runs automatically once after onboarding:

1. Highlights the menu bar icon with a pulse ring
2. Shows how to open the companion panel
3. Shows how to use push-to-talk
4. Demonstrates the overlay cursor
5. Tutorial complete — dismissed

Each step auto-advances after **4 seconds**. Completion is persisted in UserDefaults as `hasCompletedTutorial`.

---

## 6. Security Model

### API Key Storage

All sensitive data is stored in the **macOS Keychain**, never in UserDefaults or the app bundle.

**Keychain Service:** `com.nox.luma`
**Accessibility:** `kSecAttrAccessibleAfterFirstUnlock`
- Keys are readable after device first-unlock post-reboot
- No additional user interaction needed for subsequent reads in the same session

**Vault Structure**

A single Keychain item (`com.nox.luma.vault`) stores a JSON-encoded `LumaVault`:

```swift
struct LumaVault: Codable {
    var pin: String?                    // 6-digit PIN, nil if not set
    var apiKeys: [String: String] = []  // profileID (UUID string) → API key
}
```

Vault is cached in-memory after first read for performance. Profile metadata (names, providers, model IDs) lives in UserDefaults — these are non-sensitive.

### PIN Protection

- 6-digit numeric PIN
- Stored in the vault (Keychain)
- PIN entry uses a native numeric keypad with shake animation on incorrect entry
- **No brute-force lockout** in current implementation
- PIN is optional; not required for app function

### Network Security

- All API calls use HTTPS (TLS 1.2+)
- TLS session is pre-warmed on `APIClient` init to reduce cold-start latency
- No custom certificate pinning
- No Cloudflare Worker proxy — API keys go directly to providers
- AssemblyAI uses WSS (WebSocket Secure) for streaming transcription

### Analytics

PostHog is the only telemetry. It receives:
- Anonymous usage events (interactions, errors)
- No API keys, no transcripts of full conversations, no personal identifiers beyond what PostHog auto-collects (anonymous device ID)

---

## 7. Voice Input Pipeline

### Push-to-Talk Shortcut

- **Default hotkey:** `ctrl + option` (both keys held simultaneously)
- Implemented via a listen-only `CGEvent` tap (`GlobalPushToTalkShortcutMonitor`)
- Works system-wide — even when other apps are focused
- Does **not** require the app to be frontmost

### Audio Capture

`BuddyDictationManager` owns the audio pipeline:

1. On hotkey press: `AVAudioEngine` starts, installs a tap on the input bus
2. Audio captured as raw PCM buffers (microphone default format)
3. Buffers forwarded to the active transcription provider in real time
4. On hotkey release: provider is asked to finalize the transcript
5. Finalized transcript handed to `CompanionManager`

### Transcription Providers

Provider is resolved from `VoiceTranscriptionProvider` in Info.plist (factory pattern in `BuddyTranscriptionProvider`).

| Provider | Type | Notes |
|---|---|---|
| **AssemblyAI** (primary) | Real-time streaming via WebSocket | Fetches temp tokens from AssemblyAI using Keychain key; model: `u3-rt-pro`; PCM16 mono audio streamed over WSS; turn-based transcript with finalization on key-up |
| **OpenAI** | Upload-based | Buffers push-to-talk audio locally; uploads as WAV on key-release; returns finalized transcript |
| **Apple Speech** | Local, on-device | `SFSpeechRecognizer`; used as fallback when no cloud STT key is available |

**AssemblyAI Session Architecture:**
A single `URLSession` is shared across all AssemblyAI streaming sessions (owned by the provider, not the individual session). Creating and invalidating a URLSession per session corrupts the OS connection pool, causing "Socket is not connected" errors after rapid reconnections.

### Audio Conversion

`BuddyAudioConversionSupport` handles:
- Converting live `AVAudioPCMBuffer` input → PCM16 mono (for cloud STT streaming)
- Building WAV file payloads (for upload-based providers)
- Sample rate conversion if the device's native rate differs from what the provider expects

### Voice State Machine

`CompanionManager` tracks `CompanionVoiceState`:

```
idle → listening → processing → responding → idle
```

| State | Trigger | What Happens |
|---|---|---|
| `listening` | Hotkey pressed | Waveform animates; audio captures; TTS interrupts if playing |
| `processing` | Hotkey released | Transcript finalized; screenshot captured; API call initiated |
| `responding` | First streaming chunk received | Response text streams into overlay; TTS begins speaking |
| `idle` | TTS finishes (or user presses hotkey again) | Overlay fades; waveform stops |

---

## 8. AI & API Layer

### APIClient

`APIClient.shared` is the single outbound AI request router. It enforces:

- **One active request at a time** — concurrent calls queue behind a `CheckedContinuation` array
- **15-second minimum gap** between consecutive requests (respects free-tier rate limits)
- **429 retry logic**: on rate limit, waits 60 seconds then retries once
- **Profile-based routing**: reads active profile from `ProfileManager` on each request — model, base URL, and auth headers are all profile-driven

#### TLS Warmup

On `APIClient.init()`, a silent `HEAD` request is made to the active provider's base URL. This pre-establishes the TLS session ticket, so the first real user-facing request avoids cold TLS handshake overhead (~200–400ms).

#### Public API Surface

| Method | Purpose |
|---|---|
| `analyzeImage(images:systemPrompt:conversationHistory:userPrompt:maxOutputTokens:)` | Synchronous (non-streaming) vision analysis |
| `analyzeImageStreaming(images:systemPrompt:conversationHistory:userPrompt:onChunk:)` | SSE streaming response with per-chunk callback |
| `generateSteps(...)` | Thin wrapper over `analyzeImageStreaming` for step planning |

### Multi-Provider Profile System

`ProfileManager` manages named API profiles. Each profile stores:

```swift
struct LumaProfile {
    var id: UUID
    var name: String
    var provider: LumaAPIProvider      // .openRouter / .anthropic / .google / .custom
    var baseURL: String
    var selectedModel: String
    // API key stored separately in VaultManager
}
```

**Providers and their auth:**

| Provider | Base URL | Auth Header |
|---|---|---|
| OpenRouter | `https://openrouter.ai/api/v1` | `Authorization: Bearer {key}` |
| Anthropic | `https://api.anthropic.com/v1` | `x-api-key: {key}` (no Bearer prefix) |
| Google AI | `https://generativelanguage.googleapis.com/v1beta/openai` | `Authorization: Bearer {key}` |
| Custom | User-specified | `Authorization: Bearer {key}` |

**Default recommended model:** `google/gemini-2.5-flash:free` (free via OpenRouter)

### Model Picker

`OpenRouterModelFetcher` fetches the live model list from OpenRouter:
- Models are divided into **Free** and **Paid** sections
- Recommended models carry a badge (curated list in `OpenRouterModelFetcher`)
- Model list is cached locally after fetch
- Search within model picker is real-time (filters by model ID substring)

### Prompt Compression (LumaMLEngine)

Before any user message is sent to the API, `LumaMLEngine.compressPrompt()` strips filler words:

**Removed:** `um`, `uh`, `like`, `please`, `just`, `basically`, `hey`, `luma`, `can`, `could`, and compound fillers (`"can you"`, `"could you please"`, etc.)
**Preserved:** Action verbs, articles, all context words

Typical token reduction: **50–60%**

Multi-word fillers are matched first (longest match wins) to prevent partial-word stripping.

### Intent Classification (LumaTaskClassifier)

Before each user message is processed, `LumaTaskClassifier` classifies intent:

| Classification | Triggers | Routing |
|---|---|---|
| `singleStep` | Default; simple verbs without connectors | Voice response + optional single cursor point |
| `multiStep` | "how to", "steps to", "set up", "and then", "help me [task]" | `WalkthroughEngine` step planning |
| `question` | "what is", "why does", "explain", "tell me about" | Voice-only response (no pointing) |
| `unknown` | Fallback | Treated as `singleStep` |

Classification uses heuristic rules only — **zero API calls**. Sequential connectors like "and go to" or "then click" promote any classification to `multiStep` even if the primary verb is simple.

---

## 9. Walkthrough System

The walkthrough system guides the user through multi-step tasks. It is the primary differentiator of Luma vs. a simple AI chatbot.

### State Machine

`WalkthroughEngine` (singleton, `@MainActor`) owns these states:

```
idle → planning → confirming → executing(steps, currentIndex) → complete
```

| State | What's Happening |
|---|---|
| `idle` | No active walkthrough |
| `planning` | AI is generating steps (streaming JSON) |
| `confirming` | Plan displayed for user confirmation before execution begins |
| `executing` | Step-by-step execution loop active |
| `complete` | All steps done |

### Step Planning

`TaskPlanner` sends goal + frontmost app name to the AI with a strict JSON format requirement:

```json
{
  "totalSteps": 3,
  "steps": [
    {
      "index": 0,
      "instruction": "Right-click the Downloads folder in Finder.",
      "elementName": "Downloads",
      "elementRole": "AXFolder",
      "appBundleID": "com.apple.finder",
      "isMenuBar": false,
      "timeoutSeconds": 15
    }
  ]
}
```

Steps are parsed by `TaskPlanner` from the raw AI response. If JSON parsing fails, the engine retries once, then falls back to a plain voice response.

### Step Execution Loop

For each step:

1. **Speak instruction** — `NativeTTSClient` reads the step's `instruction` text aloud
2. **Point cursor** — `CursorGuide.pointAtElement(name:appBundleID:isMenuBar:)` → runs `LumaImageProcessingEngine.findElement()` → animates blue cursor to element
3. **Install AX observer** — `AccessibilityWatcher` installs on the target app; watches for `focusChanged`, `valueChanged`, `windowCreated`
4. **Install mouse monitor** — global left/right click monitor catches Dock clicks and sidebar interactions that don't fire AX focus events
5. **Wait for action** — two paths run concurrently:
   - **Fast path**: AX label of focused element matches expected element name (case-insensitive, fuzzy) → step immediately complete
   - **Slow path**: Debounced AI screenshot validation ("Is this step COMPLETED or INCOMPLETE?") → complete on positive answer
6. **Typing step detection** (if step instruction contains "type", "write", or "enter"):
   - Polls `AXValue` of target text field every **0.5 seconds**
   - Step completes when typed text matches expected text (case-insensitive)
   - Minimum elapsed time: **1 second** (ignores pre-filled values)
   - Timeout: `max(30, charCount × 1.5)` seconds
7. **Nudge on timeout** — if no action detected within `step.timeoutSeconds`, `NudgeEngine` speaks a gentle offline correction and re-points the cursor; nudge reschedules itself
8. **Periodic AI re-validation** — every 5 completed steps, Claude re-validates that the task is still on track

### Concurrency Safety

All async callbacks (AX observer C callbacks, timers, mouse events) carry a **generation integer** captured when created. `currentStepGeneration` is incremented every time a step ends. Any callback whose generation doesn't match the current one is silently dropped. This prevents stale events from a previous step from accidentally advancing or corrupting the current step.

### AX Dwell Time

An AX focus event must hold for **1 second** before the fast-path considers it valid. This prevents accidental advancement when the user brushes over elements while navigating.

### NudgeEngine

Offline nudge templates (no API calls, no latency):

- "That doesn't seem quite right. Let me re-point you."
- "Try clicking [element name] — I'll point to it again."
- "Almost there. Let me show you where to go."

After **3 nudges** on the same step, the engine escalates to Claude for a context-aware correction message.

### StepValidator

`StepValidator` provides a `validate(completedSteps:currentScreenshot:goal:)` method that sends a screenshot + completed steps to Claude and asks if the task is on track. Called every 5 steps.

---

## 10. Element Detection System (LIPE)

`LumaImageProcessingEngine` (LIPE) is the single authority for "find UI element X on screen." It runs two scans in parallel and cross-validates the results.

### Layer 1 — Accessibility Tree (AX Scan)

`scanAccessibilityTree(query:appBundleID:isMenuBar:)`:

1. Identifies the target app by `appBundleID` or falls back to frontmost app
2. Walks the AX tree recursively up to **depth 12**
3. Reads `kAXTitleAttribute`, `kAXDescriptionAttribute`, `kAXValueAttribute`, `kAXRoleAttribute`, `kAXFrameAttribute` for each element
4. Scores each element against the query (see scoring rules below)
5. If the query doesn't match the frontmost app, also scans the Dock (`com.apple.dock`) to find app icons
6. Returns the top 5 scored candidates as `ElementCandidate` structs

**Menu bar scan path** (when `isMenuBar = true`):
- Scans the frontmost app's menu bar
- Also scans `com.apple.controlcenter` and `com.apple.systemuiserver`

**Scoring Rules:**

| Match Type | Score |
|---|---|
| Exact label match | +100 |
| Label contains query | +50 |
| Query contains label (and label > 3 chars) | +30 |
| `AXMenuBarItem` role | +15 |
| `AXButton` or `AXMenuItem` | +10 |
| Element area > 200,000 px² (window/container) | −50 |
| Element area > 60,000 px² (group/scroll area) | −25 |
| `AXWindow`, `AXSheet`, `AXDrawer` | −40 |
| `AXGroup`, `AXScrollArea`, `AXList`, `AXTable` | −20 |
| `AXStaticText`, `AXImage` | −8 |
| `AXDockItem` vs `AXMenuBarItem` for same label | `AXMenuBarItem` −50 (Dock wins) |

**Live AX Frame Re-Read:**
When pointing (confidence ≥ 0.8, source is `.accessibility` or `.both`), LIPE re-reads `kAXFrameAttribute` from the live `AXUIElement` reference at point-time. This corrects elements that moved between scan-time and cursor animation time (e.g., sidebar items that render late).

### Layer 2 — Visual / Screenshot Scan

`scanVisual(query:)`:

1. Captures a screenshot via `CompanionScreenCaptureUtility` (ScreenCaptureKit)
2. Passes the image to `LumaOnDeviceAI.detectElements(in:screenSize:searchQuery:)`
3. Layers 1+2 run on-device (Vision text detection + MobileNetV2 crop validation)
4. Visual-only candidates are capped at confidence **0.4** (can't dominate over AX results)
5. If best on-device confidence < **0.5**, triggers Layer 3 (Claude Vision API fallback)

### Layer 3 — Claude Vision API Fallback

`detectElementViaAPIClient(screenshotData:screenCapture:searchQuery:)`:

1. Sends the screenshot to the active AI profile
2. System prompt: "Find the UI element, respond ONLY with `[POINT:x,y:label]`"
3. Parses `[POINT:x,y:label]` from response using regex
4. Scales pixel coordinates to Quartz screen coordinates
5. Estimates bounding box: 24×24 pt for ≤2-char queries; 60×30 pt otherwise
6. Returns `ElementCandidate` with confidence **0.55**
7. If AX cross-validation overlaps this box, the merged result inherits the real AX frame

### Cross Validation

When AX and visual candidates overlap by ≥ **60%** (measured as fraction of AX frame), they are merged:
- Merged source: `.both`
- Confidence: `min(axConfidence + 0.3, 1.0)` — 0.3 bonus for agreement
- Frame: AX frame used (more precise)

Candidates with confidence < **0.3** are discarded.

### Coordinate System

LIPE works in **Quartz coordinates** (top-left origin, Y increases downward) internally. Before notifying the overlay, `toScreenPoint()` converts to **AppKit coordinates** (bottom-left origin, Y increases upward):

```
appKitY = mainScreenHeight - axFrame.origin.y - (axFrame.height / 2)
```

---

## 11. On-Device ML Layer

`LumaOnDeviceAI` is a lightweight coordinator that lazy-loads all on-device models.

### LumaMobileNetDetector

Runs Layers 1+2 of visual detection:

**Layer 1 — Vision Framework:**
- `VNRecognizeTextRequest`: finds text labels in the screenshot
- `VNDetectRectanglesRequest`: finds rectangular UI elements
- Results include real bounding boxes in normalized coordinates
- Text matching is query-aware (filters results by relevance to `searchQuery`)

**Layer 2 — MobileNetV2 Crop Validation:**
- Crops a 160×160 pt region centered on each Layer 1 candidate's bounding box
- Runs the crop through bundled MobileNetV2 model
- If top-class confidence < **0.35**: downgrades the candidate's confidence score
- If MobileNetV2 model is not bundled: Layer 2 is skipped, Layer 1 results pass through unchanged

**Detection Result Structure:**
```swift
struct DetectionResult {
    let label: String
    let screenFrame: CGRect     // Quartz coordinates
    let confidence: Float
}
```

### LumaMLEngine

Prompt compression and coordinate validation utilities:

**Prompt Compression:**
- Strips filler words before every API call
- Multi-word phrases matched first (longest-match)
- Preserves action verbs, articles, and all contextually meaningful words
- 50–60% typical token reduction

**Coordinate Validation Gate:**
- `validateCoordinate(x:y:screenshot:completion:)`: crops 160×160 region at (x,y), runs MobileNetV2
- Passes if top-class confidence ≥ 0.35
- On rejection: `requestCoordinateRetry()` is called — logs the rejection and defers recovery to the WalkthroughEngine's nudge timer (no redundant API call from LIPE)

### LumaTaskClassifier

Zero-API intent routing:
- Pattern-matches against heuristic rule sets
- Returns: `.singleStep`, `.multiStep`, `.question`, `.unknown`
- Multi-step sequential connectors ("and go to", "then click") promote any classification to `.multiStep`
- Questions ("what is", "why does", "explain") route to voice-only response

### LumaWhisperEngine

On-device speech-to-text encoder (WhisperKit-based):
- **Status:** Encoder only — decoder not yet integrated
- Intended future path: fully on-device STT without AssemblyAI
- Currently unused in production transcription pipeline

---

## 12. Cursor Overlay System

### OverlayWindow

One `OverlayWindow` is created per connected display. Each window:

- **Window level:** `.screenSaver` — always on top, above all app windows, menus, and Spotlight
- **Background:** Fully transparent (`NSColor.clear`)
- **Mouse events:** Ignored — click-through; overlay never steals focus
- **Screen capture exclusion:** Excluded from Cmd+Shift+3/4 screenshots and ScreenCaptureKit captures
- **Multi-monitor safe:** Joins all Spaces, uses `fullScreenAuxiliary` collection behavior
- Content rendered via `NSHostingView` containing SwiftUI views

### Companion Cursor

The blue animated companion cursor. Configured via `LumaTheme`:

| Property | Default Value |
|---|---|
| Color | `#0A84FF` (blue) |
| Idle size | 14×14 pt |
| Pointing size | 32×32 pt |
| Idle shape | `.capsule` |
| Pointing shape | `.triangle` |

The cursor never represents the OS mouse cursor. It is purely decorative/instructional.

### Cursor Animation

`CursorGuide.pointAtElement()` dispatches a `NotificationCenter` notification with:
- `targetPoint`: `NSValue(point: CGPoint)` — destination in AppKit coordinates
- `bubbleText`: optional string shown in speech bubble when cursor arrives

The overlay animates along a **bezier arc** from current position to target. The arc provides natural motion (not a straight line).

### Transient Cursor Mode

When "Show Luma" is toggled off in the panel:
- Pressing the hotkey **fades in** the overlay for the duration of the interaction
- Sequence: recording → response → TTS → optional pointing
- Overlay **fades out automatically** after **1 second** of inactivity post-response

### CompanionResponseOverlay

Floating SwiftUI view rendered inside the overlay next to the cursor:
- **Response text bubble:** Streams AI response text in real time as chunks arrive
- **Waveform:** Animated audio level bars during recording (driven by `currentAudioPowerLevel` from `BuddyDictationManager`)
- **Spinner:** Shown during `processing` state

### CustomCursorManager

Configures a custom black teardrop cursor shape for the app's cursor (visible in the companion panel). Unrelated to the overlay cursor.

### CompanionBubbleWindow

A cursor-following tooltip window that appears next to the blue cursor when it lands on an element. Shows `bubbleText` from the step instruction.

---

## 13. Text-to-Speech

`NativeTTSClient` wraps `AVSpeechSynthesizer`. Fully local — no network calls.

### Voice Selection Priority

1. **Zoe Enhanced** (premium Siri voice, requires download in System Settings > Accessibility > Spoken Content)
2. **Zoe Compact** (base Zoe quality)
3. **Samantha Compact** (fallback)
4. **System default** (final fallback — any available voice)

### Speech Parameters

| Setting | Value | Effect |
|---|---|---|
| Rate | 0.52 | Slightly faster than default (0.5) |
| Pitch | 1.4 | Higher-pitched, friendlier delivery |
| Volume | 1.0 | Full volume |

### Coordinate Sanitization

Before speaking, `NativeTTSClient` strips coordinate tags that AI responses may embed. Patterns removed before reading aloud:

- `[POINT:x,y:label]`
- `(400, 200)` — raw coordinate pairs
- `{x:400,y:200}` — JSON-style coordinates

This prevents the TTS from literally saying "bracket POINT 400 comma 200".

### Async Interface

`speak(_ text: String) async` — resolves when speech finishes or is cancelled. Used by `WalkthroughEngine` to `await` each instruction before advancing.

---

## 14. Screen Capture

`CompanionScreenCaptureUtility` wraps ScreenCaptureKit for multi-monitor screenshot capture.

### Capture Flow

1. Creates a `SCShareableContent` request to enumerate all displays
2. For each display, configures an `SCStreamConfiguration` (JPEG output, full resolution)
3. Captures a single frame from each display
4. Returns an array of `CompanionScreenCapture` structs:

```swift
struct CompanionScreenCapture {
    let imageData: Data              // JPEG-encoded screenshot
    let displayWidthInPoints: Int    // Display logical width (pt)
    let displayHeightInPoints: Int   // Display logical height (pt)
    let screenshotWidthInPixels: Int // Pixel dimensions of the JPEG
    let screenshotHeightInPixels: Int
}
```

### Coordinate Scaling

When Layer 3 (Claude Vision) returns pixel coordinates from the screenshot:
```
quartzX = pixelX × (displayWidthInPoints / screenshotWidthInPixels)
quartzY = pixelY × (displayHeightInPoints / screenshotHeightInPixels)
```

This converts screenshot pixel space to display point space, accounting for Retina display scaling.

### Screenshot Exclusion

The overlay window itself is excluded from ScreenCaptureKit captures (`.excludedFromCapture = true`), so screenshots sent to Claude don't include the Luma overlay — only the user's actual screen content.

---

## 15. UI Components

### Menu Bar Panel

`MenuBarPanelManager` creates and manages:

- **Status item:** `NSStatusItem` with Luma lightbulb icon in the macOS menu bar
- **Panel type:** `KeyablePanel` — a custom `NSPanel` subclass that can become key window (needed to accept keyboard input in the model search field)
- **Panel behavior:** Borderless, dark, rounded corners, custom shadow; drops below the menu bar when the status icon is clicked
- **Click-outside dismiss:** Global `NSEvent` monitor auto-dismisses the panel on left/right mouse-down outside its bounds
- **Not in Windows menu:** Panel not listed in the app's Window menu
- **Screen capture excluded:** Panel excluded from ScreenCaptureKit and Cmd+Shift+3/4

### CompanionPanelView

The main dropdown panel. Contains:

| Section | Contents |
|---|---|
| Status | Voice state indicator (idle / listening / processing / responding) |
| Push-to-talk | Shortcut reminder (`ctrl+option`); large microphone button for mouse-driven PTT |
| Model picker | Searchable OpenRouter model browser (free/paid sections, recommended badges); syncs with `CompanionManager.selectedModel` |
| Permissions | Toggle rows for Microphone, Screen Recording, Accessibility — each opens System Settings to the correct pane |
| Luma cursor | Toggle for overlay cursor visibility |
| DM feedback | Opens a direct message link to report bugs |
| Quit | Quits the app |

### SettingsPanelView

Tabbed settings window (launched from the companion panel):

| Tab | Contents |
|---|---|
| Account | Username, display name, avatar initials; edit/save; logout |
| Profiles | List of API profiles; add/delete; set active; per-profile model selection |
| Model | Global model selection; shortcut to OpenRouter model browser |
| General | Startup behavior (login item toggle); PIN management; cursor shape; about |

### OnboardingWizardView

Full-screen wizard that replaces the panel on first launch. 5 steps (see Section 5).

### PINEntryView

Numeric keypad for PIN entry:
- 6-digit entry with visual dots
- Shake animation on incorrect PIN
- Haptic feedback on macOS (where supported)
- "Forgot PIN" escape hatch (prompts to delete vault and re-enter API key)

---

## 16. Design System

All UI references `LumaTheme` tokens.

### Color Palette

| Token | Hex | Usage |
|---|---|---|
| `background` | `#0A0A0A` | App/panel backgrounds |
| `surface` | `#141414` | Card surfaces |
| `surfaceElevated` | `#1C1C1C` | Elevated cards, popovers |
| `textPrimary` | `#FFFFFF` | Primary labels |
| `textSecondary` | `#B0B0B0` | Secondary labels, captions |
| `border` | `#3A3A3A` | Dividers, borders |
| `accent` | `#FFFFFF` | Accent highlights |
| `companionColor` | `#0A84FF` | Blue cursor / companion |

### Typography

Defined in `LumaTheme` as `Font` tokens. Follows macOS system font conventions with size adjustments per context.

### Corner Radii

Defined as `CGFloat` tokens in `LumaTheme.CornerRadius`:
- `small`, `medium`, `large`, `extraLarge`

### String Catalog

`LumaStrings` centralizes all user-facing strings. This is not a `.strings` file — it's a Swift enum with static properties. No localization in the current version.

---

## 17. Analytics

`LumaAnalytics` wraps the PostHog SDK.

### Configuration

- PostHog API key embedded in the app binary
- Events are sent to PostHog's cloud (no self-hosted option currently)
- Anonymized — no personally identifiable information in event properties

### Tracked Events

| Event | Properties | Trigger |
|---|---|---|
| `app_opened` | `version` | App launch |
| `push_to_talk_started` | — | Hotkey pressed |
| `push_to_talk_released` | — | Hotkey released |
| `user_message_sent` | `transcript`, `length` | Transcript submitted to AI |
| `ai_response_received` | — | First chunk received from AI |
| `element_pointed` | `elementName` | Cursor pointed at element |
| `walkthrough_started` | `goal` | WalkthroughEngine enters `.planning` |
| `walkthrough_step_completed` | `stepIndex`, `totalSteps` | Step advances |
| `walkthrough_completed` | `goal`, `totalSteps` | WalkthroughEngine reaches `.complete` |
| `onboarding_started` | — | Onboarding wizard opens |
| `onboarding_completed` | — | Onboarding wizard dismisses |
| `response_error` | `error` | API call fails |
| `tts_error` | `error` | TTS synthesis fails |

---

## 18. Auto-Update

Luma uses **Sparkle** for over-the-air updates.

### Configuration

| Setting | Value |
|---|---|
| Feed URL | `https://raw.githubusercontent.com/julianjear/makesomething-mac-app/main/appcast.xml` |
| Public ED key | `/l3d2rw5ZZFRU3AadP/w2Zf8FHfhA6bKv16BQOV5OSk=` |

Updates are checked on launch. Sparkle presents a standard update dialog when a newer version is available. Delta updates are supported if configured in the appcast.

---

## 19. Data Storage Map

| Data | Location | Sensitive | Persists Across Reboots |
|---|---|---|---|
| API keys | Keychain (vault item) | Yes | Yes (after first unlock) |
| PIN | Keychain (vault item) | Yes | Yes (after first unlock) |
| Profile metadata (names, providers, model IDs) | UserDefaults | No | Yes |
| Active profile ID | UserDefaults | No | Yes |
| User account (username, display name) | UserDefaults | No | Yes |
| Model selection | UserDefaults | No | Yes |
| Cursor visibility toggle | UserDefaults | No | Yes |
| Onboarding completion flag | UserDefaults | No | Yes |
| Tutorial completion flag | UserDefaults | No | Yes |
| Walkthrough state | In-memory only | — | No (resets on relaunch) |
| Conversation history | In-memory only | — | No (resets on relaunch) |
| Audio buffers | In-memory only | — | No |
| Screenshots | In-memory only | — | No (never written to disk) |

---

## 20. API Endpoints & Providers

### OpenRouter

- **Base URL:** `https://openrouter.ai/api/v1`
- **Chat Completions:** `POST /chat/completions`
- **Model List:** `GET /models`
- **Auth:** `Authorization: Bearer {key}`
- **Default Model:** `google/gemini-2.5-flash:free`

### Anthropic

- **Base URL:** `https://api.anthropic.com/v1`
- **Chat Completions:** `POST /messages` (OpenAI-compatible adapter used)
- **Auth:** `x-api-key: {key}`
- **Default Model:** `claude-sonnet-4-6`

### Google AI (Gemini)

- **Base URL:** `https://generativelanguage.googleapis.com/v1beta/openai`
- **Chat Completions:** `POST /chat/completions`
- **Auth:** `Authorization: Bearer {key}`
- **Default Model:** `gemini-2.5-flash`

### AssemblyAI (STT)

- **Token endpoint:** `https://streaming.assemblyai.com/v3/token`
- **WebSocket:** `wss://streaming.assemblyai.com/v3/ws`
- **Model:** `u3-rt-pro`
- **Audio format:** PCM16, mono, device native sample rate
- **Auth:** Keychain key `assemblyai_api_key` → short-lived temp token per session

---

## 21. Hardcoded Configuration Values

| Setting | Value | Location | Can Be Changed By User |
|---|---|---|---|
| Push-to-talk hotkey | `ctrl + option` | `BuddyDictationManager` | No (hardcoded) |
| API request queue gap | 15 seconds | `APIClient` | No |
| 429 retry wait | 60 seconds | `APIClient` | No |
| AI validation cooldown | 1.5 seconds minimum between calls | `WalkthroughEngine` | No |
| AX dwell time (fast path) | 1 second | `WalkthroughEngine` | No |
| Typing poll interval | 0.5 seconds | `WalkthroughEngine` | No |
| Typing minimum elapsed | 1 second | `WalkthroughEngine` | No |
| Typing timeout formula | `max(30, charCount × 1.5)` seconds | `WalkthroughEngine` | No |
| Nudge fire-after | Step's `timeoutSeconds` (from AI) | `WalkthroughEngine` | AI-determined per step |
| Nudge escalate-after | 3 nudges | `WalkthroughEngine` | No |
| Periodic AI re-validation | Every 5 completed steps | `WalkthroughEngine` | No |
| LIPE confidence threshold | 0.3 | `LumaImageProcessingEngine` | No |
| LIPE cross-validation overlap | 60% | `LumaImageProcessingEngine` | No |
| LIPE confidence boost (both sources) | +0.3 | `LumaImageProcessingEngine` | No |
| Visual confidence cap (visual-only) | 0.4 | `LumaImageProcessingEngine` | No |
| Layer 3 trigger threshold | 0.5 on-device confidence | `LumaImageProcessingEngine` | No |
| Layer 3 assigned confidence | 0.55 | `LumaImageProcessingEngine` | No |
| MobileNet crop size | 160×160 pt | `LumaMLEngine` | No |
| MobileNet pass threshold | 0.35 | `LumaMLEngine` | No |
| AX tree max depth | 12 | `LumaImageProcessingEngine` | No |
| Dock scan max depth | 4 | `LumaImageProcessingEngine` | No |
| Tutorial auto-advance | 4 seconds | `PostOnboardingTutorialManager` | No |
| TTS rate | 0.52 | `NativeTTSClient` | No |
| TTS pitch | 1.4 | `NativeTTSClient` | No |
| Companion color | `#0A84FF` | `LumaTheme` | No (theming not exposed) |
| Cursor idle size | 14×14 pt | `LumaTheme` | No |
| Cursor pointing size | 32×32 pt | `LumaTheme` | No |
| Keychain service name | `com.nox.luma` | `KeychainManager` | No |
| Keychain vault key | `com.nox.luma.vault` | `VaultManager` | No |
| Bundle ID | `com.nox.luma` | `Info.plist` | No |

---

## 22. Key Files Reference

| File | Lines (approx) | Purpose |
|---|---|---|
| `leanring_buddyApp.swift` | ~89 | App entry point; `@NSApplicationDelegateAdaptor` wires `CompanionAppDelegate` which creates `MenuBarPanelManager` and starts `CompanionManager` |
| `CompanionManager.swift` | ~1026 | Central voice state machine; owns dictation, shortcut monitoring, screen capture, API client, TTS, overlay; drives full PTT → screenshot → AI → TTS → pointing pipeline |
| `WalkthroughEngine.swift` | ~600+ | Walkthrough state machine; step planning, execution loop, AX observer, typing detection, nudge timer, AI validation |
| `MenuBarPanelManager.swift` | ~244 | `NSStatusItem` + custom `NSPanel`; menu bar icon, floating panel show/hide/position, click-outside dismiss |
| `CompanionPanelView.swift` | ~900 | SwiftUI panel content; status, PTT button, model picker, permissions, cursor toggle, quit |
| `OverlayWindow.swift` | ~881 | Full-screen transparent overlay; blue cursor, response text, waveform, spinner, bezier animation, multi-monitor coordinate mapping, fade transitions |
| `LumaImageProcessingEngine.swift` | ~743 | LIPE; AX scan + visual scan in parallel, cross-validation, Layer 3 Claude Vision fallback, coordinate conversion |
| `LumaMobileNetDetector.swift` | ~354 | Layer 1 (VNRecognizeTextRequest + VNDetectRectanglesRequest) + Layer 2 (MobileNetV2 crop validation) |
| `LumaOnDeviceAI.swift` | ~82 | On-device AI coordinator; lazy loads Whisper, DistilBERT, MobileNet; threads `searchQuery` through to detector |
| `LumaMLEngine.swift` | ~200+ | Prompt compression (filler word stripping) + coordinate MobileNet validation gate |
| `LumaTaskClassifier.swift` | ~150+ | Zero-API intent classification (single/multi-step/question) via heuristic rules |
| `BuddyDictationManager.swift` | ~866 | Push-to-talk pipeline; `AVAudioEngine`, provider-aware permission checks, transcript finalization, audio level reporting |
| `GlobalPushToTalkShortcutMonitor.swift` | ~132 | System-wide CGEvent tap for `ctrl+option`; publishes press/release transitions |
| `AssemblyAIStreamingTranscriptionProvider.swift` | ~478 | AssemblyAI v3 WebSocket streaming; temp token fetch, PCM16 streaming, turn-based transcript |
| `OpenAIAudioTranscriptionProvider.swift` | ~317 | Upload-based STT; buffers audio, uploads as WAV, returns finalized transcript |
| `AppleSpeechTranscriptionProvider.swift` | ~147 | Local Apple Speech fallback (`SFSpeechRecognizer`) |
| `BuddyAudioConversionSupport.swift` | ~108 | PCM buffer → PCM16 mono conversion; WAV file building |
| `BuddyTranscriptionProvider.swift` | ~100 | STT provider protocol + factory |
| `APIClient.swift` | ~300+ | AI API request router; request queue, 15s gap enforcement, 429 retry, profile-based routing, TLS warmup |
| `ProfileManager.swift` | ~200+ | Multi-provider API profile management; UserDefaults metadata + VaultManager keys |
| `TaskPlanner.swift` | ~200+ | Step generation via Claude; JSON parsing, retry logic |
| `NudgeEngine.swift` | ~100+ | Offline correction templates; spoken nudges with zero API calls |
| `CursorGuide.swift` | ~200+ | Cursor animation dispatcher; `NotificationCenter` bridge between LIPE and `OverlayWindow` |
| `AccessibilityWatcher.swift` | ~300+ | AX observer (focus, value, window, app activation events) + polling timer for frontmost app changes |
| `StepValidator.swift` | ~100+ | AI-powered step completion validation; screenshot + completed steps → Claude → COMPLETED/INCOMPLETE |
| `WalkthroughStep.swift` | ~50 | `WalkthroughStep` struct and `WalkthroughPlan` |
| `CompanionResponseOverlay.swift` | ~217 | SwiftUI view for response text bubble + waveform |
| `CompanionBubbleWindow.swift` | ~150+ | Cursor-following speech bubble tooltip |
| `CompanionScreenCaptureUtility.swift` | ~132 | Multi-monitor screenshot via ScreenCaptureKit; returns JPEG per display |
| `NativeTTSClient.swift` | ~150+ | `AVSpeechSynthesizer` wrapper; voice selection, coordinate sanitization, async interface |
| `ElevenLabsTTSClient.swift` | ~90 | Legacy TTS client (replaced by `NativeTTSClient`); retained for reference |
| `KeychainManager.swift` | ~100+ | macOS Keychain read/write wrapper |
| `VaultManager.swift` | ~150+ | Single-item vault (PIN + all API keys) stored in Keychain |
| `AccountManager.swift` | ~107 | Local user account (username, display name) via UserDefaults; `LumaAvatarView` for initials display |
| `ProfileManager.swift` | ~200+ | Named API profiles; active profile tracking |
| `PINManager.swift` | ~80+ | PIN check/set/clear; delegates storage to VaultManager |
| `PINEntryView.swift` | ~150+ | Numeric PIN keypad; shake animation, haptics |
| `OnboardingWizardView.swift` | ~500+ | 5-step first-launch wizard |
| `SettingsPanelView.swift` | ~600+ | Tabbed settings (Account, Profiles, Model, General) |
| `PostOnboardingTutorialManager.swift` | ~80 | 5-step post-onboarding tutorial; pulse rings, auto-advance, UserDefaults completion flag |
| `FeedbackEngine.swift` | ~100+ | In-app feedback; DM link dispatch |
| `OfflineGuideManager.swift` | ~100+ | Offline walkthrough content fallback (bundled guides for common tasks) |
| `OpenRouterModelFetcher.swift` | ~150 | OpenRouter model list fetch, parse, cache; recommended badge mapping |
| `LumaTheme.swift` | ~400+ | Design tokens (colors, spacing, typography, cursor config) |
| `LumaStrings.swift` | ~100+ | User-facing string constants |
| `LumaAnalytics.swift` | ~121 | PostHog analytics wrapper |
| `LumaWriteEngine.swift` | ~100+ | Typing automation helper |
| `ElementLocationDetector.swift` | ~335 | Legacy element location detection (Claude Computer Use style); wraps AI screenshot pointing for one-shot use from CompanionManager |
| `CustomCursorManager.swift` | ~80+ | Teardrop cursor styling for the companion panel |
| `DesignSystem.swift` (legacy) | ~880 | Legacy design tokens; being superseded by `LumaTheme` |
| `WindowPositionManager.swift` | ~262 | Window placement logic; Screen Recording permission flow; accessibility permission helpers |
| `AppBundleConfiguration.swift` | ~28 | Runtime reader for keys in Info.plist |
| `ClaudeAPI.swift` | ~291 | Claude vision API client (legacy; direct Anthropic endpoint); SSE streaming, TLS warmup, MIME detection |
| `OpenAIAPI.swift` | ~142 | Legacy OpenAI GPT vision client |
| `LumaWhisperEngine.swift` | ~100+ | On-device Whisper STT encoder (encoder-only, decoder pending) |

---

## 23. Known Limitations

| Limitation | Impact | Notes |
|---|---|---|
| **WhisperKit decoder not integrated** | No fully on-device STT | Encoder loads but full transcription requires AssemblyAI/OpenAI/Apple Speech |
| **Push-to-talk shortcut hardcoded** | Cannot be rebound by user | `ctrl+option` is not user-configurable |
| **No brute-force PIN lockout** | PIN can be guessed by automated entry | Not a concern for typical use; PIN is local-only protection |
| **Single active API request** | One user message at a time; concurrent requests queue | By design (rate limit compliance); queue enforces 15s minimum gap |
| **Typing step detection polls AXValue** | 0.5s polling adds up to half-second detection lag | Fast enough in practice; event-based AX would be more elegant |
| **Multi-monitor Y-axis mapping** | Uses primary screen height for Y-flip formula | Correct for standard desktop layouts; edge cases in non-standard multi-monitor arrangements |
| **Conversation history in-memory only** | History resets on app relaunch | No persistent chat log |
| **No sandbox** | App has full system access | Required for global hotkey, AX API, ScreenCaptureKit |
| **App Store ineligible** | App uses entitlements not allowed on MAS | Distributed outside the Mac App Store only |
| **Layer 3 bounding box estimated** | Claude returns a point, not a box; LIPE estimates box size | Mitigated by AX cross-validation providing real frame when available |
| **No dark/light mode switching** | App is always dark | LumaTheme has fixed dark values |
| **Sparkle update feed is public GitHub URL** | Update feed URL is visible in binary | Standard pattern; not a security concern for update integrity (ED key validates signature) |
