import Testing
@testable import NotchPaste

@Suite("VibeIslandDashboard")
struct VibeIslandDashboardTests {

    @Test("demo dashboard mirrors Vibe Island core functions")
    func demoDashboardMirrorsVibeIslandCoreFunctions() {
        let dashboard = VibeIslandDashboard.demo

        #expect(dashboard.supportedAgentCount == 16)
        #expect(dashboard.supportedTerminalCount >= 18)
        #expect(dashboard.sessions.contains { $0.agent == "Claude" && $0.action == .approval })
        #expect(dashboard.sessions.contains { $0.agent == "Codex" && $0.terminal == "Terminal" })
        #expect(dashboard.sessions.contains { $0.agent == "Gemini" && $0.terminal == "Ghostty" })
        #expect(dashboard.question?.options == ["Production", "Staging", "Local only"])
        #expect(dashboard.planReview.title == "Plan Review")
        #expect(dashboard.usageMeters.map { $0.agent }.contains("Codex"))
    }

    @Test("approval session exposes allow and deny actions")
    func approvalSessionExposesAllowAndDenyActions() {
        let approval = VibeIslandDashboard.demo.sessions.first { $0.action == .approval }

        #expect(approval?.primaryActionTitle == "Allow")
        #expect(approval?.secondaryActionTitle == "Deny")
    }

    @Test("approval modal mirrors active permission request")
    @MainActor
    func approvalModalMirrorsActivePermissionRequest() {
        let model = VibeIslandDashboardModel(dashboard: .demo)
        let modal = model.approvalModal

        #expect(modal?.title == "Permission Request")
        #expect(modal?.toolLine == "Edit src/auth/middleware.ts")
        #expect(modal?.deltaLabel == "+3 -1")
        #expect(modal?.denyShortcut == "⌘N")
        #expect(modal?.allowShortcut == "⌘Y")
    }

    @Test("completed session jumps back to its terminal")
    func completedSessionJumpsBackToItsTerminal() {
        let completed = VibeIslandDashboard.demo.sessions.first { $0.action == .jump }

        #expect(completed?.primaryActionTitle == "Jump")
        #expect(completed?.terminal == "iTerm")
    }

    @Test("allow updates approval session and local feedback")
    @MainActor
    func allowUpdatesApprovalSessionAndLocalFeedback() {
        let model = VibeIslandDashboardModel(dashboard: .demo)
        let approval = model.dashboard.sessions.first { $0.action == .approval }

        model.allow(sessionID: approval?.id)

        #expect(model.lastAction == "Claude 已批准")
        #expect(model.dashboard.sessions.first { $0.id == approval?.id }?.state == "Approved")
        #expect(model.dashboard.sessions.first { $0.id == approval?.id }?.action == .jump)
    }

    @Test("deny updates approval session and local feedback")
    @MainActor
    func denyUpdatesApprovalSessionAndLocalFeedback() {
        let model = VibeIslandDashboardModel(dashboard: .demo)
        let approval = model.dashboard.sessions.first { $0.action == .approval }

        model.deny(sessionID: approval?.id)

        #expect(model.lastAction == "Claude 已拒绝")
        #expect(model.dashboard.sessions.first { $0.id == approval?.id }?.state == "Denied")
    }

    @Test("reply records selected deployment target")
    @MainActor
    func replyRecordsSelectedDeploymentTarget() {
        let model = VibeIslandDashboardModel(dashboard: .demo)

        model.reply("Production")

        #expect(model.lastAction == "已回答 Production")
        #expect(model.selectedQuestionOption == "Production")
    }

    @Test("plan review and jump expose local feedback")
    @MainActor
    func planReviewAndJumpExposeLocalFeedback() {
        let model = VibeIslandDashboardModel(dashboard: .demo)
        let completed = model.dashboard.sessions.first { $0.action == .jump }

        model.reviewPlan()
        #expect(model.lastAction == "正在审阅 Plan Review")

        model.jump(sessionID: completed?.id)
        #expect(model.lastAction == "跳回 iTerm")
    }

    @Test("model follows unified agent store and terminal handoff feedback")
    @MainActor
    func modelFollowsUnifiedAgentStoreAndTerminalHandoffFeedback() {
        let store = VibeAgentStore()
        let model = VibeIslandDashboardModel(dashboard: .empty, agentStore: store)
        store.process(VibeAgentEvent(
            agent: .codex,
            sessionID: "codex-approval",
            cwd: "/tmp/codex-app",
            terminal: "Terminal",
            event: "PermissionRequest",
            status: .waitingForApproval,
            toolName: "Bash",
            toolInputSummary: "npm test",
            approvalID: "approval-1",
            responseMode: .terminalHandoff
        ))

        let session = model.dashboard.sessions.first
        model.allow(sessionID: session?.id)

        #expect(model.dashboard.sessions.first?.agent == "Codex")
        #expect(model.dashboard.sessions.first?.state == "需要终端确认")
        #expect(model.lastAction == "Codex 需要在 Terminal 确认")
    }
}
