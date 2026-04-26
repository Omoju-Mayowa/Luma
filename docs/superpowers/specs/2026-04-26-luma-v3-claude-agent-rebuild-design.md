# Luma v3 Claude Agent Rebuild Design

## Summary

Rebuild Luma into a cleaner, more professional menu bar companion that takes visual inspiration from OpenClicky without copying it literally. The rebuilt product keeps Luma's defining interaction model: multiple visible on-screen agents that can work in parallel and act autonomously for the user. The companion shell, overlay, settings, and agent surfaces should all feel cohesive, restrained, and operationally clear.

The rebuild should preserve the reliable subsystems that already matter, including push-to-talk capture, screenshot capture, keychain-based secret storage, and parts of the existing overlay and window plumbing. The current agent architecture, most of the visible UI shell, and the current multi-agent presentation should be rebuilt around a new Claude-first runtime and a new design system.

## Goals

- Create a polished Luma-specific visual system inspired by OpenClicky's restraint, density, and professional feel.
- Rebuild the primary app surfaces so the menu panel, overlay, settings, and agent views feel like one product.
- Replace the current agent orchestration with a Claude Opus-based runtime that uses the user's existing Anthropic API key.
- Preserve Luma's visible multi-agent method as the center of Agent Mode rather than replacing it with a standard dashboard-only workflow.
- Support fully autonomous agent behavior by default, with strong interruption controls and runtime guardrails.

## Non-Goals

- Do not make Luma a literal OpenClicky clone.
- Do not replace Luma's core voice and screenshot capture capabilities unless required for compatibility.
- Do not redesign the product around Codex or a local runtime.
- Do not flatten Agent Mode into a single-pane dashboard that removes the on-screen multi-agent presence.
- Do not broaden scope into unrelated refactors or warning cleanups.

## Product Direction

Luma should feel like a premium operator tool instead of a playful experiment. The interface should be dark, crisp, compact, and deliberate. It should borrow OpenClicky's discipline in spacing, hierarchy, and state presentation while still reading as Luma.

The rebuilt product has two equal pillars:

- `Companion`: short, screen-aware, push-to-talk assistance with voice, text, pointer guidance, and contextual response rendering.
- `Agent Mode`: visible autonomous agents that can plan, act, coordinate, and complete work on the user's behalf using Claude Opus.

These pillars should share infrastructure and visual language, but each should have a clear job. Companion mode answers quickly. Agent Mode executes deeply.

## Architecture

### 1. LumaDesignSystem

Create a design system layer that becomes the single source of truth for tokens and common interaction patterns. It should cover:

- colors
- materials and surface hierarchy
- spacing
- corner radii
- typography
- border treatments
- hover, focus, pressed, and selected states
- button styles
- chips, cards, and inline status treatments
- cursor and tooltip affordances

This layer replaces the current fragmented theme usage with a consistent professional language.

### 2. CompanionShell

This layer owns the app surfaces and presentation flow:

- menu bar status item
- floating panel
- settings window
- overlay presentation
- expanded and minimized agent presentation

This shell renders state and routes intent, but does not own agent reasoning or orchestration logic.

### 3. ClaudeCompanionRuntime

This layer owns the fast-turn interaction loop for Companion mode:

- push-to-talk capture
- transcription pipeline
- screenshot capture
- Claude streaming response
- TTS
- pointer guidance and point-tag handling

This is the best candidate for selective reuse because Luma already has strong building blocks here.

### 4. ClaudeAgentRuntime

This is the main new subsystem. It replaces the current agent orchestration with a runtime built specifically for autonomous Claude Opus sessions backed by the user's Anthropic API key.

Responsibilities:

- create and manage agent sessions
- maintain per-agent conversation state
- build prompts and tool context
- decide next action
- drive action execution loops
- track pause, resume, stop, blocked, and completion states
- persist per-agent memory and execution summaries
- coordinate refreshes of screen and accessibility context during execution

This runtime should be Claude-only for Agent Mode and should always target Claude Opus.

### 5. ExecutionServices

Shared services used by both Companion mode and Agent Mode:

- screen capture service
- accessibility inspection service
- pointer and keyboard executor
- app launching and focusing
- memory persistence
- logging
- permission state service

This layer should make it possible for agents to stay autonomous without duplicating low-level device control logic across the app.

## Reuse and Replacement Boundaries

### Keep and adapt

- keychain storage
- push-to-talk and audio capture foundations
- screenshot capture foundations
- parts of overlay window and panel positioning infrastructure
- permission helpers
- logging and analytics hooks where still relevant

### Rework heavily

- menu panel UI
- settings UI
- overlay response card UI
- agent visual presentation
- state modeling for visible UI
- agent hotkey ergonomics
- memory presentation to the user

### Replace outright

- current multi-agent orchestration internals
- current agent-mode visual language
- Codex-shaped assumptions in planning or runtime behavior
- any dashboard or panel structure that fights the preserved on-screen agent model

## User Experience Surfaces

### Menu Bar Panel

The menu panel should become a calm control center instead of a crowded utility stack. It should make the current state obvious within a glance:

