<div align="center">

<img src="assets/luma-icon.png" alt="Luma" width="96" />

# Luma

**Light by Darkness**

A native macOS AI teaching assistant that lives beside your cursor. Watches your screen, guides you step by step, and teaches you anything — right where you work.

![macOS](https://img.shields.io/badge/macOS-14.0%2B-black?style=flat-square)
![Swift](https://img.shields.io/badge/Swift-5.9-black?style=flat-square)
![License](https://img.shields.io/badge/License-Proprietary-black?style=flat-square)
![Status](https://img.shields.io/badge/Status-In%20Development-orange?style=flat-square)

<img src="assets/luma-demo.png" alt="Luma Demo" width="720" />

</div>

---

## What is Luma?

Luma is a native macOS AI companion built for learners, developers, creatives, and everyone in between. It sits in your menu bar, follows your cursor with a floating companion bubble, and uses the macOS Accessibility API to watch what's happening on your screen in real time.

Tell Luma what you want to do. It breaks the task into steps, points at exactly what to click, watches for your actions, validates each one, and corrects you if you go off track — until the task is complete. Like having a senior developer or designer sitting right next to you, except it's always there, it never judges you, and it works with your own API keys so your data stays yours.

---

## Features

- **Interactive Walkthroughs** — Press `Ctrl + Option`, state your goal, and Luma generates a step-by-step guided walkthrough using Claude AI. It watches your screen via the Accessibility API, validates each action, corrects wrong moves, and nudges you if you go idle — all with minimal API usage.
- **Hybrid On-Device + Cloud AI** — MobileNetV2 (Core ML) handles visual element detection on-device. Nudges and corrections run fully offline via NudgeEngine. Claude is only called when genuine reasoning is required, keeping costs low.
- **Smart Element Detection** — Triple-validation architecture: Accessibility API scan + MobileNetV2 visual detection + Claude coordinate verification. Luma always knows exactly where to point.
- **Custom Cursor** — A minimal black teardrop cursor replaces your system cursor while Luma is active — a subtle signal that your AI teacher is watching and ready.
- **Companion Bubble** — A floating translucent black bubble follows your cursor across the entire screen, showing Luma's responses and instructions right where you're working.
- **Bring Your Own Keys** — Connect directly to OpenRouter, Anthropic, Google AI, or any custom OpenAI-compatible endpoint. No Luma servers involved in your conversations.
- **Multi-Profile System** — Create multiple API profiles for different providers or use cases. Set a default, switch instantly, manage everything from settings.
- **Smart Model Switcher** — Browse all OpenRouter models divided into Free and Paid, searchable, with recommended badges for the best picks. Persists per profile.
- **PIN Security** — Protect your settings with a 6-digit PIN stored in macOS Keychain. Never interrupts your workflow.
- **Voice Input** — Speak to Luma via Apple Speech (SFSpeechRecognizer). Fully on-device, no third-party transcription service required.
- **Native TTS** — Luma speaks back using macOS AVSpeechSynthesizer. No ElevenLabs, no credits, no limits.
- **Request Override** — Start a new request at any time and Luma immediately cancels the current walkthrough and responds to you.
- **Privacy First** — All keys in Keychain, zero analytics, zero telemetry. Your conversations never touch Luma's infrastructure.

---

## Getting Started

**Requirements:** macOS 14.0+, Apple Silicon or Intel, Xcode 15+ (if building from source), an API key from any supported provider.

```bash
git clone https://github.com/Omoju-Mayowa/luma.git
cd luma
open Luma.xcodeproj
```

Hit `⌘R` to build and run. Complete the onboarding wizard — enter your username, set an optional PIN, add your API key — and you're ready. No Cloudflare worker, no deployment, no terminal commands.

---

## Walkthrough Engine

```
Ctrl + Option → "Open Notes and create a new note and type hello world"

Luma plans steps → shows plan → walkthrough begins

Each step:
  LumaMLEngine compresses voice transcript (offline)
  LumaTaskClassifier routes request (offline)
  Claude plans steps + coordinates (one API call)
  MobileNetV2 validates target coordinate (offline)
  CursorGuide points at verified element
  AccessibilityWatcher monitors UI state

  ✓ Correct action → confirm + advance
  ✗ Wrong action   → NudgeEngine corrects offline (no API call)
  ⏱ No action 30s  → gentle nudge (×3 then "take your time")
  🔁 Stuck 3x      → escalate to Claude once

Typing steps:
  Poller waits 1.5s → captures focused element → polls AXValue
  Advances only when typed text matches expected text

All steps done → "You did it!" → idle
```

---

## Supported Providers

| Provider | Free Tier | Recommended Model |
|---|---|---|
| OpenRouter | ✅ Yes | `google/gemini-2.5-flash:free` |
| Anthropic | ❌ No | `claude-sonnet-4-6` |
| Google AI | ✅ Yes | `gemini-2.5-flash` |
| Custom | Depends | Any OpenAI-compatible endpoint |

---

## Architecture

```
Luma/
├── Core/
│   ├── APIClient.swift                    # Unified API routing + request queue
│   ├── ProfileManager.swift               # Multi-profile management
│   ├── AccountManager.swift               # Local account (username)
│   ├── KeychainManager.swift              # macOS Keychain wrapper
│   └── PINManager.swift                   # PIN security
│
├── ML/
│   ├── LumaMLEngine.swift                 # MobileNetV2 (Core ML) + prompt compression
│   ├── LumaMobileNetDetector.swift        # Visual UI element detection
│   ├── LumaTaskClassifier.swift           # Single vs multi-step classification
│   └── LumaOnDeviceAI.swift              # On-device AI coordinator
│
├── Walkthrough/
│   ├── WalkthroughEngine.swift            # Central state machine
│   ├── TaskPlanner.swift                  # Claude step generation
│   ├── NudgeEngine.swift                  # Offline corrections (zero API calls)
│   ├── AccessibilityWatcher.swift         # AX API monitor
│   ├── LumaImageProcessingEngine.swift    # AX + MobileNet element finder
│   ├── CursorGuide.swift                  # Element pointer
│   └── StepValidator.swift               # Action validation
│
├── UI/
│   ├── CompanionPanelView.swift           # Main panel
│   ├── CompanionBubbleWindow.swift        # Cursor-following bubble
│   ├── OnboardingWizardView.swift         # First launch wizard
│   ├── SettingsPanelView.swift            # Settings (PIN gated)
│   └── PINEntryView.swift                # PIN entry keypad
│
├── Overlay/
│   ├── OverlayWindow.swift               # Full-screen overlay
│   └── CustomCursorManager.swift         # Custom cursor
│
├── TTS/
│   └── NativeTTSClient.swift             # AVSpeechSynthesizer
│
└── Theme/
    ├── LumaTheme.swift                    # Design tokens
    └── LumaStrings.swift                 # String constants
```

---

## Roadmap

**v1.0 — Local**
- [x] Custom cursor + companion bubble
- [x] Multi-profile API config
- [x] Model switcher
- [x] PIN-secured settings
- [x] Onboarding wizard
- [x] Native TTS
- [x] Voice input via Apple Speech
- [x] Walkthrough engine with step validation
- [x] Accessibility API integration
- [x] On-device ML (MobileNetV2 + prompt compression)
- [x] Offline nudge system (NudgeEngine)
- [x] Request queue + rate limit handling
- [x] Request override (new request cancels active walkthrough)

**v2.0 — Accounts**
- [ ] Go backend (JWT auth, argon2id)
- [ ] Cross-device profile sync
- [ ] Plan-based profile limits

**v3.0 — SaaS**
- [ ] Stripe billing
- [ ] Free + Pro tiers
- [ ] Public release

---

## Privacy

API keys live exclusively in macOS Keychain with `kSecAttrAccessibleAfterFirstUnlock` — no repeated prompts, no plaintext storage. Conversations go directly from your Mac to your chosen provider — Luma has no servers that touch your messages. Voice transcription runs fully on-device via Apple Speech. Screen access via Accessibility API is only requested when you start a walkthrough. No analytics. No telemetry. No exceptions.

---

## Developer

**Omoju Oluwamayowa** (Nox) — Full-stack developer & UI/UX designer, Lagos, Nigeria.

---

## License

Copyright © 2026 Omoju Oluwamayowa (Nox). All rights reserved. This software is proprietary. You may not distribute, sublicense, or use it commercially without explicit written permission from the author.

---

<div align="center">
  <sub>Built by Nox · Lagos, Nigeria · 2026</sub>
</div>
