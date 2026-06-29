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

    @Test("agent store saves dashboard snapshot for idle session recovery")
    @MainActor
    func agentStoreSavesDashboardSnapshotForIdleSessionRecovery() throws {
        let dir = try temporaryDirectory()
        let snapshotStore = VibeIslandEventStore(directory: dir)
        let store = VibeAgentStore(snapshotStore: snapshotStore, snapshotSaveDelay: 0)

        store.process(VibeAgentEvent(
            agent: .claude,
            sessionID: "claude-idle",
            cwd: "/tmp/pasteboard",
            terminal: "Terminal",
            event: "Stop",
            status: .waitingForInput,
            question: "Stop"
        ))

        let restored = try snapshotStore.loadDashboard()
        #expect(restored.sessions.map(\.agent) == ["Claude"])
        #expect(restored.sessions.first?.title == "pasteboard")
        #expect(restored.sessions.first?.action == .jump)
    }

    @Test("agent store coalesces rapid dashboard snapshot writes")
    @MainActor
    func agentStoreCoalescesRapidDashboardSnapshotWrites() async throws {
        let snapshotStore = CountingSnapshotStore()
        let store = VibeAgentStore(snapshotStore: snapshotStore, snapshotSaveDelay: 0.05)
        let base = Date(timeIntervalSince1970: 1_800_000_000)

        store.process(VibeAgentEvent(
            agent: .codex,
            sessionID: "codex-live",
            cwd: "/tmp/pasteboard",
            event: "PreToolUse",
            status: .runningTool,
            createdAt: base
        ))
        store.process(VibeAgentEvent(
            agent: .codex,
            sessionID: "codex-live",
            cwd: "/tmp/pasteboard",
            event: "PostToolUse",
            status: .processing,
            createdAt: base.addingTimeInterval(1)
        ))
        store.process(VibeAgentEvent(
            agent: .codex,
            sessionID: "codex-live",
            cwd: "/tmp/pasteboard",
            event: "Notification",
            status: .waitingForInput,
            question: "Stop",
            createdAt: base.addingTimeInterval(2)
        ))

        #expect(snapshotStore.saveCount == 0)
        try await Task.sleep(nanoseconds: 350_000_000)
        #expect(snapshotStore.saveCount == 1)
        #expect(snapshotStore.latestDashboard?.sessions.first?.detail == "Stop")
    }

    @Test("agent store coalesces high frequency dashboard publishes")
    @MainActor
    func agentStoreCoalescesHighFrequencyDashboardPublishes() async throws {
        let store = VibeAgentStore(dashboardPublishDelay: 0.05)
        let base = Date(timeIntervalSince1970: 1_800_000_000)

        store.process(VibeAgentEvent(
            agent: .codex,
            sessionID: "codex-live",
            cwd: "/tmp/pasteboard",
            event: "PreToolUse",
            status: .runningTool,
            toolName: "Bash",
            toolInputSummary: "npm test",
            createdAt: base
        ))
        store.process(VibeAgentEvent(
            agent: .codex,
            sessionID: "codex-live",
            cwd: "/tmp/pasteboard",
            event: "PostToolUse",
            status: .processing,
            toolName: "Bash",
            toolInputSummary: "8 passed",
            createdAt: base.addingTimeInterval(1)
        ))

        #expect(store.dashboard.sessions.isEmpty)

        try await Task.sleep(nanoseconds: 120_000_000)

        #expect(store.dashboard.sessions.count == 1)
        #expect(store.dashboard.sessions.first?.detail == "Bash 8 passed")
        #expect(store.dashboard.notchActivity == .running)
    }

    @Test("interactive agent events publish immediately with dashboard coalescing")
    @MainActor
    func interactiveAgentEventsPublishImmediatelyWithDashboardCoalescing() {
        let store = VibeAgentStore(dashboardPublishDelay: 10)

        store.process(VibeAgentEvent(
            agent: .claude,
            sessionID: "claude-approval",
            cwd: "/tmp/pasteboard",
            event: "PermissionRequest",
            status: .waitingForApproval,
            toolName: "Bash",
            toolInputSummary: "rm temp",
            approvalID: "tool-1",
            responseMode: .socket
        ))

        #expect(store.dashboard.sessions.count == 1)
        #expect(store.dashboard.notchActivity == .needsInteraction)
        #expect(store.dashboard.sessions.first?.action == .approval)
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

    @Test("stop event clears notch activity")
    @MainActor
    func stopEventClearsNotchActivity() {
        let store = VibeAgentStore()
        let base = Date(timeIntervalSince1970: 1_800_000_000)

        store.process(VibeAgentEvent(
            agent: .codex,
            sessionID: "codex-stop",
            cwd: "/tmp/codex-app",
            terminal: "Terminal",
            event: "PreToolUse",
            status: .runningTool,
            toolName: "Bash",
            toolInputSummary: "npm test",
            createdAt: base
        ))

        #expect(store.dashboard.notchActivity == .running)

        store.process(VibeAgentEvent(
            agent: .codex,
            sessionID: "codex-stop",
            cwd: "/tmp/codex-app",
            terminal: "Terminal",
            event: "Stop",
            status: .completed,
            question: "Stop",
            createdAt: base.addingTimeInterval(1)
        ))

        #expect(store.dashboard.sessions.first?.state == "Completed")
        #expect(store.dashboard.sessions.first?.action == .monitor)
        #expect(store.dashboard.notchActivity == .idle)
    }

    @Test("failed event stays visible without jump action")
    @MainActor
    func failedEventStaysVisibleWithoutJumpAction() {
        let store = VibeAgentStore()

        store.process(VibeAgentEvent(
            agent: .codex,
            sessionID: "codex-failed",
            cwd: "/tmp/codex-app",
            terminal: "Terminal",
            event: "StopFailure",
            status: .failed,
            question: "Failed"
        ))

        #expect(store.dashboard.sessions.first?.state == "Failed")
        #expect(store.dashboard.sessions.first?.action == .monitor)
        #expect(store.dashboard.notchActivity == .idle)
    }

    @Test("session keeps user agent and processing history")
    @MainActor
    func sessionKeepsUserAgentAndProcessingHistory() {
        let store = VibeAgentStore()
        let base = Date(timeIntervalSince1970: 1_800_000_000)

        store.process(VibeAgentEvent(
            agent: .codex,
            sessionID: "codex-history",
            cwd: "/tmp/app",
            event: "UserPromptSubmit",
            status: .processing,
            question: "修复 Jump 显示错误",
            createdAt: base
        ))
        store.process(VibeAgentEvent(
            agent: .codex,
            sessionID: "codex-history",
            cwd: "/tmp/app",
            event: "PreToolUse",
            status: .runningTool,
            toolName: "Bash",
            toolInputSummary: "xcodebuild test",
            createdAt: base.addingTimeInterval(1)
        ))
        store.process(VibeAgentEvent(
            agent: .codex,
            sessionID: "codex-history",
            cwd: "/tmp/app",
            event: "Notification",
            status: .waitingForInput,
            toolName: nil,
            toolInputSummary: nil,
            question: "测试通过，等待确认",
            createdAt: base.addingTimeInterval(2)
        ))

        let events = store.dashboard.sessions.first?.history ?? []
        #expect(events.map(\.kind) == [.userInput, .processing, .agentOutput])
        #expect(events.map(\.message) == ["修复 Jump 显示错误", "Bash xcodebuild test", "测试通过，等待确认"])
    }

    @Test("edit tool input becomes code diff in session history")
    @MainActor
    func editToolInputBecomesCodeDiffInSessionHistory() {
        let store = VibeAgentStore()
        let diff = [
            VibeCodeDiffLine("Edit src/auth/middleware.ts", style: .context),
            VibeCodeDiffLine("- jwt.verify(token);", style: .removed),
            VibeCodeDiffLine("+ if (!token) throw new AuthError('missing');", style: .added)
        ]

        store.process(VibeAgentEvent(
            agent: .codex,
            sessionID: "codex-diff",
            cwd: "/tmp/app",
            event: "PermissionRequest",
            status: .waitingForApproval,
            toolName: "Edit",
            toolInputSummary: "file_path: src/auth/middleware.ts",
            codeDiff: diff,
            responseMode: .terminalHandoff
        ))

        let session = store.dashboard.sessions.first
        #expect(session?.codeDiff == diff)
        #expect(session?.history.first?.codeDiff == diff)
    }

    @Test("apply patch command becomes colored code diff")
    @MainActor
    func applyPatchCommandBecomesColoredCodeDiff() {
        let store = VibeAgentStore()
        let command = """
        *** Begin Patch
        *** Update File: NotchPaste/Core/VibeAgentModels.swift
        @@
         case .completed, .waitingForInput:
             return .jump
        +case .failed:
        +    return .jump
        *** End Patch
        """

        store.process(VibeAgentEvent(
            agent: .codex,
            sessionID: "codex-patch",
            cwd: "/tmp/app",
            event: "PreToolUse",
            status: .runningTool,
            toolName: "apply_patch",
            toolInputSummary: "command: \(command)",
            codeDiff: VibeAgentCodeDiffBuilder.lines(
                toolName: "apply_patch",
                toolInput: ["command": AnyCodable(command)]
            )
        ))

        let diff = store.dashboard.sessions.first?.codeDiff ?? []
        #expect(diff.contains(VibeCodeDiffLine("Edit NotchPaste/Core/VibeAgentModels.swift", style: .context)))
        #expect(diff.contains(VibeCodeDiffLine("+case .failed:", style: .added)))
        #expect(diff.contains(VibeCodeDiffLine("+    return .jump", style: .added)))
        #expect(store.dashboard.sessions.first?.history.first?.codeDiff == diff)
    }

    private func temporaryDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("notchpaste-agent-store-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

private final class CountingSnapshotStore: VibeIslandDashboardSnapshotStore {
    private let lock = NSLock()
    private var dashboards: [VibeIslandDashboard] = []

    var saveCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return dashboards.count
    }

    var latestDashboard: VibeIslandDashboard? {
        lock.lock()
        defer { lock.unlock() }
        return dashboards.last
    }

    func save(_ dashboard: VibeIslandDashboard) throws {
        lock.lock()
        dashboards.append(dashboard)
        lock.unlock()
    }
}
