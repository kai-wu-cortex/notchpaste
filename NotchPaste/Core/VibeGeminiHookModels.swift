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
    let message: String?

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
        case message
    }
}

extension VibeGeminiHookEvent {
    var agentEvent: VibeAgentEvent {
        VibeAgentEvent(
            agent: .gemini,
            sessionID: sessionId,
            cwd: cwd,
            terminal: displayTerminal,
            event: event,
            status: agentStatus,
            toolName: tool,
            toolInputSummary: toolInputSummary,
            approvalID: toolUseId,
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
        return toolInput
            .sorted { $0.key < $1.key }
            .prefix(2)
            .map { "\($0.key): \($0.value.description)" }
            .joined(separator: ", ")
    }
}
