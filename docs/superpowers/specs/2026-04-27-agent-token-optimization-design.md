# Agent Token Optimization Design
**Date:** 2026-04-27
**Status:** Approved
**Scope:** `ClaudeAPIAgentRuntime.swift`, `AgentSession.swift`

---

## Problem

Agent mode accumulates tokens aggressively across two runtimes:

- **`ClaudeAPIAgentRuntime`** (API fallback): `conversationMessages` grows unboundedly — every tool-use loop iteration resends all prior turns. Bash tool outputs are stored verbatim and never truncated.
- **Both runtimes** (via `AgentSession.buildContextualPrompt`): Every follow-up prompt includes the full raw transcript of all prior exchanges, causing 10x+ cost escalation across multi-turn sessions.

Single task cost: $0.15–$0.20. Multi-session cost: unpredictably higher.

---

## Solution Overview

Two complementary approaches applied together:

- **Approach A — Surgical Truncation**: Four targeted caps to prevent unbounded growth within a single task.
- **Approach B — Cheap-Model Summarization**: After each task completes, summarize the session with a cheap model. Follow-up prompts use the summary instead of raw history, keeping multi-session cost flat.

---

## Approach A — Surgical Truncation

### 1. Tool output cap (`ClaudeAPIAgentRuntime.executeBashCommand`)

Truncate combined stdout+stderr to **1200 characters**. If truncated, append `\n[... output truncated]`. Prevents verbose bash output (git log, cat, ls -la on large dirs) from permanently poisoning the context.

### 2. API loop sliding window (`ClaudeAPIAgentRuntime.executeToolUseLoop`)

Before each API call, prune `conversationMessages` to:
- `messages[0]` — the original user prompt (always kept)
- last 4 messages — the 2 most recent turns (assistant + tool_result pairs)

A new private helper `pruneConversationMessagesToSlidingWindow(_ messages:)` handles this. If `messages.count <= 5`, it returns them unchanged (no-op). Context window goes from unbounded → max 5 messages per call.

### 3. Follow-up transcript cap (`AgentSession.buildContextualPrompt`)

Cap `priorEntries` to the **last 6 transcript entries**. If older entries are dropped, prepend `[Earlier context omitted for brevity]` so the model knows history was cut.

### 4. Lower max_tokens (`ClaudeAPIAgentRuntime.sendAPIRequest`)

Reduce from 4096 → **2048**. Most agent responses are well under 1000 tokens. Caps worst-case output cost per call.

---

## Approach B — Cheap-Model Summarization

### Trigger

When `AgentSession` detects the status transition `.running → .ready`, it fires `summarizeCompletedSessionInBackground()` as an async `Task`. This runs after every completed task automatically.

### Summary content

The last 20 transcript entries are formatted compactly and sent to the cheap model with this prompt:
> "Summarize this agent session in 2–3 sentences. Be factual and specific. Include: what was requested, the key steps taken, and the outcome."

Result is stored in `completedTaskSummary: String?` on the session. max_tokens: 200.

### Usage in follow-up prompts

`buildContextualPrompt` checks for `completedTaskSummary` first:

- **If present:** replaces raw history with:
  ```
  [Previous task summary: {summary}]

  [New request:]
  {latestPrompt}
  ```
- **If absent (first task, or summary still pending):** falls back to last 6 raw transcript entries.

This makes follow-up cost flat regardless of prior session length.

### Cheap model selection

A new static helper `cheapSummaryModelID(for agentModel: String) -> String` on `AgentSession`:

| Configured model | Cheap model used |
|---|---|
| `claude-sonnet-4-6`, `claude-opus-4-6` | `anthropic/claude-haiku-4-5-20251001` |
| `gpt-4o`, `gpt-4o-mini` | `openai/gpt-4o-mini` |
| Starts with `google/` | `google/gemini-2.5-flash:free` |
| Anything else (custom / OpenRouter) | same model string as-is |

The call mirrors `generateTitleIfNeeded`: a direct URLSession POST to OpenRouter with the keychain API key.

---

## Files Modified

| File | Changes |
|---|---|
| `leanring-buddy/Agent/ClaudeAPIAgentRuntime.swift` | Tool output cap (1200 chars), sliding window helper, max_tokens 2048 |
| `leanring-buddy/Agent/AgentSession.swift` | `completedTaskSummary` property, `summarizeCompletedSessionInBackground()`, `cheapSummaryModelID(for:)`, updated `buildContextualPrompt` |

No new files. No changes to other agent files.

---

## Expected Impact

| Scenario | Before | After (estimated) |
|---|---|---|
| Single task (10 tool steps) | $0.15–$0.20 | $0.06–$0.09 |
| Multi-turn follow-up (3 sessions) | $0.45–$0.60+ | $0.12–$0.18 |
| Multi-turn follow-up (10 sessions) | $1.50–$2.00+ | $0.25–$0.40 |

Savings from A alone: ~50–65% per task. B flattens the multi-session escalation curve.
