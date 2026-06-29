import Foundation
import Testing
@testable import NotchPaste

@Suite("VibeClaudeIntegration")
struct VibeClaudeIntegrationTests {

    @Test("hook installer writes Claude hook script and settings")
    func hookInstallerWritesClaudeHookScriptAndSettings() throws {
        let dir = try temporaryDirectory()

        try VibeClaudeHookInstaller.installIfNeeded(
            claudeDir: dir,
            socketPath: "/tmp/notchpaste-test.sock"
        )

        let scriptURL = dir.appendingPathComponent("hooks/claude-island-state.py")
        let settingsURL = dir.appendingPathComponent("settings.json")
        let script = try String(contentsOf: scriptURL, encoding: .utf8)
        let settingsData = try Data(contentsOf: settingsURL)
        let settings = try #require(JSONSerialization.jsonObject(with: settingsData) as? [String: Any])
        let hooks = try #require(settings["hooks"] as? [String: Any])

        #expect(script.contains(#"SOCKET_PATH = "/tmp/notchpaste-test.sock""#))
        #expect(hooks["PermissionRequest"] != nil)
        #expect(hooks["AskUserQuestion"] != nil)
        #expect(hooks["PreToolUse"] != nil)
        #expect(try VibeClaudeHookInstaller.isInstalled(claudeDir: dir))
    }

    @Test("Claude hook event becomes real Vibe dashboard session")
    @MainActor
    func claudeHookEventBecomesRealVibeDashboardSession() {
        let store = VibeAgentStore()
        let event = VibeClaudeHookEvent(
            sessionId: "session-1",
            cwd: "/Users/kyle/project/auth-api",
            event: "PermissionRequest",
            status: "waiting_for_approval",
            pid: 123,
            tty: "/dev/ttys001",
            tool: "Edit",
            toolInput: ["file_path": AnyCodable("/Users/kyle/project/auth-api/src/auth/middleware.ts")],
            toolUseId: "tool-1",
            notificationType: nil,
            message: nil,
            questionOptions: nil,
            agent: nil
        )

        store.process(event.agentEvent)

        let session = store.dashboard.sessions.first
        #expect(session?.agent == "Claude")
        #expect(session?.terminal == "ttys001")
        #expect(session?.title == "auth-api")
        #expect(session?.detail.contains("Edit") == true)
        #expect(session?.state == "Permission Request")
        #expect(session?.action == .approval)
        #expect(session?.agentSessionID == "session-1")
        #expect(session?.approvalID == "tool-1")
        #expect(session?.responseMode == .socket)
        #expect(session?.terminalProcessID == 123)
    }

    @Test("Claude AskUserQuestion becomes question session, not approval")
    @MainActor
    func claudeAskUserQuestionBecomesQuestionSessionNotApproval() {
        let store = VibeAgentStore()
        let event = VibeClaudeHookEvent(
            sessionId: "question-session",
            cwd: "/Users/kyle/project/ink-api",
            event: "AskUserQuestion",
            status: "waiting_for_approval",
            pid: 456,
            tty: "/dev/ttys003",
            tool: "AskUserQuestion",
            toolInput: ["questions": AnyCodable("请选择优化范围")],
            toolUseId: nil,
            notificationType: nil,
            message: "请选择优化范围",
            questionOptions: ["客户端烫印工艺", "品特工厂涂布生产工艺", "整体技术体系"],
            agent: nil
        )

        store.process(event.agentEvent)

        let session = store.dashboard.sessions.first
        #expect(session?.state == "Waiting for input")
        #expect(session?.action == .question)
        #expect(session?.primaryActionTitle == "Reply")
        #expect(session?.secondaryActionTitle == nil)
        #expect(session?.questionOptions == ["客户端烫印工艺", "品特工厂涂布生产工艺", "整体技术体系"])
        #expect(session?.responseMode == VibeAgentResponseMode.none)
        #expect(store.dashboard.notchActivity == .needsInteraction)
    }

    @Test("Claude socket event can be reclassified as Codex")
    @MainActor
    func claudeSocketEventCanBeReclassifiedAsCodex() {
        let store = VibeAgentStore()
        let event = VibeClaudeHookEvent(
            sessionId: "codex-session",
            cwd: "/Users/kyle/codex project/pasteboard",
            event: "PermissionRequest",
            status: "waiting_for_approval",
            pid: 123,
            tty: "/dev/ttys001",
            tool: "Bash",
            toolInput: ["command": AnyCodable("npm test")],
            toolUseId: "tool-1",
            notificationType: nil,
            message: nil,
            questionOptions: nil,
            agent: nil
        )

        store.process(event.agentEvent(resolvedAgent: .codex))

        let session = store.dashboard.sessions.first
        #expect(session?.agent == "Codex")
        #expect(session?.action == .jump)
        #expect(session?.responseMode == .terminalHandoff)
    }

    @Test("Claude socket event declared as Codex stays Codex")
    @MainActor
    func claudeSocketEventDeclaredAsCodexStaysCodex() {
        let store = VibeAgentStore()
        let event = VibeClaudeHookEvent(
            sessionId: "codex-session",
            cwd: "/Users/kyle/codex project/pasteboard",
            event: "SessionStart",
            status: "waiting_for_input",
            pid: nil,
            tty: "/dev/ttys002",
            tool: nil,
            toolInput: nil,
            toolUseId: nil,
            notificationType: nil,
            message: nil,
            questionOptions: nil,
            agent: "codex"
        )

        store.process(event.agentEvent)

        let session = store.dashboard.sessions.first
        #expect(session?.agent == "Codex")
        #expect(session?.terminal == "ttys002")
        #expect(session?.agentKind == .codex)
    }

    private func temporaryDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("notchpaste-claude-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
