# Vibe Multi-Agent Dashboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build real Claude, Codex, and Gemini support for the Vibe dashboard through a unified agent event model and hook adapters.

**Architecture:** Add a shared `VibeAgentEvent`/`VibeAgentStore` layer and make the UI consume that layer instead of the Claude-only store. Keep Claude's existing socket response path, add Codex and Gemini hook installers/scripts that send normalized events, and degrade unsupported response actions to terminal handoff.

**Tech Stack:** Swift 5.10, SwiftUI, Foundation JSON serialization, Unix domain sockets, Xcode unit tests.

---

### Task 1: Unified Agent Model

**Files:**
- Create: `NotchPaste/Core/VibeAgentModels.swift`
- Test: `NotchPasteTests/VibeAgentStoreTests.swift`

- [ ] **Step 1: Write failing tests**

Add tests proving Claude, Codex, and Gemini events map into one dashboard and sort newest first.

- [ ] **Step 2: Run tests and verify failure**

Run: `xcodegen generate && xcodebuild test -scheme NotchPaste -destination 'platform=macOS' -only-testing:NotchPasteTests/VibeAgentStoreTests`

Expected: build fails because `VibeAgentStore` and `VibeAgentEvent` do not exist.

- [ ] **Step 3: Implement minimal model and store**

Create `VibeAgentModels.swift` with `VibeAgentKind`, `VibeAgentStatus`, `VibeAgentResponseMode`, `VibeAgentEvent`, `VibeAgentSessionState`, and `VibeAgentStore`.

- [ ] **Step 4: Run tests and verify pass**

Run the same focused test command. Expected: all new tests pass.

### Task 2: Claude Adapter Migration

**Files:**
- Modify: `NotchPaste/Core/VibeClaudeSessionStore.swift`
- Modify: `NotchPaste/Core/VibeClaudeHookModels.swift`
- Test: `NotchPasteTests/VibeClaudeIntegrationTests.swift`

- [ ] **Step 1: Write failing tests**

Update Claude tests to assert Claude hook events enter `VibeAgentStore`, not `VibeClaudeSessionStore`.

- [ ] **Step 2: Run tests and verify failure**

Run: `xcodebuild test -scheme NotchPaste -destination 'platform=macOS' -only-testing:NotchPasteTests/VibeClaudeIntegrationTests`

Expected: failure because bridge still writes to Claude-only store.

- [ ] **Step 3: Implement Claude adapter**

Add `VibeClaudeHookEvent.agentEvent` mapping. Update `VibeClaudeBridge.start()` to process events through `VibeAgentStore.shared`.

- [ ] **Step 4: Run tests and verify pass**

Run the same focused test command. Expected: pass.

### Task 3: Codex Hook Adapter

**Files:**
- Create: `NotchPaste/Core/VibeCodexHookInstaller.swift`
- Create: `NotchPaste/Core/VibeCodexHookModels.swift`
- Test: `NotchPasteTests/VibeCodexIntegrationTests.swift`

- [ ] **Step 1: Write failing tests**

Add tests for merging `~/.codex/hooks.json` while preserving unrelated hooks, generating a Codex script, and mapping a Codex hook payload to a Codex session.

- [ ] **Step 2: Run tests and verify failure**

Run: `xcodebuild test -scheme NotchPaste -destination 'platform=macOS' -only-testing:NotchPasteTests/VibeCodexIntegrationTests`

Expected: build fails because Codex installer/model do not exist.

- [ ] **Step 3: Implement Codex installer and parser**

Installer writes `hooks/notchpaste-agent-state.py` under the Codex config directory and merges NotchPaste-owned entries into `hooks.json`. Parser maps hook payloads into `VibeAgentEvent(agent: .codex, responseMode: .terminalHandoff)` unless a response channel is explicitly present.

- [ ] **Step 4: Run tests and verify pass**

Run focused Codex tests. Expected: pass.

### Task 4: Gemini Hook Adapter

**Files:**
- Create: `NotchPaste/Core/VibeGeminiHookInstaller.swift`
- Create: `NotchPaste/Core/VibeGeminiHookModels.swift`
- Test: `NotchPasteTests/VibeGeminiIntegrationTests.swift`

- [ ] **Step 1: Write failing tests**

Add tests for merging `~/.gemini/settings.json` while preserving `mcpServers`, generating a Gemini script, and mapping Gemini tool hooks into a Gemini session.

- [ ] **Step 2: Run tests and verify failure**

Run: `xcodebuild test -scheme NotchPaste -destination 'platform=macOS' -only-testing:NotchPasteTests/VibeGeminiIntegrationTests`

Expected: build fails because Gemini installer/model do not exist.

- [ ] **Step 3: Implement Gemini installer and parser**

Installer writes `hooks/notchpaste-agent-state.py` under the Gemini config directory and merges NotchPaste-owned hook commands into the `hooks` object in `settings.json`. Parser maps before-tool/after-tool/notification payloads into `VibeAgentEvent(agent: .gemini, responseMode: .terminalHandoff)`.

- [ ] **Step 4: Run tests and verify pass**

Run focused Gemini tests. Expected: pass.

### Task 5: UI Store Migration and Action Dispatcher

**Files:**
- Modify: `NotchPaste/UI/Panel/VibeIslandReplicaView.swift`
- Modify: `NotchPaste/Core/VibeClaudeSessionStore.swift`
- Test: `NotchPasteTests/VibeIslandDashboardTests.swift`
- Test: `NotchPasteTests/VibeAgentStoreTests.swift`

- [ ] **Step 1: Write failing tests**

Add tests proving `Allow` dispatches through response-capable Claude metadata and Codex/Gemini fallback to `需要在 Terminal 确认`.

- [ ] **Step 2: Run tests and verify failure**

Run focused dashboard and agent store tests. Expected: failure because UI model still has Claude-only fields.

- [ ] **Step 3: Implement action dispatcher**

Move action metadata from `claudeSessionID`/`claudeToolUseID` to generic `agentSessionID`/`approvalID`/`responseMode`. Update `VibeIslandDashboardModel` to call `VibeAgentStore`.

- [ ] **Step 4: Run tests and verify pass**

Run focused tests. Expected: pass.

### Task 6: App Startup and Full Verification

**Files:**
- Modify: `NotchPaste/App/NotchPasteApp.swift`
- Test: full suite

- [ ] **Step 1: Install all bridges on startup**

Update app launch to start Claude, Codex, and Gemini installers/listeners through one `VibeAgentBridge`.

- [ ] **Step 2: Run full test suite**

Run: `xcodegen generate && xcodebuild test -scheme NotchPaste -destination 'platform=macOS'`

Expected: all tests pass.

- [ ] **Step 3: Restart app**

Quit existing NotchPaste and open the newly built debug app.

- [ ] **Step 4: Verify local hook files**

Check:
- `/tmp/claude-island.sock` exists
- `~/.claude/hooks/claude-island-state.py` exists
- `~/.codex/hooks/notchpaste-agent-state.py` exists
- `~/.gemini/hooks/notchpaste-agent-state.py` exists

Expected: all relevant files exist and unrelated config entries remain.
