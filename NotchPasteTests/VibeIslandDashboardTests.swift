import Foundation
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

    @Test("approval session exposes vibe permission actions")
    func approvalSessionExposesVibePermissionActions() {
        let approval = VibeIslandDashboard.demo.sessions.first { $0.action == .approval }

        #expect(approval?.approvalActions.map(\.title) == ["Deny", "Allow Once", "Allow All", "Bypass"])
        #expect(approval?.primaryActionTitle == "Allow Once")
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
        #expect(row?.primaryActionTitle == "Allow Once")
        #expect(row?.approvalActions.map(\.title) == ["Deny", "Allow Once", "Allow All", "Bypass"])
    }

    @Test("dashboard exposes notch activity for running and interactive sessions")
    func dashboardExposesNotchActivityForRunningAndInteractiveSessions() {
        #expect(VibeIslandDashboard.empty.notchActivity == .idle)
        #expect(VibeIslandDashboard.demo.notchActivity == .needsInteraction)

        var runningDashboard = VibeIslandDashboard.demo
        runningDashboard.sessions.removeAll { $0.action == .approval }
        runningDashboard.sessions.removeAll { $0.action == .jump }

        #expect(runningDashboard.notchActivity == .running)

        let jumpSession = VibeSession(
            agent: "Codex",
            terminal: "Terminal",
            title: "pasteboard",
            detail: "需要在终端确认",
            elapsed: "live",
            state: "需要终端确认",
            action: .jump,
            tint: .cyan
        )
        let jumpDashboard = VibeIslandDashboard(
            supportedAgentCount: 1,
            supportedTerminalCount: 1,
            sessions: [jumpSession],
            question: nil,
            planReview: VibePlanReview(title: "", summary: "", points: []),
            usageMeters: [],
            supportedAgents: ["Codex"]
        )

        #expect(jumpDashboard.notchActivity == .needsInteraction)

        let completedDashboard = VibeIslandDashboard(
            supportedAgentCount: 1,
            supportedTerminalCount: 1,
            sessions: [
                VibeSession(
                    agent: "Codex",
                    terminal: "Terminal",
                    title: "pasteboard",
                    detail: "Stop",
                    elapsed: "live",
                    state: "Completed",
                    action: .jump,
                    tint: .cyan
                )
            ],
            question: nil,
            planReview: VibePlanReview(title: "", summary: "", points: []),
            usageMeters: [],
            supportedAgents: ["Codex"]
        )

        #expect(completedDashboard.notchActivity == .idle)
    }

    @Test("monitor sessions in waiting or stopped states do not show running activity")
    func monitorSessionsInWaitingOrStoppedStatesDoNotShowRunningActivity() {
        for state in ["Waiting for input", "Stop", "SessionEnd", "Unknown", "需要终端确认"] {
            let dashboard = VibeIslandDashboard(
                supportedAgentCount: 1,
                supportedTerminalCount: 1,
                sessions: [
                    VibeSession(
                        agent: "Claude",
                        terminal: "Terminal",
                        title: "pasteboard",
                        detail: state,
                        elapsed: "live",
                        state: state,
                        action: .monitor,
                        tint: .orange
                    )
                ],
                question: nil,
                planReview: VibePlanReview(title: "", summary: "", points: []),
                usageMeters: [],
                supportedAgents: ["Claude"]
            )

            #expect(dashboard.notchActivity == .idle)
        }
    }

    @Test("notch diff prefers pending session and falls back to latest diff")
    func notchDiffPrefersPendingSessionAndFallsBackToLatestDiff() {
        let fallbackDiff = [VibeCodeDiffLine("+ fallback", style: .added)]
        let approvalDiff = [VibeCodeDiffLine("- approval", style: .removed)]
        let approval = VibeSession(
            agent: "Claude",
            terminal: "iTerm",
            title: "auth",
            detail: "Edit auth.ts",
            elapsed: "live",
            state: "Permission Request",
            action: .approval,
            tint: .orange,
            codeDiff: approvalDiff
        )
        let latest = VibeSession(
            agent: "Codex",
            terminal: "Terminal",
            title: "api",
            detail: "Edit api.ts",
            elapsed: "live",
            state: "Running Tool",
            action: .monitor,
            tint: .cyan,
            codeDiff: fallbackDiff
        )
        let dashboard = VibeIslandDashboard(
            supportedAgentCount: 2,
            supportedTerminalCount: 2,
            sessions: [latest, approval],
            question: nil,
            planReview: VibePlanReview(title: "", summary: "", points: []),
            usageMeters: [],
            supportedAgents: ["Codex", "Claude"]
        )

        #expect(dashboard.notchCodeDiff(preferredSessionID: approval.id) == approvalDiff)
        #expect(dashboard.notchCodeDiff(preferredSessionID: UUID()) == fallbackDiff)
    }

    @Test("notch diff falls back when approval has no diff")
    func notchDiffFallsBackWhenApprovalHasNoDiff() {
        let fallbackDiff = [VibeCodeDiffLine("+ latest", style: .added)]
        let approval = VibeSession(
            agent: "Claude",
            terminal: "iTerm",
            title: "auth",
            detail: "Approval without diff",
            elapsed: "live",
            state: "Permission Request",
            action: .approval,
            tint: .orange
        )
        let latest = VibeSession(
            agent: "Codex",
            terminal: "Terminal",
            title: "api",
            detail: "Edit api.ts",
            elapsed: "live",
            state: "Running Tool",
            action: .monitor,
            tint: .cyan,
            codeDiff: fallbackDiff
        )
        let dashboard = VibeIslandDashboard(
            supportedAgentCount: 2,
            supportedTerminalCount: 2,
            sessions: [latest, approval],
            question: nil,
            planReview: VibePlanReview(title: "", summary: "", points: []),
            usageMeters: [],
            supportedAgents: ["Codex", "Claude"]
        )

        #expect(dashboard.notchCodeDiff(preferredSessionID: approval.id) == fallbackDiff)
    }

    @Test("latest diff tab is collapsed by default and expands to all lines")
    func latestDiffTabIsCollapsedByDefaultAndExpandsToAllLines() {
        let diff = [
            VibeCodeDiffLine("Edit a.swift", style: .context),
            VibeCodeDiffLine("- old", style: .removed),
            VibeCodeDiffLine("+ new", style: .added)
        ]

        #expect(!NotchLatestDiffTabPolicy.defaultIsExpanded)
        #expect(NotchLatestDiffTabPolicy.visibleLines(from: diff, isExpanded: false).isEmpty)
        #expect(NotchLatestDiffTabPolicy.visibleLines(from: diff, isExpanded: true) == diff)
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

    @Test("ask user question session exposes inline reply options")
    @MainActor
    func askUserQuestionSessionExposesInlineReplyOptions() {
        let question = VibeSession(
            agent: "Codex",
            terminal: "Terminal",
            title: "pasteboard",
            detail: "Which deployment target?",
            elapsed: "live",
            state: "Waiting for input",
            action: .question,
            tint: .cyan,
            questionOptions: ["Production", "Staging", "Local only"]
        )
        let model = VibeIslandDashboardModel(dashboard: VibeIslandDashboard(
            supportedAgentCount: 1,
            supportedTerminalCount: 1,
            sessions: [question],
            question: nil,
            planReview: VibePlanReview(title: "", summary: "", points: []),
            usageMeters: [],
            supportedAgents: ["Codex"]
        ))

        model.mode = .questions

        #expect(model.visibleRows.first?.primaryActionTitle == "Reply")
        #expect(model.visibleRows.first?.questionOptions == ["Production", "Staging", "Local only"])
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

    @Test("submit reply records user input on selected session")
    @MainActor
    func submitReplyRecordsUserInputOnSelectedSession() {
        var sentReply: (agent: String, value: String)?
        let model = VibeIslandDashboardModel(
            dashboard: .demo,
            replySender: { session, value in
                sentReply = (session.agent, value)
                return true
            }
        )
        let session = model.dashboard.sessions.first { $0.agent == "Codex" }

        model.submitReply("继续检查失败原因", sessionID: session?.id)

        let updated = model.dashboard.sessions.first { $0.id == session?.id }
        #expect(updated?.history.last?.kind == .userInput)
        #expect(updated?.history.last?.message == "继续检查失败原因")
        #expect(model.lastAction == "已发送给 Codex")
        #expect(sentReply?.agent == "Codex")
        #expect(sentReply?.value == "继续检查失败原因")
    }

    @Test("submit reply reports terminal handoff when sender cannot inject")
    @MainActor
    func submitReplyReportsTerminalHandoffWhenSenderCannotInject() {
        let model = VibeIslandDashboardModel(
            dashboard: .demo,
            replySender: { _, _ in false }
        )
        let session = model.dashboard.sessions.first { $0.agent == "Codex" }

        model.submitReply("继续检查失败原因", sessionID: session?.id)

        #expect(model.lastAction == "已复制回复，请在 Terminal 回车发送")
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
