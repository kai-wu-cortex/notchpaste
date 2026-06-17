import Foundation
import Testing
@testable import NotchPaste

@Suite("VibeAgentStore")
struct VibeAgentStoreTests {

    @Test("mixed agent events map into one dashboard sorted newest first")
    @MainActor
    func mixedAgentEventsMapIntoOneDashboardSortedNewestFirst() {
        let store = VibeAgentStore()
        let base = Date(timeIntervalSince1970: 1_800_000_000)

        store.process(VibeAgentEvent(
            agent: .claude,
            sessionID: "claude-1",
            cwd: "/tmp/claude-app",
            terminal: "iTerm",
            event: "PermissionRequest",
            status: .waitingForApproval,
            toolName: "Edit",
            toolInputSummary: "file_path: auth.ts",
            approvalID: "tool-1",
            responseMode: .socket,
            createdAt: base
        ))
        store.process(VibeAgentEvent(
            agent: .codex,
            sessionID: "codex-1",
            cwd: "/tmp/codex-app",
            terminal: "Terminal",
            event: "PreToolUse",
            status: .processing,
            toolName: "Bash",
            toolInputSummary: "npm test",
            responseMode: .terminalHandoff,
            createdAt: base.addingTimeInterval(20)
        ))
        store.process(VibeAgentEvent(
            agent: .gemini,
            sessionID: "gemini-1",
            cwd: "/tmp/gemini-app",
            terminal: "Ghostty",
            event: "BeforeTool",
            status: .runningTool,
            toolName: "Read",
            toolInputSummary: "schema.prisma",
            responseMode: .terminalHandoff,
            createdAt: base.addingTimeInterval(10)
        ))

        #expect(store.dashboard.supportedAgentCount == 3)
        #expect(store.dashboard.sessions.map(\.agent) == ["Codex", "Gemini", "Claude"])
        #expect(store.dashboard.sessions.map(\.terminal) == ["Terminal", "Ghostty", "iTerm"])
        #expect(store.dashboard.sessions[2].action == .approval)
        #expect(store.dashboard.sessions[2].agentSessionID == "claude-1")
        #expect(store.dashboard.sessions[2].approvalID == "tool-1")
        #expect(store.dashboard.sessions[2].responseMode == .socket)
    }

    @Test("terminal handoff action records honest local feedback")
    @MainActor
    func terminalHandoffActionRecordsHonestLocalFeedback() {
        let store = VibeAgentStore()
        let event = VibeAgentEvent(
            agent: .codex,
            sessionID: "codex-approval",
            cwd: "/tmp/codex-app",
            terminal: "Terminal",
            event: "PermissionRequest",
            status: .waitingForApproval,
            toolName: "Bash",
            toolInputSummary: "rm temp",
            approvalID: "approval-1",
            responseMode: .terminalHandoff,
            createdAt: Date()
        )

        store.process(event)
        let sessionID = store.dashboard.sessions.first?.id
        store.allow(sessionID: sessionID)

        #expect(store.lastAction == "Codex 需要在 Terminal 确认")
        #expect(store.dashboard.sessions.first?.action == .jump)
        #expect(store.dashboard.sessions.first?.state == "需要终端确认")
    }

    @Test("usage meters aggregate by agent and include Codex usage")
    @MainActor
    func usageMetersAggregateByAgentAndIncludeCodexUsage() {
        let store = VibeAgentStore()
        store.process(VibeAgentEvent(
            agent: .claude,
            sessionID: "claude-1",
            cwd: "/tmp/claude-app",
            terminal: "iTerm",
            event: "PreToolUse",
            status: .runningTool,
            usageLabel: "live"
        ))
        store.process(VibeAgentEvent(
            agent: .claude,
            sessionID: "claude-2",
            cwd: "/tmp/claude-app",
            terminal: "iTerm",
            event: "PreToolUse",
            status: .runningTool,
            usageLabel: "live"
        ))
        store.process(VibeAgentEvent(
            agent: .codex,
            sessionID: "codex-1",
            cwd: "/tmp/codex-app",
            terminal: "Terminal",
            event: "TokenUsage",
            status: .processing,
            usageLabel: "42%"
        ))

        #expect(store.dashboard.usageMeters.map(\.agent) == ["Claude", "Codex"])
        #expect(store.dashboard.usageMeters.first { $0.agent == "Codex" }?.label == "42%")
    }

    @Test("new Codex event replaces stale Claude event for same workspace")
    @MainActor
    func codexEventReplacesStaleClaudeEventForSameWorkspace() {
        let store = VibeAgentStore()
        let workspace = "/Users/kyle/codex project/pasteboard"
        let base = Date(timeIntervalSince1970: 1_800_000_000)

        store.process(VibeAgentEvent(
            agent: .claude,
            sessionID: "stale",
            cwd: workspace,
            terminal: "Terminal",
            event: "Stop",
            status: .completed,
            createdAt: base
        ))
        store.process(VibeAgentEvent(
            agent: .codex,
            sessionID: "codex-live",
            cwd: workspace,
            terminal: "Terminal",
            event: "Stop",
            status: .completed,
            responseMode: .terminalHandoff,
            createdAt: base.addingTimeInterval(1)
        ))

        #expect(store.dashboard.sessions.map(\.agent) == ["Codex"])
    }

    @Test("process command identifies agent kind")
    func processCommandIdentifiesAgentKind() {
        #expect(VibeAgentProcessResolver.kind(fromCommandLine: "/opt/homebrew/bin/codex exec") == .codex)
        #expect(VibeAgentProcessResolver.kind(fromCommandLine: "/Users/kyle/.npm/bin/claude") == .claude)
        #expect(VibeAgentProcessResolver.kind(fromCommandLine: "/opt/homebrew/bin/gemini --model pro") == .gemini)
        #expect(VibeAgentProcessResolver.kind(fromCommandLine: "/bin/zsh -l") == nil)
    }
}
