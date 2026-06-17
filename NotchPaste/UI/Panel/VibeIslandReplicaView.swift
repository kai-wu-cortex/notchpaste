import Combine
import SwiftUI

struct VibeIslandDashboard {
    let supportedAgentCount: Int
    let supportedTerminalCount: Int
    var sessions: [VibeSession]
    let question: VibeQuestion?
    let planReview: VibePlanReview
    let usageMeters: [VibeUsageMeter]
    let supportedAgents: [String]

    static let demo = VibeIslandDashboard(
        supportedAgentCount: 16,
        supportedTerminalCount: 18,
        sessions: [
            VibeSession(
                agent: "Claude",
                terminal: "iTerm",
                title: "fix auth bug",
                detail: "Edit src/auth/middleware.ts  +3 -1",
                elapsed: "28m",
                state: "Permission Request",
                action: .approval,
                tint: .orange
            ),
            VibeSession(
                agent: "Codex",
                terminal: "Terminal",
                title: "backend server",
                detail: "Bash(npm test) -> 3 passed",
                elapsed: "1h",
                state: "Building REST endpoints",
                action: .monitor,
                tint: .cyan
            ),
            VibeSession(
                agent: "Gemini",
                terminal: "Ghostty",
                title: "optimize queries",
                detail: "Read schema.prisma, edit queries.ts",
                elapsed: "5h",
                state: "Analyzing slow queries",
                action: .monitor,
                tint: .green
            ),
            VibeSession(
                agent: "Claude",
                terminal: "iTerm",
                title: "fix auth bug",
                detail: "Done - click to jump",
                elapsed: "done",
                state: "Ready",
                action: .jump,
                tint: .mint
            )
        ],
        question: VibeQuestion(
            agent: "Claude asks",
            prompt: "Which deployment target?",
            options: ["Production", "Staging", "Local only"]
        ),
        planReview: VibePlanReview(
            title: "Plan Review",
            summary: "Markdown plan ready before approval",
            points: ["middleware guard", "expiry check", "regression test"]
        ),
        usageMeters: [
            VibeUsageMeter(agent: "Claude", remaining: 0.68, label: "68%"),
            VibeUsageMeter(agent: "Codex", remaining: 0.42, label: "42%"),
            VibeUsageMeter(agent: "Kimi", remaining: 0.81, label: "81%")
        ],
        supportedAgents: [
            "Claude Code", "Codex", "Gemini CLI", "Cursor", "OpenCode", "Droid",
            "Qoder", "Qwen", "Kimi Code", "DeepSeek", "Copilot", "CodeBuddy",
            "Kiro", "Hermes", "Amp", "Pi Agent"
        ]
    )

    static let empty = VibeIslandDashboard(
        supportedAgentCount: 3,
        supportedTerminalCount: 1,
        sessions: [],
        question: nil,
        planReview: VibePlanReview(
            title: "Agent Hooks",
            summary: "等待 Claude / Codex / Gemini 事件",
            points: ["已安装 hooks", "监听工具调用", "本地状态反馈"]
        ),
        usageMeters: [],
        supportedAgents: ["Claude", "Codex", "Gemini"]
    )
}

struct VibeSession: Identifiable {
    let id: UUID
    let agent: String
    let terminal: String
    let title: String
    var detail: String
    let elapsed: String
    var state: String
    var action: VibeSessionAction
    let tint: Color
    let agentKind: VibeAgentKind?
    let agentSessionID: String?
    let approvalID: String?
    let responseMode: VibeAgentResponseMode
    let claudeSessionID: String?
    let claudeToolUseID: String?

    init(
        id: UUID = UUID(),
        agent: String,
        terminal: String,
        title: String,
        detail: String,
        elapsed: String,
        state: String,
        action: VibeSessionAction,
        tint: Color,
        agentKind: VibeAgentKind? = nil,
        agentSessionID: String? = nil,
        approvalID: String? = nil,
        responseMode: VibeAgentResponseMode = .none,
        claudeSessionID: String? = nil,
        claudeToolUseID: String? = nil
    ) {
        self.id = id
        self.agent = agent
        self.terminal = terminal
        self.title = title
        self.detail = detail
        self.elapsed = elapsed
        self.state = state
        self.action = action
        self.tint = tint
        self.agentKind = agentKind
        self.agentSessionID = agentSessionID
        self.approvalID = approvalID
        self.responseMode = responseMode
        self.claudeSessionID = claudeSessionID
        self.claudeToolUseID = claudeToolUseID
    }

