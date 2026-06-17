# Vibe Native Tab Design

## Goal

Replace only the Vibe tab dashboard with a `vibe-notch` style native agent surface while keeping the clipboard tab and notch shell intact.

## Scope

Remove the current Vibe Island dashboard presentation: the large title, agent and terminal metrics, dashboard feature chips, standalone usage card, question card, and modal approval card. The Vibe tab becomes a compact session list with inline actions modeled after `farouqaldori/vibe-notch`.

The clipboard list, clipboard capture, paste behavior, settings panel, notch geometry, and global shortcut behavior remain unchanged.

## User Experience

The Vibe tab header reads `Vibe`. Empty state shows that no agent sessions are active and asks the user to run Claude, Codex, or Gemini in a terminal.

When sessions exist, the tab shows a single vertical list. Each row displays an activity indicator, agent or project title, terminal, latest tool/message detail, optional usage label, and actions. Approval rows show `Deny` and `Allow` inline. Non-approval rows show `Open` or `Jump` based on current action state.

Claude socket approval sends the decision directly. Codex and Gemini terminal handoff sessions do not fake approval; they move into the existing terminal-confirmation feedback path.

## Data Model

Keep `VibeAgentStore` and `VibeIslandDashboardModel` as the app boundary for agent events. `VibeIslandDashboard` remains a transport model for sessions and usage while the UI stops presenting it as a dashboard.

Add a derived `VibeNativeSessionRow` model for UI rows. It maps `VibeSession` into `vibe-notch` concepts: phase, primary text, secondary text, status indicator, usage label, and action visibility.

## Testing

Tests must prove:

- Vibe tab title is `Vibe`, not `Vibe Island`.
- Demo data no longer exposes dashboard metrics, questions, plan review, or usage cards.
- Waiting approval rows expose inline `Allow` and `Deny`.
- Codex/Gemini terminal handoff still reports that confirmation must happen in Terminal.

