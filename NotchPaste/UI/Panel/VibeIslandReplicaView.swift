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
        supportedAgentCount: 0,
        supportedTerminalCount: 0,
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
        question: nil,
        planReview: VibePlanReview(title: "", summary: "", points: []),
        usageMeters: [],
        supportedAgents: []
    )

    static let empty = VibeIslandDashboard(
        supportedAgentCount: 0,
        supportedTerminalCount: 0,
        sessions: [],
        question: nil,
        planReview: VibePlanReview(title: "", summary: "", points: []),
        usageMeters: [],
        supportedAgents: []
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

struct VibeNativeSessionRow: Identifiable {
    let id: UUID
    let title: String
    let subtitle: String
    let projectTitle: String
    let detail: String
    let state: String
    let usageLabel: String?
    let tint: Color
    let isWaitingForApproval: Bool
    let primaryActionTitle: String
    let secondaryActionTitle: String?

    init(session: VibeSession, usageLabel: String? = nil) {
        id = session.id
        title = session.agent
        subtitle = session.terminal
        projectTitle = session.title
        detail = session.detail
        state = session.state
        self.usageLabel = usageLabel
        tint = session.tint
        isWaitingForApproval = session.action == .approval
        primaryActionTitle = session.primaryActionTitle
        secondaryActionTitle = session.secondaryActionTitle
    }

    var showsInlineApproval: Bool {
        isWaitingForApproval
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

    var nativeRows: [VibeNativeSessionRow] {
        dashboard.sessions.map { session in
            VibeNativeSessionRow(
                session: session,
                usageLabel: dashboard.usageMeters.first { $0.agent == session.agent }?.label
            )
        }
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
        lastAction = dashboard.planReview.title.isEmpty ? "无审阅计划" : "正在审阅 \(dashboard.planReview.title)"
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

    var body: some View {
        VStack(spacing: 0) {
            if model.nativeRows.isEmpty {
                emptyState
            } else {
                sessionList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .background(Color.black)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No sessions")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.42))

            Text("Run Claude, Codex, or Gemini in terminal")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.27))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var sessionList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 2) {
                ForEach(model.nativeRows) { row in
                    nativeRow(row)
                }
            }
            .padding(.vertical, 4)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func nativeRow(_ row: VibeNativeSessionRow) -> some View {
        HStack(alignment: .center, spacing: 10) {
            stateIndicator(for: row)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(row.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Text(row.subtitle)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.34))
                        .lineLimit(1)

                    if let usage = row.usageLabel {
                        Text(usage)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.3))
                            .lineLimit(1)
                    }
                }

                Text(row.projectTitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.86))
                    .lineLimit(1)

                Text(row.detail.isEmpty ? row.state : row.detail)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(row.isWaitingForApproval ? TerminalPalette.amber : .white.opacity(0.42))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            rowActions(row)
        }
        .padding(.leading, 8)
        .padding(.trailing, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(model.selectedSessionID == row.id ? row.tint.opacity(0.12) : Color.clear)
        )
        .onTapGesture(count: 2) {
            model.open(sessionID: row.id)
        }
    }

    @ViewBuilder
    private func stateIndicator(for row: VibeNativeSessionRow) -> some View {
        if row.isWaitingForApproval {
            Text("✢")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(TerminalPalette.amber)
        } else if row.state == "Ready" || row.state == "Completed" || row.primaryActionTitle == "Jump" {
            Circle()
                .fill(TerminalPalette.green)
                .frame(width: 6, height: 6)
        } else {
            Text("·")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(row.tint)
        }
    }

    @ViewBuilder
    private func rowActions(_ row: VibeNativeSessionRow) -> some View {
        if row.showsInlineApproval {
            HStack(spacing: 6) {
                iconButton("bubble.left") {
                    model.open(sessionID: row.id)
                }

                Button("Deny") {
                    model.deny(sessionID: row.id)
                }
                .buttonStyle(VibeNativeButtonStyle(filled: false, tint: row.tint))

                Button("Allow") {
                    model.allow(sessionID: row.id)
                }
                .buttonStyle(VibeNativeButtonStyle(filled: true, tint: .white))
            }
        } else {
            HStack(spacing: 6) {
                iconButton("bubble.left") {
                    model.open(sessionID: row.id)
                }

                Button(row.primaryActionTitle) {
                    performPrimaryAction(for: row)
                }
                .buttonStyle(VibeNativeButtonStyle(filled: false, tint: row.tint))
            }
        }
    }

    private func iconButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.45))
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(0.055))
                )
        }
        .buttonStyle(.plain)
    }

    private func performPrimaryAction(for row: VibeNativeSessionRow) {
        switch row.primaryActionTitle {
        case "Allow":
            model.allow(sessionID: row.id)
        case "Jump":
            model.jump(sessionID: row.id)
        default:
            model.open(sessionID: row.id)
        }
    }
}

private struct TerminalPalette {
    static let amber = Color(red: 1.0, green: 0.55, blue: 0.16)
    static let green = Color(red: 0.18, green: 0.82, blue: 0.4)
}

private struct VibeNativeButtonStyle: ButtonStyle {
    let filled: Bool
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(filled ? .black : tint.opacity(0.92))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(filled ? tint.opacity(configuration.isPressed ? 0.76 : 0.92) : tint.opacity(configuration.isPressed ? 0.22 : 0.12))
            )
    }
}
