# Luma V3 Behavior + UI Reconciliation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring `luma` to reliable PRD parity, then align UI behavior and polish with `openclicky` patterns without regressing guide mode.

**Architecture:** Use a behavior-first sequence: fix agent lifecycle and execution correctness first, then update visual surfaces. Reuse existing module boundaries (`CompanionManager`, `Agent/*`, overlays/panels), adding only minimal helper functions and migration logic where needed.

**Tech Stack:** Swift 5.9, SwiftUI + AppKit, UserDefaults/Keychain persistence, macOS notifications, existing Luma managers.

---

### Task 1: Gap Audit + Scope Lock

**Files:**
- Modify: `LUMA_V3_PRD.md`
- Create: `docs/superpowers/plans/2026-04-25-luma-v3-behavior-ui-reconciliation.md` (this file)
- Compare against: `/Users/nox/Desktop/openclicky/leanring-buddy/*.swift`

- [ ] **Step 1: Build requirement matrix**
- [ ] **Step 2: Mark each PRD item as done/partial/broken with code references**
- [ ] **Step 3: Lock fix order by severity (behavioral correctness first)**

### Task 2: Agent Task Execution Correctness

**Files:**
- Modify: `leanring-buddy/Agent/LumaAgentEngine.swift`
- Modify: `leanring-buddy/Agent/AgentStackView.swift`
- Modify: `leanring-buddy/Agent/AgentManager.swift`

- [ ] **Step 1: Route text submit and voice submit into `LumaAgentEngine.executeTask`**
- [ ] **Step 2: Replace simulated task completion with real action-loop execution + robust error cleanup**
- [ ] **Step 3: Enforce deterministic state transitions (`idle -> processing -> complete/failed`)**
- [ ] **Step 4: Ensure memory write + notification fire exactly once per completed task**
- [ ] **Step 5: Validate cursor lock acquire/release and conflict retry behavior**

### Task 3: Physics + Interaction Reliability

**Files:**
- Modify: `leanring-buddy/Agent/AgentBubblePhysics.swift`
- Modify: `leanring-buddy/Agent/AgentStackView.swift`

- [ ] **Step 1: Replace timer-based loop with display-link-backed 60fps update**
- [ ] **Step 2: Keep drag momentum decay and overlap repulsion stable under multiple agents**
- [ ] **Step 3: Wire processing impulse and neighbor wobble to visible bubble motion**
- [ ] **Step 4: Ensure no runaway updates when no agents are active**

### Task 4: Persistence and Migration Safety

**Files:**
- Modify: `leanring-buddy/Agent/AgentProfile.swift`
- Modify: `leanring-buddy/Agent/AgentSettingsManager.swift`
- Modify: `leanring-buddy/Agent/AgentManager.swift`

- [ ] **Step 1: Add compatibility decode paths for old profile/settings formats**
- [ ] **Step 2: Normalize persisted values to current schema on successful load**
- [ ] **Step 3: Keep safe defaults for corrupt/missing data**

### Task 5: UI Alignment with OpenClicky Patterns

**Files:**
- Modify: `leanring-buddy/CompanionPanelView.swift`
- Modify: `leanring-buddy/CompanionBubbleWindow.swift`
- Modify: `leanring-buddy/CompanionResponseOverlay.swift`
- Modify: `leanring-buddy/Agent/AgentStackView.swift`
- Modify: `leanring-buddy/Agent/AgentShapeView.swift`

- [ ] **Step 1: Align spacing/visual hierarchy and control states with reference implementation**
- [ ] **Step 2: Keep all existing Luma feature controls intact while restyling**
- [ ] **Step 3: Verify expanded/minimized bubble transitions and section reveal timing**

### Task 6: Verification + PRD Finalization

**Files:**
- Modify: `LUMA_V3_PRD.md`
- Inspect: edited Swift files from Tasks 2-5

- [ ] **Step 1: Run `ReadLints` on all touched files and fix introduced diagnostics**
- [ ] **Step 2: Run static acceptance checklist against PRD items**
- [ ] **Step 3: Update PRD progress checkboxes and add concise validation notes**
- [ ] **Step 4: Provide manual test checklist for Xcode run (no terminal `xcodebuild`)**
