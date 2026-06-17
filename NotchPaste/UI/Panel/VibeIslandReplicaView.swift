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

    var notchActivity: VibeNotchActivity {
        if sessions.contains(where: { $0.action == .approval || $0.action == .question }) {
            return .needsInteraction
        }

        if sessions.contains(where: { $0.action == .monitor }) {
            return .running
        }

        return .idle
    }
}

enum VibeNotchActivity: Equatable {
    case idle
    case running
    case needsInteraction
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

    var selectedNativeRow: VibeNativeSessionRow? {
        guard let selectedSessionID else { return nil }
        return nativeRows.first { $0.id == selectedSessionID }
    }

    var pendingInteractionRow: VibeNativeSessionRow? {
        nativeRows.first { $0.showsInlineApproval }
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

    func closeConversation() {
        selectedSessionID = nil
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
        ZStack {
            VStack(spacing: 0) {
                if let selectedRow = model.selectedNativeRow {
                    conversationDetail(selectedRow)
                } else if model.nativeRows.isEmpty {
                    emptyState
                } else {
                    sessionList
                }
            }

            if model.selectedNativeRow == nil, let row = model.pendingInteractionRow {
                permissionRequestModal(row)
                    .transition(.scale(scale: 0.92, anchor: .top).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .background(Color.black)
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: model.selectedSessionID)
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: model.pendingInteractionRow?.id)
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

    private func conversationDetail(_ row: VibeNativeSessionRow) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                iconButton("chevron.left") {
                    model.closeConversation()
                }

                stateIndicator(for: row)
                    .frame(width: 14)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(row.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)

                        Text(row.subtitle)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white.opacity(0.36))

                        Text(row.usageLabel ?? row.state)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.34))
                    }

                    Text(row.projectTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.86))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                rowActions(row)
            }

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(row.state)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(row.isWaitingForApproval ? TerminalPalette.amber : row.tint)

                    conversationBlock(title: "Latest event", value: row.detail.isEmpty ? row.state : row.detail, tint: row.tint)

                    if row.isWaitingForApproval {
                        permissionDiffBlock(row)
                    }

                    if !model.lastAction.isEmpty {
                        Text(model.lastAction)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white.opacity(0.34))
                            .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 8)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func conversationBlock(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.36))

            Text(value)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.84))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tint.opacity(0.08))
        )
    }

    private func permissionRequestModal(_ row: VibeNativeSessionRow) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(row.tint.opacity(0.55))
                    .frame(width: 6, height: 6)

                Text("Permission Request")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.45))
            }

            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(TerminalPalette.amber)

                Text(permissionTitle(for: row))
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundColor(TerminalPalette.amber)
                    .lineLimit(1)

                Text(permissionPath(for: row))
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.86))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            permissionDiffBlock(row)
                .frame(height: 82)
                .clipped()

            HStack(spacing: 8) {
                Button("Deny") {
                    model.deny(sessionID: row.id)
                }
                .buttonStyle(VibeModalButtonStyle(filled: false))

                Button("Allow") {
                    model.allow(sessionID: row.id)
                }
                .buttonStyle(VibeModalButtonStyle(filled: true))
            }
        }
        .padding(16)
        .frame(width: 390)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.96))
                .shadow(color: .black.opacity(0.75), radius: 18, y: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
        .padding(.top, 28)
    }

    private func permissionDiffBlock(_ row: VibeNativeSessionRow) -> some View {
        let lines = permissionPreviewLines(for: row)

        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line.text)
                    .foregroundColor(line.color)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(line.background)
            }
        }
        .font(.system(size: 11, weight: .medium, design: .monospaced))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func permissionPreviewLines(for row: VibeNativeSessionRow) -> [PermissionPreviewLine] {
        if row.detail.localizedCaseInsensitiveContains("edit ") {
            return [
                PermissionPreviewLine("12 const verify = (token) =>", color: .white.opacity(0.24), background: .white.opacity(0.04)),
                PermissionPreviewLine("13 - jwt.verify(token);", color: Color(red: 1.0, green: 0.55, blue: 0.5), background: .red.opacity(0.14)),
                PermissionPreviewLine("13 + if (!token) throw new", color: TerminalPalette.green, background: TerminalPalette.green.opacity(0.10)),
                PermissionPreviewLine("14 + AuthError('missing');", color: TerminalPalette.green, background: TerminalPalette.green.opacity(0.10))
            ]
        }

        return [
            PermissionPreviewLine(row.state, color: .white.opacity(0.24), background: .white.opacity(0.04)),
            PermissionPreviewLine(row.detail.isEmpty ? row.projectTitle : row.detail, color: .white.opacity(0.82), background: Color.white.opacity(0.03)),
            PermissionPreviewLine("Waiting for approval", color: TerminalPalette.amber, background: TerminalPalette.amber.opacity(0.10))
        ]
    }

    private func permissionTitle(for row: VibeNativeSessionRow) -> String {
        row.detail.split(separator: " ").first.map(String.init) ?? "Edit"
    }

    private func permissionPath(for row: VibeNativeSessionRow) -> String {
        let parts = row.detail.split(separator: " ").map(String.init)
        guard parts.count > 1 else { return row.projectTitle }
        return parts.dropFirst().prefix { !$0.hasPrefix("+") && !$0.hasPrefix("-") }.joined(separator: " ")
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

private struct PermissionPreviewLine {
    let text: String
    let color: Color
    let background: Color

    init(_ text: String, color: Color, background: Color) {
        self.text = text
        self.color = color
        self.background = background
    }
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

private struct VibeModalButtonStyle: ButtonStyle {
    let filled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(filled ? .black : .white.opacity(0.84))
            .frame(maxWidth: .infinity)
            .frame(height: 31)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(filled ? Color.white.opacity(configuration.isPressed ? 0.78 : 0.92) : Color.white.opacity(configuration.isPressed ? 0.18 : 0.13))
            )
    }
}
