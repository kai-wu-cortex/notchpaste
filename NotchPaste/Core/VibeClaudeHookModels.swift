import Foundation

struct VibeClaudeHookEvent: Codable, Equatable, Sendable {
    let sessionId: String
    let cwd: String
    let event: String
    let status: String
    let pid: Int?
    let tty: String?
    let tool: String?
    let toolInput: [String: AnyCodable]?
    let toolUseId: String?
    let notificationType: String?
    let message: String?
    let questionOptions: [String]?
    let agent: String?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case cwd
        case event
        case status
        case pid
        case tty
        case tool
        case toolInput = "tool_input"
        case toolUseId = "tool_use_id"
        case notificationType = "notification_type"
        case message
        case questionOptions = "question_options"
        case agent
    }

    var expectsResponse: Bool {
        event == "PermissionRequest" && status == "waiting_for_approval"
    }

    private var isQuestionEvent: Bool {
        Self.questionEvents.contains(event)
    }

    private static let questionEvents: Set<String> = [
        "AskUserQuestion",
        "UserQuestion",
        "Question"
    ]
}

struct VibeClaudeHookResponse: Codable, Equatable {
    let decision: String
    let reason: String?
}

extension VibeClaudeHookEvent {
    var agentEvent: VibeAgentEvent {
        agentEvent(resolvedAgent: declaredAgentKind ?? .claude)
    }

    func agentEvent(resolvedAgent: VibeAgentKind) -> VibeAgentEvent {
        let mode: VibeAgentResponseMode
        if resolvedAgent == .claude, expectsResponse {
            mode = .socket
        } else if agentStatus == .waitingForApproval {
            mode = .terminalHandoff
        } else {
            mode = .none
        }

        return VibeAgentEvent(
            agent: resolvedAgent,
            sessionID: sessionId,
            cwd: cwd,
            terminal: displayTerminal,
            terminalProcessID: pid,
            event: event,
            status: agentStatus,
            toolName: tool,
            toolInputSummary: toolInputSummary,
            approvalID: toolUseId,
            question: message,
            questionOptions: questionOptions ?? [],
            codeDiff: VibeAgentCodeDiffBuilder.lines(toolName: tool, toolInput: toolInput),
            responseMode: mode,
            createdAt: Date()
        )
    }

    private var displayTerminal: String {
        guard let tty, !tty.isEmpty else { return "Terminal" }
        return tty.replacingOccurrences(of: "/dev/", with: "")
    }

    var declaredAgentKind: VibeAgentKind? {
        guard let agent = agent?.lowercased() else { return nil }
        if agent.contains("codex") { return .codex }
        if agent.contains("claude") { return .claude }
        if agent.contains("gemini") { return .gemini }
        return nil
    }

    private var agentStatus: VibeAgentStatus {
        if isQuestionEvent { return .waitingForInput }

        switch status {
        case "idle", "ready": return .idle
        case "waiting_for_approval": return .waitingForApproval
        case "waiting_for_input": return .waitingForInput
        case "running_tool": return .runningTool
        case "processing", "starting": return .processing
        case "compacting": return .compacting
        case "ended": return .completed
        default: return .unknown
        }
    }

    private var toolInputSummary: String? {
        if isQuestionEvent, let message, !message.isEmpty {
            return message
        }

        guard let toolInput else { return nil }
        let priority = ["file_path", "path", "old_string", "new_string", "command", "description"]
        let ordered = toolInput.sorted { lhs, rhs in
            let left = priority.firstIndex(of: lhs.key) ?? priority.count
            let right = priority.firstIndex(of: rhs.key) ?? priority.count
            if left == right { return lhs.key < rhs.key }
            return left < right
        }
        return ordered
            .prefix(4)
            .map { "\($0.key): \($0.value.description)" }
            .joined(separator: ", ")
    }
}

struct AnyCodable: Codable, Equatable, @unchecked Sendable {
    let value: AnyHashable

    init(_ value: AnyHashable) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = "null"
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map(\.description).joined(separator: ", ")
        } else if let dictionary = try? container.decode([String: AnyCodable].self) {
            value = dictionary
                .sorted { $0.key < $1.key }
                .map { "\($0.key): \($0.value.description)" }
                .joined(separator: ", ")
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value.base {
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        default:
            try container.encode(description)
        }
    }

    var description: String {
        switch value.base {
        case let bool as Bool:
            return bool ? "true" : "false"
        case let int as Int:
            return String(int)
        case let double as Double:
            return String(double)
        case let string as String:
            return string
        default:
            return String(describing: value.base)
        }
    }

    static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        lhs.description == rhs.description
    }
}