    var primaryActionTitle: String {
        switch action {
        case .approval: return "Allow"
        case .question: return "Reply"
        case .jump: return "Jump"
        case .monitor: return "Open"
        }
    }

    var secondaryActionTitle: String? {
        action == .approval ? "Deny" : nil
    }
}

enum VibeSessionAction: String, Codable, Equatable {
    case approval
    case question
    case jump
    case monitor
}

struct VibeQuestion: Equatable {
    let agent: String
    let prompt: String
    let options: [String]
}

struct VibePlanReview: Equatable {
    let title: String
    let summary: String
    let points: [String]
}

struct VibeUsageMeter: Equatable {
    let agent: String
    let remaining: Double
    let label: String
}

struct VibeApprovalModal: Equatable {
    let sessionID: UUID
    let title: String
    let toolLine: String
    let contextLine: String
    let removedLine: String
    let addedLine: String
    let deltaLabel: String
    let denyShortcut: String
    let allowShortcut: String

    init(session: VibeSession) {
        sessionID = session.id
        title = session.state
        let parsed = Self.parseDetail(session.detail)
        toolLine = parsed.toolLine
        deltaLabel = parsed.deltaLabel
        if parsed.deltaLabel.isEmpty {
            contextLine = "tool \(parsed.toolLine)"
            removedLine = "- waiting for permission"
            addedLine = "+ choose Allow or Deny"
        } else {
            contextLine = "12 const verify = (token) =>"
            removedLine = "13- jwt.verify(token);"
            addedLine = "13+ if (!token) throw new AuthError('missing');"
        }
        denyShortcut = "⌘N"
        allowShortcut = "⌘Y"
    }

    private static func parseDetail(_ detail: String) -> (toolLine: String, deltaLabel: String) {
        let pattern = #"(\+\d+\s+-\d+)"#
        guard let match = detail.range(of: pattern, options: .regularExpression) else {
            return (detail, "")
        }

        let toolLine = detail[..<match.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        let deltaLabel = String(detail[match]).trimmingCharacters(in: .whitespacesAndNewlines)
        return (toolLine.isEmpty ? detail : toolLine, deltaLabel)
    }
}

@MainActor
final class VibeIslandDashboardModel: ObservableObject {
    @Published var dashboard: VibeIslandDashboard
    @Published var selectedSessionID: UUID?
    @Published var selectedQuestionOption: String?
    @Published var lastAction = "等待 Agent 事件"
    private let eventStore: VibeIslandEventStore?
    private let agentStore: VibeAgentStore?
    private var cancellables = Set<AnyCancellable>()

    init(
        dashboard: VibeIslandDashboard = .empty,
        eventStore: VibeIslandEventStore? = nil,
        agentStore: VibeAgentStore? = nil
    ) {
        self.dashboard = dashboard
        self.eventStore = eventStore
        self.agentStore = agentStore

        agentStore?.$dashboard
            .sink { [weak self] dashboard in
                self?.dashboard = dashboard
            }
            .store(in: &cancellables)

        agentStore?.$lastAction
            .sink { [weak self] action in
                self?.lastAction = action
            }
            .store(in: &cancellables)
    }

    var approvalModal: VibeApprovalModal? {
        guard let session = dashboard.sessions.first(where: { $0.action == .approval }) else { return nil }
        return VibeApprovalModal(session: session)
    }

    func allow(sessionID: UUID?) {
        if let agentStore {
            agentStore.allow(sessionID: sessionID)
        } else {
            updateApproval(sessionID: sessionID, state: "Approved", detail: "Approved - click to jump", feedback: "已批准")
        }
        writeResponse(sessionID: sessionID, action: .allow, value: "approved")
    }

