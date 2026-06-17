# Vibe Native Tab Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the current Vibe Island dashboard tab with a compact `vibe-notch` style session list and inline approval controls.

**Architecture:** Keep the existing NotchPaste shell and clipboard tab. Replace `VibeIslandReplicaView` internals with a native session-list view backed by `VibeIslandDashboardModel`, and add small derived row data for display decisions.

**Tech Stack:** SwiftUI, Combine, Swift Testing, existing NotchPaste agent stores and hook servers.

---

### Task 1: Lock New Vibe Tab Contract

**Files:**
- Modify: `NotchPasteTests/VibeIslandDashboardTests.swift`
- Modify: `NotchPasteTests/NotchViewModelTests.swift`

- [ ] **Step 1: Write failing tests**

Add tests that expect demo dashboard decorations to be absent and the Vibe header title to be `Vibe`.

- [ ] **Step 2: Run focused tests**

Run: `xcodebuild test -scheme NotchPaste -destination 'platform=macOS' -only-testing:NotchPasteTests/VibeIslandDashboardTests`

Expected: FAIL until the transport/demo model and view header are updated.

### Task 2: Replace Dashboard Model Decorations

**Files:**
- Modify: `NotchPaste/UI/Panel/VibeIslandReplicaView.swift`
- Modify: `NotchPaste/Core/VibeAgentModels.swift`

- [ ] **Step 1: Remove dashboard-only demo data**

Change demo and empty dashboards so they do not expose question, plan review content, or fake usage cards as standalone dashboard sections.

- [ ] **Step 2: Add native row derivation**

Add `VibeNativeSessionRow` and derive rows from `VibeSession`, including inline approval visibility and usage labels.

- [ ] **Step 3: Run focused tests**

Run: `xcodebuild test -scheme NotchPaste -destination 'platform=macOS' -only-testing:NotchPasteTests/VibeIslandDashboardTests`

Expected: PASS.

### Task 3: Replace Vibe Tab UI

**Files:**
- Modify: `NotchPaste/UI/Panel/VibeIslandReplicaView.swift`
- Modify: `NotchPaste/UI/Pill/NotchView.swift`

- [ ] **Step 1: Remove old dashboard sections**

Delete or stop rendering the old Vibe title, metric boxes, feature chips, question card, usage card, and approval overlay.

- [ ] **Step 2: Implement native session list**

Render empty state or rows modeled after `vibe-notch` `ClaudeInstancesView`: indicator, title, terminal, detail, usage label, chat icon, focus/open/jump, inline Deny/Allow.

- [ ] **Step 3: Rename header text**

Change the Vibe tab header/help text from `Vibe Island` to `Vibe`.

### Task 4: Verify and Publish

**Files:**
- All changed files.

- [ ] **Step 1: Run full tests**

Run: `xcodebuild test -scheme NotchPaste -destination 'platform=macOS'`

Expected: all tests pass.

- [ ] **Step 2: Commit and push**

Commit message: `Replace Vibe dashboard with native session list`

Push branch: `code`

