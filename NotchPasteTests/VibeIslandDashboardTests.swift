import Testing
@testable import NotchPaste

@Suite("VibeIslandDashboard")
struct VibeIslandDashboardTests {

    @Test("demo data exposes native sessions without dashboard decorations")
    func demoDataExposesNativeSessionsWithoutDashboardDecorations() {
        let dashboard = VibeIslandDashboard.demo

        #expect(dashboard.sessions.contains { $0.agent == "Claude" && $0.action == .approval })
        #expect(dashboard.sessions.contains { $0.agent == "Codex" && $0.terminal == "Terminal" })
        #expect(dashboard.sessions.contains { $0.agent == "Gemini" && $0.terminal == "Ghostty" })
        #expect(dashboard.supportedAgentCount == 0)
        #expect(dashboard.supportedTerminalCount == 0)
        #expect(dashboard.question == nil)
        #expect(dashboard.planReview.points.isEmpty)
        #expect(dashboard.usageMeters.isEmpty)
    }

    @Test("approval session exposes allow and deny actions")
    func approvalSessionExposesAllowAndDenyActions() {
        let approval = VibeIslandDashboard.demo.sessions.first { $0.action == .approval }

        #expect(approval?.primaryActionTitle == "Allow")
        #expect(approval?.secondaryActionTitle == "Deny")
    }

    @Test("native approval row mirrors active permission request")
    @MainActor
    func nativeApprovalRowMirrorsActivePermissionRequest() {
        let model = VibeIslandDashboardModel(dashboard: .demo)
        let row = model.nativeRows.first { $0.isWaitingForApproval }

        #expect(row?.title == "Claude")
        #expect(row?.subtitle == "iTerm")
        #expect(row?.detail == "Edit src/auth/middleware.ts  +3 -1")
        #expect(row?.showsInlineApproval == true)
        #expect(row?.secondaryActionTitle == "Deny")
        #expect(row?.primaryActionTitle == "Allow")
    }

    @Test("dashboard exposes notch activity for running and interactive sessions")
    func dashboardExposesNotchActivityForRunningAndInteractiveSessions() {
        #expect(VibeIslandDashboard.empty.notchActivity == .idle)
        #expect(VibeIslandDashboard.demo.notchActivity == .needsInteraction)

        var runningDashboard = VibeIslandDashboard.demo
        runningDashboard.sessions.removeAll { $0.action == .approval }

        #expect(runningDashboard.notchActivity == .running)
    }

    @Test("open selects conversation detail")
    @MainActor
    func openSelectsConversationDetail() {
        let model = VibeIslandDashboardModel(dashboard: .demo)
        let session = model.dashboard.sessions.first { $0.agent == "Codex" }

        model.open(sessionID: session?.id)

        #expect(model.selectedNativeRow?.id == session?.id)
        #expect(model.selectedNativeRow?.detail == session?.detail)

        model.closeConversation()

        #expect(model.selectedNativeRow == nil)
    }

    @Test("approval chat opens permission request page")
    @MainActor
    func approvalChatOpensPermissionRequestPage() {
        let model = VibeIslandDashboardModel(dashboard: .demo)
        let approval = model.dashboard.sessions.first { $0.action == .approval }

        model.openConversation(sessionID: approval?.id)

        #expect(model.selectedPermissionRow?.id == approval?.id)
        #expect(model.selectedNativeRow == nil)
    }

    @Test("native mode filters expose overview approvals questions and jump sessions")
    @MainActor
    func nativeModeFiltersExposeOverviewApprovalsQuestionsAndJumpSessions() {
        let model = VibeIslandDashboardModel(dashboard: .demo)

        model.mode = .overview
        #expect(model.visibleRows.count == model.nativeRows.count)

        model.mode = .approvals
        #expect(model.visibleRows.allSatisfy { $0.showsInlineApproval })

        model.mode = .questions
        #expect(model.visibleRows.isEmpty)

        model.mode = .jump
        #expect(model.visibleRows.allSatisfy { $0.primaryActionTitle == "Jump" })
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

    @Test("jump exposes local feedback")
    @MainActor
    func jumpExposesLocalFeedback() {
        var jumpedTerminal: String?
        let model = VibeIslandDashboardModel(
            dashboard: .demo,
            terminalJumper: { session in
                jumpedTerminal = session.terminal
            }
        )
        let completed = model.dashboard.sessions.first { $0.action == .jump }

        model.jump(sessionID: completed?.id)
        #expect(model.lastAction == "跳回 iTerm")
        #expect(jumpedTerminal == "iTerm")
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