    func deny(sessionID: UUID?) {
        if let agentStore {
            agentStore.deny(sessionID: sessionID)
        } else {
            updateApproval(sessionID: sessionID, state: "Denied", detail: "Denied by user", feedback: "已拒绝")
        }
        writeResponse(sessionID: sessionID, action: .deny, value: "denied")
    }

    func reply(_ option: String) {
        selectedQuestionOption = option
        lastAction = "已回答 \(option)"
        writeResponse(sessionID: nil, action: .reply, value: option)
    }

    func reviewPlan() {
        lastAction = "正在审阅 \(dashboard.planReview.title)"
        writeResponse(sessionID: nil, action: .reviewPlan, value: dashboard.planReview.title)
    }

    func open(sessionID: UUID?) {
        guard let index = sessionIndex(for: sessionID) else { return }
        let session = dashboard.sessions[index]
        selectedSessionID = session.id
        lastAction = "打开 \(session.agent) 状态"
        writeResponse(sessionID: sessionID, action: .open, value: session.agent)
    }

    func jump(sessionID: UUID?) {
        guard let index = sessionIndex(for: sessionID) else { return }
        let session = dashboard.sessions[index]
        selectedSessionID = session.id
        lastAction = "跳回 \(session.terminal)"
        writeResponse(sessionID: sessionID, action: .jump, value: session.terminal)
    }

    private func updateApproval(sessionID: UUID?, state: String, detail: String, feedback: String) {
        guard let index = sessionIndex(for: sessionID) else { return }
        dashboard.sessions[index].state = state
        dashboard.sessions[index].detail = detail
        dashboard.sessions[index].action = .jump
        selectedSessionID = dashboard.sessions[index].id
        lastAction = "\(dashboard.sessions[index].agent) \(feedback)"
    }

    private func sessionIndex(for id: UUID?) -> Int? {
        guard let id else { return nil }
        return dashboard.sessions.firstIndex { $0.id == id }
    }

    private func session(for id: UUID?) -> VibeSession? {
        guard let index = sessionIndex(for: id) else { return nil }
        return dashboard.sessions[index]
    }

    private func writeResponse(sessionID: UUID?, action: VibeIslandAgentResponseAction, value: String) {
        try? eventStore?.appendResponse(
            VibeIslandAgentResponse(
                sessionID: sessionID,
                action: action,
                value: value,
                createdAt: Date()
            )
        )
    }
}

struct VibeIslandReplicaView: View {

    @StateObject private var model: VibeIslandDashboardModel

    @MainActor
    init(
        dashboard: VibeIslandDashboard? = nil,
        eventStore: VibeIslandEventStore? = VibeIslandEventStore.defaultStore(),
        agentStore: VibeAgentStore? = nil
    ) {
        let liveAgentStore = agentStore ?? VibeAgentStore.shared
        let storedDashboard = try? eventStore?.loadDashboard()
        let initialDashboard = dashboard ?? storedDashboard ?? liveAgentStore.dashboard
        _model = StateObject(
            wrappedValue: VibeIslandDashboardModel(
                dashboard: initialDashboard,
                eventStore: eventStore,
                agentStore: liveAgentStore
            )
        )
    }

    private var dashboard: VibeIslandDashboard { model.dashboard }

    var body: some View {
        VStack(spacing: 8) {
            header
            featureRail
            sessionList
            lowerGrid
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.035, green: 0.034, blue: 0.03),
                    Color(red: 0.012, green: 0.015, blue: 0.018)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay {
            if let modal = model.approvalModal {
                approvalModal(modal)
                    .padding(.horizontal, 18)
                    .transition(.scale(scale: 0.94).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.26, dampingFraction: 0.86), value: model.approvalModal)
    }

    private var header: some View {
        HStack(spacing: 10) {
            appMark

            VStack(alignment: .leading, spacing: 2) {
                Text("Vibe Island")
                    .font(.system(size: 17, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.white)
                Text("Agent 工作时，你保持心流")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.52))
            }

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                metric("\(dashboard.supportedAgentCount)", "agents", .cyan)
                metric("\(dashboard.supportedTerminalCount)+", "terms", .orange)
            }
        }
    }

