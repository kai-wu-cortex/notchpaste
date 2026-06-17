# Vibe Multi-Agent Dashboard Design

## Goal

NotchPaste's Vibe tab must become a real multi-agent control surface for Claude, Codex, and Gemini instead of a demo dashboard. It should show live agent sessions, expose permission actions, surface questions and plans, track usage when available, and give immediate local feedback after user actions.

The first production target is Claude Code, Codex CLI, and Gemini CLI. Other agents can be added later through the same adapter boundary.

## Current State

The app already has a Vibe tab and a real Claude bridge:

- `VibeClaudeHookInstaller` installs a Claude hook script.
- `VibeClaudeHookSocketServer` listens on `/tmp/claude-island.sock`.
- `VibeClaudeSessionStore` maps Claude hook events into `VibeIslandDashboard`.
- `VibeIslandReplicaView` subscribes to the Claude store.

Codex and Gemini are not real integrations yet. They appear only in old demo data and have no event source, state model, or action response channel.

## Approach

Use a unified Agent Bridge.

Add a shared `VibeAgentEvent` model and a shared `VibeAgentStore`. Claude, Codex, and Gemini each get an adapter that converts native hook payloads into this shared event model. The UI subscribes only to the shared store.

This avoids three independent dashboard implementations and keeps future agents easy to add.

## Agent Adapters

### Claude

Keep the existing Claude socket and hook script, then convert `VibeClaudeHookEvent` into `VibeAgentEvent`.

Claude can synchronously answer permission requests through its existing open socket. `Allow` and `Deny` should continue to write the response back to the waiting hook process.

### Codex

Install or merge Codex hooks into the local Codex configuration. The adapter should prefer Codex's official hook configuration when available. Hook commands call a NotchPaste-owned script that sends JSON events to the app's local socket.

Codex events should map into:

- session started or updated
- tool started or completed
- approval request when the hook payload supports it
- notification or question when present
- usage data when present

If a Codex hook event cannot synchronously wait for an app response, the dashboard action must become `Jump` instead of pretending to approve. The local feedback should say `需要在 Terminal 确认`.

### Gemini

Install or merge Gemini hooks into `~/.gemini/settings.json`. The adapter should map Gemini hook events such as before-tool, after-tool, prompt, notification, and stop into the shared model.

Gemini permission and question handling follows the same rule as Codex: use synchronous response when the hook supports it; otherwise show a terminal handoff.

## Unified Model

`VibeAgentEvent` should include:

- `agent`: Claude, Codex, or Gemini
- `sessionID`: stable session identity
- `cwd`: working directory
- `terminal`: terminal or tty label when known
- `event`: native event name
- `status`: processing, waiting for approval, waiting for input, completed, failed, compacting, or unknown
- `toolName`
- `toolInputSummary`
- `approvalID`
- `question`
- `questionOptions`
- `planMarkdown`
- `usage`
- `createdAt`

`VibeAgentSession` should be the dashboard-facing state. It should preserve stable row identity across updates and expose:

- title
- detail
- state label
- primary action
- secondary action
- tint
- last activity
- response channel metadata

## Actions

The dashboard model should no longer special-case Claude fields. It should call a shared `VibeAgentActionDispatcher`.

Supported actions:

- `Allow`: approve a pending permission if the adapter has a response channel
- `Deny`: deny a pending permission if the adapter has a response channel
- `Reply`: send an answer when the adapter supports it, otherwise mark as terminal handoff
- `Jump`: focus the related terminal/session when available
- `Open`: select the session locally
- `Review`: show or mark plan review locally

Every action must update local feedback immediately:

- `已批准`
- `已拒绝`
- `已回答`
- `跳回 Terminal`
- `需要在 Terminal 确认`
- `无法回写，已保留状态`

## UI Behavior

The Vibe tab should show real data first.

When there are no events, it should show an empty state explaining that Claude/Codex/Gemini hooks are installed or waiting. It must not show fake sessions as live data.

The header metrics should reflect the enabled adapters:

- `3 agents` for Claude, Codex, and Gemini
- terminal count should represent known terminal targets only; if unknown, show `live` or omit the fake count

The session list should support mixed agents. Rows should use agent-specific labels and colors:

- Claude: orange
- Codex: cyan
- Gemini: green

Plan, question, and usage cards should use parsed live data when available. If data is unavailable, show `unknown` or an empty state instead of fabricated percentages.

## Error Handling

Hook installation must merge with existing user configuration and remove only previous NotchPaste-owned entries. It must not delete unrelated hooks.

Socket failures should not crash the app. Failed events should be logged and ignored. Failed action responses should update local feedback with `无法回写`.

Unsupported permission response protocols must degrade to `Jump`.

## Testing

Use TDD for each behavior.

Required tests:

- Claude events still map into the unified store.
- Codex hook installer writes or merges NotchPaste-owned hook entries without deleting existing hooks.
- Gemini hook installer writes or merges NotchPaste-owned hook entries without deleting existing hooks.
- Codex hook payload maps into a Codex dashboard session.
- Gemini hook payload maps into a Gemini dashboard session.
- Mixed Claude/Codex/Gemini sessions sort by latest activity.
- `Allow` and `Deny` dispatch to the correct adapter.
- Non-response-capable adapters fall back to `Jump` with terminal confirmation feedback.
- The Vibe UI model no longer depends directly on `VibeClaudeSessionStore`.

Full suite must pass after each adapter is integrated.

## Out Of Scope

This phase does not implement support for Cursor, Qwen, Kimi, DeepSeek, or other agents.

This phase does not invent fake usage percentages. Usage appears only when available in hook payloads or parseable local logs.

This phase does not require perfect terminal focusing for every terminal app. If terminal identity is unavailable, action feedback must be honest.
