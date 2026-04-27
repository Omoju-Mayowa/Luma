# Luma v3.0 OpenClicky Rebuild — Design Spec

## Overview

Surgical update to Luma v3 PRD and implementation to match OpenClicky exactly. Replaces the Codex-built "Claude Agent Runtime" abstraction with a dual-runtime agent system (Claude Code CLI + Claude API fallback) that mirrors OpenClicky's subprocess-based agent architecture.

## What Changed From Previous Spec

### Removed: Codex Agent Abstractions
The Codex worktree introduced abstractions not present in OpenClicky:
- `ClaudeAgentExecutionState` enum (idle, planning, waitingForExecutionLock, acting, hesitating, paused, completed, failed)
- `AgentHesitationReason` enum (destructiveAction, credentialEntry, ambiguousTarget)
- `AgentExecutionCoordinator` actor (stubbed, always returns false)
- `ClaudeAgentRuntime` class with safety policy hooks
- `AgentSessionMemoryStore` (separate from main memory manager)

OpenClicky has none of this. Its agent lifecycle is simple: stopped → starting → ready → running → stopped/failed.

### Added: Dual-Runtime Agent Architecture

**Runtime detection on app launch:**
1. Check for `claude` CLI on PATH and common install locations
2. If found → `ClaudeCodeAgentRuntime` (default)
3. If not found → `ClaudeAPIAgentRuntime` (fallback)
4. User can override in Settings → Agent Mode

**ClaudeCodeAgentRuntime:**
- Spawns `claude` CLI as Foundation `Process()` subprocess
- Streams JSON output for transcript entries
- One process per agent session
- SIGTERM/SIGKILL lifecycle management
- Mirrors OpenClicky's Codex subprocess pattern exactly

**ClaudeAPIAgentRuntime:**
- Uses existing ClaudeAPI.swift with tool-use definitions
- Tools: screenshot, click, type, key_press, open_app, wait, bash
- Iterative tool-use loop (send → tool_use → execute → tool_result → repeat)
- Queue-based cursor lock for multi-agent conflict resolution
- Max 50 iterations per prompt safety limit

**Shared protocol:** `AgentRuntime` with startSession, submitPrompt, stopSession, transcriptPublisher, statusPublisher

### Preserved: Everything Else
The following sections of the PRD are unchanged and already match OpenClicky:
- Phase 1: Design System (completed by Codex)
- Phase 2: Panel & Window specs
- Phase 3: Overlay & Cursor specs
- Phase 4: Agent Session model, Panel Section, HUD, Response Cards, Dock
- Phase 5.1: Session lifecycle
- Phase 5.3: Title generation
- Phase 6: Memory & Persistence
- Phase 7: Voice & Input
- Phase 8.1: Log Window
- Phase 8.3: Final Integration

### Updated: Migration/Cleanup (Phase 8.2)
Added to removal list:
- `AgentExecutionModels.swift`, `ClaudeAgentRuntime.swift`, `AgentSessionMemoryStore.swift`
- Associated test files

Added to fix list:
- `SettingsPanelView.swift` syntax errors (malformed .font declarations from Codex code-gen)
- Remove `ClaudeAgentRuntimeAPI` and `ClaudeAgentRequest` from `ClaudeAPI.swift`

## Progress Summary

| Phase | Status | Notes |
|-------|--------|-------|
| 1. Design System | Done | 1,462 lines, all tokens + 7 button styles |
| 2.1 Menu Bar Panel | Partial | Modified, needs verification |
| 2.2 Companion Panel | Partial | DS tokens partially applied |
| 2.3 Settings Window | Partial | Sidebar layout done, has syntax errors |
| 3. Overlay & Cursor | Not started | — |
| 4. Agent System (UI) | Not started | — |
| 5.1 Session Lifecycle | Not started | — |
| 5.2 Agent Runtime | Not started | New dual-runtime architecture |
| 5.3 Title Generation | Not started | — |
| 6. Memory | Not started | Existing LumaMemoryManager usable |
| 7. Voice & Input | Not started | Existing pipeline usable |
| 8. Polish | Not started | Cleanup of Codex artifacts needed first |

## Files to Create
- `leanring-buddy/Agent/AgentRuntime.swift` — protocol + AgentRuntimeManager singleton
- `leanring-buddy/Agent/ClaudeCodeAgentRuntime.swift` — CLI subprocess runtime
- `leanring-buddy/Agent/ClaudeAPIAgentRuntime.swift` — API tool-use runtime
- `leanring-buddy/Agent/AgentSession.swift` — session model (from PRD 4.1)
- `leanring-buddy/Agent/AgentModePanelSection.swift` — inline panel controls (from PRD 4.2)
- `leanring-buddy/Agent/LumaAgentHUDWindowManager.swift` — dashboard window (from PRD 4.3)
- `leanring-buddy/Agent/ResponseCard.swift` — response card model + view (from PRD 4.4)
- `leanring-buddy/Agent/LumaAgentDockWindowManager.swift` — floating dock (from PRD 4.5)

## Files to Remove
- `leanring-buddy/Agent/AgentExecutionModels.swift`
- `leanring-buddy/Agent/ClaudeAgentRuntime.swift`
- `leanring-buddy/Agent/AgentSessionMemoryStore.swift`
- `leanring-buddy/LumaTests/ClaudeAgentRuntimeStateTests.swift`
- `leanring-buddy/LumaTests/AgentExecutionCoordinatorTests.swift`

## Reference
- OpenClicky source: `/Users/nox/Desktop/openclicky`
- Full PRD: `/Users/nox/Desktop/luma/LUMA_V3_PRD.md`
- Codex worktree: `/Users/nox/Desktop/luma/.worktrees/codex-luma-v3-claude-agent-rebuild`