    private var appMark: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(.white.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Color.orange.opacity(0.45), lineWidth: 1)
                )

            VStack(spacing: 2) {
                HStack(spacing: 2) {
                    Pixel(color: .orange)
                    Pixel(color: .cyan)
                    Pixel(color: .white.opacity(0.35))
                }
                HStack(spacing: 2) {
                    Pixel(color: .green)
                    Pixel(color: .yellow)
                    Pixel(color: .pink)
                }
                HStack(spacing: 2) {
                    Pixel(color: .cyan.opacity(0.75))
                    Pixel(color: .orange.opacity(0.85))
                    Pixel(color: .mint)
                }
            }
        }
        .frame(width: 38, height: 38)
    }

    private func metric(_ value: String, _ label: String, _ tint: Color) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: 15, weight: .black, design: .monospaced))
                .foregroundStyle(tint)
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.42))
        }
        .frame(width: 46, height: 34)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(.white.opacity(0.055))
        )
    }

    private var featureRail: some View {
        HStack(spacing: 6) {
            featureChip("总览", "rectangle.3.group", .cyan)
            featureChip("批准", "checkmark.seal", .orange)
            featureChip("询问", "bubble.left.and.bubble.right", .pink)
            featureChip("跳回", "arrow.turn.down.right", .mint)
        }
    }

    private func featureChip(_ title: String, _ icon: String, _ tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
            Text(title)
                .font(.system(size: 10, weight: .bold))
        }
        .foregroundStyle(tint)
        .frame(maxWidth: .infinity)
        .frame(height: 25)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(tint.opacity(0.12))
        )
    }

    private var sessionList: some View {
        VStack(spacing: 5) {
            if dashboard.sessions.isEmpty {
                emptyState
            } else {
                ForEach(dashboard.sessions.prefix(3)) { session in
                    sessionRow(session)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("等待 Claude Code")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
            Text("已接入 Vibe Notch hooks。启动 Claude Code 后，会话和审批会显示在这里。")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.white.opacity(0.052))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Color.cyan.opacity(0.14), lineWidth: 1)
                )
        )
    }

    private func sessionRow(_ session: VibeSession) -> some View {
        let selected = model.selectedSessionID == session.id

        return HStack(spacing: 8) {
            VStack(spacing: 2) {
                Circle()
                    .fill(session.tint)
                    .frame(width: 7, height: 7)
                Rectangle()
                    .fill(session.tint.opacity(0.45))
                    .frame(width: 2, height: 24)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(session.agent)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                    Text(session.terminal)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.44))
                    Spacer(minLength: 0)
                    Text(session.elapsed)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                }

                Text(session.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(1)

                Text(session.detail)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(session.tint.opacity(0.8))
                    .lineLimit(1)
            }

            VStack(spacing: 4) {
                if let secondary = session.secondaryActionTitle {
                    Button(secondary) {
                        model.deny(sessionID: session.id)
                    }
                    .buttonStyle(VibeMiniButtonStyle(tint: .white.opacity(0.45), filled: false))
                }

                Button(session.primaryActionTitle) {
                    performPrimaryAction(for: session)
                }
                .buttonStyle(VibeMiniButtonStyle(tint: session.tint, filled: session.action == .approval))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(selected ? session.tint.opacity(0.16) : Color.white.opacity(0.052))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(session.tint.opacity(selected ? 0.45 : 0.16), lineWidth: 1)
                )
        )
    }

    private var lowerGrid: some View {
        HStack(alignment: .top, spacing: 7) {
            questionCard
            usageCard
        }
    }

    @ViewBuilder
    private var questionCard: some View {
        if let question = dashboard.question {
            VStack(alignment: .leading, spacing: 5) {
                cardTitle(question.agent, icon: "questionmark.bubble", tint: .pink)
                Text(question.prompt)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)

                ForEach(Array(question.options.enumerated()), id: \.offset) { index, option in
                    Button {
                        model.reply(option)
                    } label: {
                        HStack(spacing: 4) {
                            Text("⌘\(index + 1)")
                                .font(.system(size: 8, weight: .heavy, design: .monospaced))
                                .foregroundStyle(.pink)
                            Text(option)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(model.selectedQuestionOption == option ? .black : .white.opacity(0.82))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 6)
                        .frame(height: 19)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(model.selectedQuestionOption == option ? Color.pink.opacity(0.9) : Color.white.opacity(0.055))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(7)
            .background(cardBackground(.pink))
        }
    }

    private var usageCard: some View {
        VStack(alignment: .leading, spacing: 5) {
            cardTitle("用量", icon: "gauge.with.dots.needle.67percent", tint: .cyan)

            ForEach(dashboard.usageMeters, id: \.agent) { meter in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(meter.agent)
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white.opacity(0.76))
                        Spacer(minLength: 0)
                        Text(meter.label)
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(.cyan.opacity(0.9))
                    }
                    ProgressView(value: meter.remaining)
                        .tint(.cyan)
                        .scaleEffect(x: 1, y: 0.55, anchor: .center)
                }
            }

            Text(model.lastAction)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.white.opacity(0.38))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(minHeight: 95, alignment: .topLeading)
        .padding(7)
        .background(cardBackground(.cyan))
    }

    private func approvalModal(_ modal: VibeApprovalModal) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.orange.opacity(0.65))
                    .frame(width: 6, height: 6)
                Text(modal.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.46))
                Spacer(minLength: 0)
            }

            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.orange)
                Text(modal.toolLine)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            VStack(alignment: .leading, spacing: 0) {
                diffLine(modal.contextLine, color: .white.opacity(0.38), background: .clear)
                diffLine(modal.removedLine, color: .red.opacity(0.9), background: .red.opacity(0.16))
                diffLine(modal.addedLine, color: .green.opacity(0.9), background: .green.opacity(0.13))
            }
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(Color.white.opacity(0.05), lineWidth: 1)
            )

            if !modal.deltaLabel.isEmpty {
                Text(modal.deltaLabel)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.58))
            }

            HStack(spacing: 8) {
                approvalButton("Deny", shortcut: modal.denyShortcut, filled: false) {
                    model.deny(sessionID: modal.sessionID)
                }
                approvalButton("Allow", shortcut: modal.allowShortcut, filled: true) {
                    model.allow(sessionID: modal.sessionID)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: 370)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.94))
                .shadow(color: .black.opacity(0.55), radius: 22, x: 0, y: 12)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func diffLine(_ text: String, color: Color, background: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background(background)
    }

    private func approvalButton(_ title: String, shortcut: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                Text(shortcut)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(filled ? .black.opacity(0.45) : .white.opacity(0.35))
            }
            .foregroundStyle(filled ? .black : .white.opacity(0.82))
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(filled ? Color.white.opacity(0.94) : Color.white.opacity(0.13))
            )
        }
        .buttonStyle(.plain)
    }

    private func cardTitle(_ title: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
            Text(title)
                .font(.system(size: 9, weight: .heavy))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .foregroundStyle(tint)
    }

    private func cardBackground(_ tint: Color) -> some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(.white.opacity(0.045))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(tint.opacity(0.16), lineWidth: 1)
            )
    }

    private func performPrimaryAction(for session: VibeSession) {
        switch session.action {
        case .approval:
            model.allow(sessionID: session.id)
        case .question:
            model.reply(dashboard.question?.options.first ?? "")
        case .jump:
            model.jump(sessionID: session.id)
        case .monitor:
            model.open(sessionID: session.id)
        }
    }
}

private struct Pixel: View {
    let color: Color

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(width: 7, height: 7)
    }
}

private struct VibeMiniButtonStyle: ButtonStyle {
    let tint: Color
    let filled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 8, weight: .black, design: .monospaced))
            .foregroundStyle(filled ? .black : tint)
            .frame(width: 40, height: 18)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(filled ? tint.opacity(configuration.isPressed ? 0.72 : 0.95) : tint.opacity(0.12))
            )
    }
}