- whether Luma is idle, listening, responding, or running agents
- how to trigger Companion mode
- how to enter Agent Mode
- whether permissions or keys need attention
- what the most recent response or active task is

The panel should be dense enough to feel capable but never visually noisy.

### Overlay

The overlay should behave like a live execution HUD. In Companion mode, it should render concise screen-aware responses and pointer guidance. In Agent Mode, it should show only the most operationally useful information:

- what an agent is doing now
- whether the agent is acting, waiting, or blocked
- how to interrupt immediately
- where attention is being directed

The overlay should feel lightweight and should get out of the way when the user does not need it.

### Settings

Settings should feel compact, serious, and operational. It should focus on:

- Anthropic API configuration
- voice and transcription behavior
- TTS behavior
- cursor and overlay preferences
- permission state
- memory controls
- autonomy defaults and safety policy

The user should be able to audit their system state quickly.

## Agent Mode Experience

Agent Mode should preserve Luma's defining method: multiple visible on-screen agents remain the primary interaction model. The rebuild should not replace this with a plain dashboard-only experience.

Each agent is a distinct visible entity with:

- its own task
- its own Claude Opus session
- its own execution state
- its own memory context
- its own completion summary

The visible agent metaphor should remain, but it should mature. Agents should feel precise, premium, and readable rather than whimsical. Motion should communicate state and focus, not novelty.

### Agent presentation

Minimized agents should remain visible on screen and easy to distinguish. Expanded agent views should feel like compact command consoles that explain:

- current task
- current state
- last meaningful action
- latest reasoning summary
- whether the agent is waiting on execution control
- whether the agent is blocked or done

### Parallelism and coordination

Agents should reason in parallel, but only one agent should own keyboard and pointer control at a time. A shared execution coordinator must serialize device actions so agents do not fight each other.

While waiting for execution ownership, agents should still be able to:

- process updated context
- refine plans
- prepare next actions
- summarize current understanding

### Autonomy model

Autonomy should default to full continuation until task completion unless interrupted by the user. This means an agent can continue acting without repeated confirmation prompts. The user should be able to:

- stop one agent
- pause one agent
- stop all agents
- bring an agent into focus
- interrupt device control immediately

### Safety model

The runtime should not ask for confirmation at every step. Instead, it should rely on focused guardrails. The agent should enter a hesitation or confirmation state when it encounters:

- destructive actions
- credential entry
- ambiguous or low-confidence UI targets
- unexpected permission interruptions

When that happens, the agent should explain what it is trying to do and what it needs from the user.

## Runtime and Data Behavior

### Agent session model

Each agent session should track:

- stable agent identifier
- user-facing title
- assigned task
- current state
- current execution lock ownership status
- conversation history
- short-term working memory
- completion summary
- timestamps for creation, last action, and completion

### Memory model

Memory should be split into three layers:

1. global Luma memory for preferences and recurring context
2. per-agent session memory for active execution history
3. persisted summaries for completed agent runs

This structure supports both short active work and long-term continuity without overloading the live UI.

### Claude configuration

Companion mode can continue to support the current conversational model configuration if needed, but Agent Mode should be hard-bound to Claude Opus using the user's configured Anthropic API key. The runtime should fail clearly when the key is missing or invalid.

## Visual Direction

The rebuilt UI should be inspired by OpenClicky's restraint, not copied literally. Principles:

- dark surfaces with clear hierarchy
- tight and consistent spacing
- restrained accent usage
- concise operational copy
- obvious hover and focus affordances
- premium-feeling but minimal motion
- strong readability in compact areas

The on-screen agents should feel like part of that same system. They can still be expressive, but expression should come from state clarity and motion discipline rather than decorative excess.

## Verification Strategy

Do not use `xcodebuild` from the terminal.

Verification should include:

- `swiftc -parse` checks for touched Swift files where practical
- focused tests for extracted runtime logic and state transitions
- manual Xcode build verification using the existing project workflow
- manual checks for panel behavior, overlay behavior, and visible multi-agent behavior

Manual verification should explicitly cover:

- menu panel presentation and resizing
- push-to-talk flow
- screenshot-backed companion responses
- agent spawning
- agent focus switching
- autonomous task continuation
- execution lock arbitration
- interruption behavior
- hesitation state behavior for risky actions

## Implementation Shape

The rebuild should proceed in layers so behavior and presentation stay aligned:

1. establish the new design system and shared surface primitives
2. rebuild the panel, overlay, and settings shell around the new visual system
3. introduce the new ClaudeAgentRuntime and execution coordinator
4. rebuild visible agent presentation around the preserved multi-agent method
5. reconnect Companion mode and Agent Mode through shared services
6. verify runtime behavior, interruption behavior, and UI parity with the design goals

This order is important because the shell and agent system are being designed together, not sequentially bolted together.

## Open Decisions Resolved

- OpenClicky is inspiration, not a strict pixel-for-pixel clone.
- Agent Mode uses the user's Anthropic API key, not a local runtime.
- Agent Mode is Claude Opus only.
- The rebuild should preserve visible on-screen multi-agent interaction as Luma's core method.
- Autonomy defaults to fully autonomous execution until interrupted.
- The shell and Agent Mode should be rebuilt together rather than in separate phases.
