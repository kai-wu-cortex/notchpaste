import Foundation

struct VibeGeminiHookEvent: Codable, Equatable, Sendable {
    let sessionId: String
    let cwd: String
    let event: String
    let status: String
    let pid: Int?
    let tty: String?
    let tool: String?
    let toolInput: [String: AnyCodable]?
    let toolUseId: String?
    let usageLabel: String?
    let message: String?
    let questionOptions: [String]?

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
        case usageLabel = "usage_label"
        case message
        case questionOptions = "question_options"
    }
}

extension VibeGeminiHookEvent {
    var agentEvent: VibeAgentEvent {
        VibeAgentEvent(
            agent: .gemini,
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
            usageLabel: usageLabel,
            codeDiff: VibeAgentCodeDiffBuilder.lines(toolName: tool, toolInput: toolInput),
            responseMode: agentStatus == .waitingForApproval ? .terminalHandoff : .none,
            createdAt: Date()
        )
    }

    private var displayTerminal: String {
        guard let tty, !tty.isEmpty else { return "Terminal" }
        return tty.replacingOccurrences(of: "/dev/", with: "")
    }

    private var agentStatus: VibeAgentStatus {
        switch status {
        case "waiting_for_approval": return .waitingForApproval
        case "waiting_for_input": return .waitingForInput
        case "running_tool": return .runningTool
        case "processing", "starting": return .processing
        case "compacting": return .compacting
        case "ended", "completed": return .completed
        case "failed", "error": return .failed
        default: return .unknown
        }
    }

    private var toolInputSummary: String? {
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
