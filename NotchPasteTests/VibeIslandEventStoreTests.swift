import Foundation
import Testing
@testable import NotchPaste

@Suite("VibeIslandEventStore")
struct VibeIslandEventStoreTests {

    @Test("loads agent sessions from local event file")
    func loadsAgentSessionsFromLocalEventFile() throws {
        let dir = try temporaryDirectory()
        let store = VibeIslandEventStore(directory: dir)
        let events = [
            VibeIslandAgentEvent(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                agent: "Claude",
                terminal: "iTerm",
                title: "fix auth bug",
                detail: "Edit middleware",
                elapsed: "28m",
                state: "Permission Request",
                action: .approval,
                tint: "orange"
            ),
            VibeIslandAgentEvent(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                agent: "Codex",
                terminal: "Terminal",
                title: "backend server",
                detail: "Bash npm test",
                elapsed: "1h",
                state: "Building",
                action: .monitor,
                tint: "cyan"
            ),
            VibeIslandAgentEvent(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
                agent: "Gemini",
                terminal: "Ghostty",
                title: "optimize queries",
                detail: "Read schema",
                elapsed: "5h",
                state: "Analyzing",
                action: .monitor,
                tint: "green"
            )
        ]

        try store.save(events)
        let dashboard = try store.loadDashboard()

        #expect(dashboard.sessions.map { $0.agent } == ["Claude", "Codex", "Gemini"])
        #expect(dashboard.sessions.first?.action == .approval)
        #expect(dashboard.sessions.first?.terminal == "iTerm")
    }

    @Test("model writes local responses for approve reply and jump")
    @MainActor
    func modelWritesLocalResponsesForApproveReplyAndJump() throws {
        let dir = try temporaryDirectory()
        let store = VibeIslandEventStore(directory: dir)
        let model = VibeIslandDashboardModel(dashboard: .demo, eventStore: store)
        let approval = model.dashboard.sessions.first { $0.action == .approval }
        let completed = model.dashboard.sessions.first { $0.action == .jump }

        model.allow(sessionID: approval?.id)
        model.reply("Production")
        model.jump(sessionID: completed?.id)

        let responses = try store.loadResponses()
        #expect(responses.map { $0.action } == [.allow, .reply, .jump])
        #expect(responses[1].value == "Production")
        #expect(responses[2].value == "iTerm")
    }

    @Test("model writes free text reply for selected agent session")
    @MainActor
    func modelWritesFreeTextReplyForSelectedAgentSession() throws {
        let dir = try temporaryDirectory()
        let store = VibeIslandEventStore(directory: dir)
        let model = VibeIslandDashboardModel(dashboard: .demo, eventStore: store)
        let session = model.dashboard.sessions.first { $0.agent == "Codex" }

        model.submitReply("继续检查失败原因", sessionID: session?.id)

        let response = try #require(store.loadResponses().first)
        #expect(response.sessionID == session?.id)
        #expect(response.action == .reply)
        #expect(response.value == "继续检查失败原因")
    }

    @Test("model keeps restored agent sessions while live store is empty")
    @MainActor
    func modelKeepsRestoredAgentSessionsWhileLiveStoreIsEmpty() {
        let liveStore = VibeAgentStore()
        var restored = VibeIslandDashboard.empty
        restored.sessions = [
            VibeSession(
                agent: "Claude",
                terminal: "Terminal",
                title: "pasteboard",
                detail: "Waiting for input",
                elapsed: "live",
                state: "Waiting for input",
                action: .jump,
                tint: .orange,
                agentKind: .claude,
                agentSessionID: "claude-idle"
            )
        ]

        let model = VibeIslandDashboardModel(dashboard: restored, eventStore: nil, agentStore: liveStore)

        #expect(model.dashboard.sessions.map(\.agent) == ["Claude"])
        #expect(model.visibleRows.map(\.projectTitle) == ["pasteboard"])
    }

    private func temporaryDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("notchpaste-vibe-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
