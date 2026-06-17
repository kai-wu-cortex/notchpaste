import Foundation
import SwiftUI

@MainActor
final class VibeClaudeSessionStore: ObservableObject {
    static let shared = VibeClaudeSessionStore()

    @Published private(set) var dashboard: VibeIslandDashboard = .empty
    private var sessions: [String: ClaudeLiveSession] = [:]

    func process(_ event: VibeClaudeHookEvent) {
        if event.status == "ended" {
            sessions.removeValue(forKey: event.sessionId)
            rebuildDashboard()
            return
        }

        var session = sessions[event.sessionId] ?? ClaudeLiveSession(event: event)
        session.apply(event)
        sessions[event.sessionId] = session
        rebuildDashboard()
    }

    func markApproved(sessionID: String, toolUseID: String) {
        VibeClaudeHookSocketServer.shared.respondToPermission(toolUseId: toolUseID, decision: "allow")
        update(sessionID: sessionID, state: "Approved", detail: "Approved - click to jump")
    }

    func markDenied(sessionID: String, toolUseID: String) {
        VibeClaudeHookSocketServer.shared.respondToPermission(toolUseId: toolUseID, decision: "deny", reason: "Denied by NotchPaste")
        update(sessionID: sessionID, state: "Denied", detail: "Denied by user")
    }

    private func update(sessionID: String, state: String, detail: String) {
        guard var session = sessions[sessionID] else { return }
        session.state = state
        session.detail = detail
        session.action = .jump
        sessions[sessionID] = session
        rebuildDashboard()
    }

    private func rebuildDashboard() {
        let liveSessions = sessions.values
            .sorted { $0.lastActivity > $1.lastActivity }
            .map(\.vibeSession)

        dashboard = VibeIslandDashboard(
            supportedAgentCount: 1,
            supportedTerminalCount: 1,
            sessions: liveSessions,
            question: nil,
            planReview: VibePlanReview(title: "", summary: "", points: []),
            usageMeters: liveSessions.isEmpty ? [] : [VibeUsageMeter(agent: "Claude", remaining: 1, label: "live")],
            supportedAgents: ["Claude Code"]
        )
    }
}

private struct ClaudeLiveSession {
    let id: UUID
    let sessionID: String
    var cwd: String
    var terminal: String
    var title: String
    var detail: String
    var state: String
    var action: VibeSessionAction
    var toolUseID: String?
    var lastActivity: Date

    init(event: VibeClaudeHookEvent) {
        id = UUID()
        sessionID = event.sessionId
        cwd = event.cwd
        terminal = Self.displayTerminal(from: event.tty)
        title = URL(fileURLWithPath: event.cwd).lastPathComponent
        detail = Self.detail(for: event)
        state = Self.state(for: event)
        action = Self.action(for: event)
        toolUseID = event.toolUseId
        lastActivity = Date()
    }

    mutating func apply(_ event: VibeClaudeHookEvent) {
        cwd = event.cwd
        terminal = Self.displayTerminal(from: event.tty)
        title = URL(fileURLWithPath: event.cwd).lastPathComponent
        detail = Self.detail(for: event)
        state = Self.state(for: event)
        action = Self.action(for: event)
        if let toolUseId = event.toolUseId {
            toolUseID = toolUseId
        }
        lastActivity = Date()
    }

    var vibeSession: VibeSession {
        VibeSession(
            id: id,
            agent: "Claude",
            terminal: terminal,
            title: title.isEmpty ? "Claude Code" : title,
            detail: detail,
            elapsed: "live",
            state: state,
            action: action,
            tint: action == .approval ? .orange : .cyan,
            claudeSessionID: sessionID,
            claudeToolUseID: toolUseID
        )
    }

    private static func displayTerminal(from tty: String?) -> String {
        guard let tty, !tty.isEmpty else { return "Terminal" }
        return tty.replacingOccurrences(of: "/dev/", with: "")
    }

    private static func state(for event: VibeClaudeHookEvent) -> String {
        switch event.status {
        case "waiting_for_approval": return "Permission Request"
        case "waiting_for_input": return "Waiting for input"
        case "running_tool": return "Running Tool"
        case "compacting": return "Compacting"
        case "processing": return "Processing"
        default: return event.status.isEmpty ? event.event : event.status
        }
    }

    private static func action(for event: VibeClaudeHookEvent) -> VibeSessionAction {
        event.expectsResponse ? .approval : .monitor
    }

    private static func detail(for event: VibeClaudeHookEvent) -> String {
        if let tool = event.tool {
            let input = event.toolInput?
                .sorted { $0.key < $1.key }
                .prefix(2)
                .map { "\($0.key): \($0.value.description)" }
                .joined(separator: ", ") ?? ""
            return input.isEmpty ? tool : "\(tool) \(input)"
        }
        return event.message ?? event.event
    }
}

final class VibeClaudeBridge {
    static let shared = VibeClaudeBridge()

    private var started = false

    func start() {
        guard !started else { return }
        started = true

        do {
            try VibeClaudeHookInstaller.installIfNeeded()
        } catch {
            AppLogger.app.error("Vibe hook install failed: \(error.localizedDescription, privacy: .public)")
        }

        VibeClaudeHookSocketServer.shared.start { event in
            Task { @MainActor in
                VibeAgentStore.shared.process(event.agentEvent)
            }
        }
    }
}
