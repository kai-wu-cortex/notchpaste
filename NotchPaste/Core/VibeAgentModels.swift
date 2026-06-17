import Foundation
import SwiftUI

enum VibeAgentKind: String, Codable, Equatable, CaseIterable {
    case claude
    case codex
    case gemini

    var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .gemini: return "Gemini"
        }
    }

    var tint: Color {
        switch self {
        case .claude: return .orange
        case .codex: return .cyan
        case .gemini: return .green
        }
    }
}

enum VibeAgentStatus: String, Codable, Equatable {
    case processing
    case runningTool
    case waitingForApproval
    case waitingForInput
    case completed
    case failed
    case compacting
    case unknown

    var stateLabel: String {
        switch self {
        case .processing: return "Processing"
        case .runningTool: return "Running Tool"
        case .waitingForApproval: return "Permission Request"
        case .waitingForInput: return "Waiting for input"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .compacting: return "Compacting"
        case .unknown: return "Unknown"
        }
    }
}

enum VibeAgentResponseMode: String, Codable, Equatable {
    case socket
    case terminalHandoff
    case none
}

struct VibeAgentEvent: Equatable {
    let agent: VibeAgentKind
    let sessionID: String
    let cwd: String
    let terminal: String
    let event: String
    let status: VibeAgentStatus
    let toolName: String?
    let toolInputSummary: String?
    let approvalID: String?
    let question: String?
    let questionOptions: [String]
    let planMarkdown: String?
    let usageLabel: String?
    let responseMode: VibeAgentResponseMode
    let createdAt: Date

    init(
        agent: VibeAgentKind,
        sessionID: String,
        cwd: String,
        terminal: String = "Terminal",
        event: String,
        status: VibeAgentStatus,
        toolName: String? = nil,
        toolInputSummary: String? = nil,
        approvalID: String? = nil,
        question: String? = nil,
        questionOptions: [String] = [],
        planMarkdown: String? = nil,
        usageLabel: String? = nil,
        responseMode: VibeAgentResponseMode = .none,
        createdAt: Date = Date()
    ) {
        self.agent = agent
        self.sessionID = sessionID
        self.cwd = cwd
        self.terminal = terminal
        self.event = event
        self.status = status
        self.toolName = toolName
        self.toolInputSummary = toolInputSummary
        self.approvalID = approvalID
        self.question = question
        self.questionOptions = questionOptions
        self.planMarkdown = planMarkdown
        self.usageLabel = usageLabel
        self.responseMode = responseMode
        self.createdAt = createdAt
    }
}

struct VibeAgentSessionState: Equatable {
    let id: UUID
    let agent: VibeAgentKind
    let sessionID: String
    var cwd: String
    var terminal: String
    var event: String
    var status: VibeAgentStatus
    var title: String
    var detail: String
    var stateOverride: String?
    var approvalID: String?
    var responseMode: VibeAgentResponseMode
    var lastActivity: Date

    init(event: VibeAgentEvent) {
        id = UUID()
        agent = event.agent
        sessionID = event.sessionID
        cwd = event.cwd
        terminal = event.terminal
        self.event = event.event
        status = event.status
        title = URL(fileURLWithPath: event.cwd).lastPathComponent
        detail = Self.detail(for: event)
        stateOverride = nil
        approvalID = event.approvalID
        responseMode = event.responseMode
        lastActivity = event.createdAt
    }

    mutating func apply(_ event: VibeAgentEvent) {
        cwd = event.cwd
        terminal = event.terminal
        self.event = event.event
        status = event.status
        title = URL(fileURLWithPath: event.cwd).lastPathComponent
        detail = Self.detail(for: event)
        stateOverride = nil
        if let approvalID = event.approvalID {
            self.approvalID = approvalID
        }
        responseMode = event.responseMode
        lastActivity = event.createdAt
    }

    var vibeSession: VibeSession {
        VibeSession(
            id: id,
            agent: agent.displayName,
            terminal: terminal,
            title: title.isEmpty ? agent.displayName : title,
            detail: detail,
            elapsed: "live",
            state: stateOverride ?? status.stateLabel,
            action: action,
            tint: agent.tint,
            agentKind: agent,
            agentSessionID: sessionID,
            approvalID: approvalID,
            responseMode: responseMode
        )
    }

    private var action: VibeSessionAction {
        switch status {
        case .waitingForApproval:
            return responseMode == .socket ? .approval : .jump
        case .completed, .waitingForInput:
            return .jump
        default:
            return .monitor
        }
    }

    private static func detail(for event: VibeAgentEvent) -> String {
        if let toolName = event.toolName {
            if let summary = event.toolInputSummary, !summary.isEmpty {
                return "\(toolName) \(summary)"
            }
            return toolName
        }
        return event.question ?? event.planMarkdown ?? event.event
    }
}

@MainActor
final class VibeAgentStore: ObservableObject {
    static let shared = VibeAgentStore()

    @Published private(set) var dashboard: VibeIslandDashboard = .empty
    @Published private(set) var lastAction = "等待 Agent 事件"
    private var sessions: [String: VibeAgentSessionState] = [:]

    func process(_ event: VibeAgentEvent) {
        let key = "\(event.agent.rawValue):\(event.sessionID)"
        var session = sessions[key] ?? VibeAgentSessionState(event: event)
        session.apply(event)
        sessions[key] = session
        rebuildDashboard()
    }

    func allow(sessionID: UUID?) {
        guard let key = key(for: sessionID), var session = sessions[key] else { return }
        switch session.responseMode {
        case .socket:
            if session.agent == .claude, let approvalID = session.approvalID {
                VibeClaudeHookSocketServer.shared.respondToPermission(toolUseId: approvalID, decision: "allow")
            }
            session.status = .completed
            session.detail = "Approved - click to jump"
            sessions[key] = session
            lastAction = "\(session.agent.displayName) 已批准"
        case .terminalHandoff, .none:
            session.status = .waitingForInput
            session.detail = "需要在终端确认"
            session.stateOverride = "需要终端确认"
            sessions[key] = session
            lastAction = "\(session.agent.displayName) 需要在 Terminal 确认"
        }
        rebuildDashboard()
    }

    func deny(sessionID: UUID?) {
        guard let key = key(for: sessionID), var session = sessions[key] else { return }
        switch session.responseMode {
        case .socket:
            if session.agent == .claude, let approvalID = session.approvalID {
                VibeClaudeHookSocketServer.shared.respondToPermission(toolUseId: approvalID, decision: "deny", reason: "Denied by NotchPaste")
            }
            session.status = .failed
            session.detail = "Denied by user"
            sessions[key] = session
            lastAction = "\(session.agent.displayName) 已拒绝"
        case .terminalHandoff, .none:
            session.status = .waitingForInput
            session.detail = "需要在终端确认"
            session.stateOverride = "需要终端确认"
            sessions[key] = session
            lastAction = "\(session.agent.displayName) 需要在 Terminal 确认"
        }
        rebuildDashboard()
    }

    private func key(for id: UUID?) -> String? {
        guard let id else { return nil }
        return sessions.first { $0.value.id == id }?.key
    }

    private func rebuildDashboard() {
        let ordered = sessions.values.sorted { $0.lastActivity > $1.lastActivity }
        let terminals = Set(ordered.map(\.terminal).filter { !$0.isEmpty })

        dashboard = VibeIslandDashboard(
            supportedAgentCount: VibeAgentKind.allCases.count,
            supportedTerminalCount: max(terminals.count, 1),
            sessions: ordered.map(\.vibeSession),
            question: nil,
            planReview: VibePlanReview(
                title: "Plan Review",
                summary: ordered.isEmpty ? "等待 Claude / Codex / Gemini 事件" : "Agent hooks active",
                points: ordered.isEmpty ? ["安装 hooks", "启动 Agent", "等待事件"] : ["unified store", "agent adapters", "live sessions"]
            ),
            usageMeters: ordered.map {
                VibeUsageMeter(agent: $0.agent.displayName, remaining: 1, label: "live")
            },
            supportedAgents: VibeAgentKind.allCases.map(\.displayName)
        )
    }
}
