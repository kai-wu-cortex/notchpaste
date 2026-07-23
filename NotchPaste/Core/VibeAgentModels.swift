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
    case idle
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
        case .idle: return "Ready"
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

enum VibeAgentProcessResolver {
    static func kind(startingAt pid: Int?) -> VibeAgentKind? {
        guard var currentPID = pid else { return nil }
        var visited = Set<Int>()

        for _ in 0..<12 {
            guard currentPID > 1, !visited.contains(currentPID) else { return nil }
            visited.insert(currentPID)

            if let commandLine = commandLine(for: currentPID),
               let kind = kind(fromCommandLine: commandLine) {
                return kind
            }

            guard let parentPID = parentProcessID(for: currentPID) else { return nil }
            currentPID = parentPID
        }

        return nil
    }

    static func kind(fromCommandLine commandLine: String) -> VibeAgentKind? {
        let tokens = commandLine
            .lowercased()
            .split { $0 == " " || $0 == "\t" || $0 == "/" }
            .map(String.init)

        if tokens.contains("codex") { return .codex }
        if tokens.contains("claude") { return .claude }
        if tokens.contains("gemini") { return .gemini }
        return nil
    }

    private static func commandLine(for pid: Int) -> String? {
        processOutput(arguments: ["-p", String(pid), "-o", "args="])
    }

    private static func parentProcessID(for pid: Int) -> Int? {
        processOutput(arguments: ["-p", String(pid), "-o", "ppid="]).flatMap(Int.init)
    }

    private static func processOutput(arguments: [String]) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return output.isEmpty ? nil : output
    }
}

struct VibeAgentEvent: Equatable {
    let agent: VibeAgentKind
    let sessionID: String
    let cwd: String
    let terminal: String
    let terminalProcessID: Int?
    let event: String
    let status: VibeAgentStatus
    let toolName: String?
    let toolInputSummary: String?
    let approvalID: String?
    let question: String?
    let questionOptions: [String]
    let planMarkdown: String?
    let usageLabel: String?
    let codeDiff: [VibeCodeDiffLine]
    let responseMode: VibeAgentResponseMode
    let createdAt: Date

    init(
        agent: VibeAgentKind,
        sessionID: String,
        cwd: String,
        terminal: String = "Terminal",
        terminalProcessID: Int? = nil,
        event: String,
        status: VibeAgentStatus,
        toolName: String? = nil,
        toolInputSummary: String? = nil,
        approvalID: String? = nil,
        question: String? = nil,
        questionOptions: [String] = [],
        planMarkdown: String? = nil,
        usageLabel: String? = nil,
        codeDiff: [VibeCodeDiffLine] = [],
        responseMode: VibeAgentResponseMode = .none,
        createdAt: Date = Date()
    ) {
        self.agent = agent
        self.sessionID = sessionID
        self.cwd = cwd
        self.terminal = terminal
        self.terminalProcessID = terminalProcessID
        self.event = event
        self.status = status
        self.toolName = toolName
        self.toolInputSummary = toolInputSummary
        self.approvalID = approvalID
        self.question = question
        self.questionOptions = questionOptions
        self.planMarkdown = planMarkdown
        self.usageLabel = usageLabel
        self.codeDiff = codeDiff
        self.responseMode = responseMode
        self.createdAt = createdAt
    }
}

enum VibeAgentCodeDiffBuilder {
    static func lines(toolName: String?, toolInput: [String: AnyCodable]?) -> [VibeCodeDiffLine] {
        guard let toolInput else { return [] }
        let lowerTool = toolName?.lowercased() ?? ""
        let command = value(for: ["command"], in: toolInput)

        if let patchLines = patchLines(from: command), !patchLines.isEmpty {
            return patchLines
        }

        guard lowerTool.contains("edit")
                || lowerTool.contains("write")
                || lowerTool.contains("apply_patch")
                || toolInput["old_string"] != nil
                || toolInput["new_string"] != nil
                || command?.contains("*** Begin Patch") == true
        else { return [] }

        let path = value(for: ["file_path", "path", "relative_path"], in: toolInput)
        let oldValue = value(for: ["old_string", "old", "before"], in: toolInput)
        let newValue = value(for: ["new_string", "new", "after", "content"], in: toolInput)

        var lines: [VibeCodeDiffLine] = []
        if let path, !path.isEmpty {
            lines.append(VibeCodeDiffLine("Edit \(path)", style: .context))
        }

        if let oldValue, !oldValue.isEmpty {
            lines.append(contentsOf: formattedLines(oldValue, prefix: "-", style: .removed))
        }

        if let newValue, !newValue.isEmpty {
            lines.append(contentsOf: formattedLines(newValue, prefix: "+", style: .added))
        }

        return lines
    }

    private static func patchLines(from command: String?) -> [VibeCodeDiffLine]? {
        guard let command, command.contains("*** Begin Patch") else { return nil }

        var result: [VibeCodeDiffLine] = []
        for rawLine in command.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if rawLine.hasPrefix("*** Update File: ") || rawLine.hasPrefix("*** Add File: ") {
                let file = rawLine
                    .replacingOccurrences(of: "*** Update File: ", with: "")
                    .replacingOccurrences(of: "*** Add File: ", with: "")
                result.append(VibeCodeDiffLine("Edit \(file)", style: .context))
            } else if rawLine.hasPrefix("+") {
                result.append(VibeCodeDiffLine(rawLine, style: .added))
            } else if rawLine.hasPrefix("-") {
                result.append(VibeCodeDiffLine(rawLine, style: .removed))
            } else if rawLine.hasPrefix(" ") {
                result.append(VibeCodeDiffLine(rawLine, style: .context))
            }
        }

        return result.isEmpty ? nil : Array(result.prefix(24))
    }

    private static func value(for keys: [String], in toolInput: [String: AnyCodable]) -> String? {
        keys.compactMap { toolInput[$0]?.description }.first {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private static func formattedLines(_ value: String, prefix: String, style: VibeCodeDiffLine.Style) -> [VibeCodeDiffLine] {
        let rawLines = value
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        let visibleLines = Array(rawLines.prefix(6))
        var result = visibleLines.map { line in
            VibeCodeDiffLine("\(prefix) \(line)", style: style)
        }
        if rawLines.count > visibleLines.count {
            result.append(VibeCodeDiffLine("\(prefix) ...", style: style))
        }
        return result
    }
}

struct VibeAgentSessionState: Equatable {
    let id: UUID
    let agent: VibeAgentKind
    let sessionID: String
    var cwd: String
    var terminal: String
    var terminalProcessID: Int?
    var event: String
    var status: VibeAgentStatus
    var title: String
    var detail: String
    var stateOverride: String?
    var approvalID: String?
    var responseMode: VibeAgentResponseMode
    var usageLabel: String?
    var codeDiff: [VibeCodeDiffLine]
    var questionOptions: [String]
    var history: [VibeSessionEvent]
    var lastActivity: Date

    init(event: VibeAgentEvent) {
        id = UUID()
        agent = event.agent
        sessionID = event.sessionID
        cwd = event.cwd
        terminal = event.terminal
        terminalProcessID = event.terminalProcessID
        self.event = event.event
        status = Self.normalizedStatus(for: event)
        title = URL(fileURLWithPath: event.cwd).lastPathComponent
        detail = Self.detail(for: event)
        stateOverride = nil
        approvalID = event.approvalID
        responseMode = event.responseMode
        usageLabel = event.usageLabel
        codeDiff = event.codeDiff
        questionOptions = event.questionOptions
        history = [Self.historyEvent(for: event)]
        lastActivity = event.createdAt
    }

    mutating func apply(_ event: VibeAgentEvent) {
        cwd = event.cwd
        terminal = event.terminal
        terminalProcessID = event.terminalProcessID
        self.event = event.event
        status = Self.normalizedStatus(for: event)
        title = URL(fileURLWithPath: event.cwd).lastPathComponent
        detail = Self.detail(for: event)
        stateOverride = nil
        if let approvalID = event.approvalID {
            self.approvalID = approvalID
        }
        responseMode = event.responseMode
        if let usageLabel = event.usageLabel {
            self.usageLabel = usageLabel
        }
        if !event.codeDiff.isEmpty {
            codeDiff = event.codeDiff
        }
        if !event.questionOptions.isEmpty {
            questionOptions = event.questionOptions
        }
        appendHistory(event)
        lastActivity = event.createdAt
    }

    var vibeSession: VibeSession {
        VibeSession(
            id: id,
            agent: agent.displayName,
            terminal: terminal,
            terminalProcessID: terminalProcessID,
            title: title.isEmpty ? agent.displayName : title,
            detail: detail,
            elapsed: elapsedLabel,
            state: stateOverride ?? status.stateLabel,
            action: action,
            tint: agent.tint,
            agentKind: agent,
            agentSessionID: sessionID,
            approvalID: approvalID,
            responseMode: responseMode,
            codeDiff: codeDiff,
            questionOptions: questionOptions,
            history: history
        )
    }

    var countsAsActiveForNotch: Bool {
        switch status {
        case .processing, .runningTool, .waitingForApproval, .compacting:
            return true
        case .waitingForInput:
            return action == .question || action == .jump
        case .idle, .completed, .failed, .unknown:
            return false
        }
    }

    private var elapsedLabel: String {
        switch status {
        case .idle:
            return ""
        case .completed:
            return "done"
        case .failed:
            return "failed"
        case .unknown:
            return ""
        default:
            return usageLabel ?? "live"
        }
    }

    private var action: VibeSessionAction {
        switch status {
        case .waitingForApproval:
            return responseMode == .socket ? .approval : .jump
        case .waitingForInput where Self.isQuestionEvent(event):
            return .question
        case .waitingForInput where !questionOptions.isEmpty:
            return .question
        case .waitingForInput:
            return .jump
        case .completed, .failed:
            return .monitor
        default:
            return .monitor
        }
    }

    private static func isQuestionEvent(_ event: String) -> Bool {
        ["AskUserQuestion", "UserQuestion", "Question"].contains(event)
    }

    private static func normalizedStatus(for event: VibeAgentEvent) -> VibeAgentStatus {
        switch event.event {
        case "SessionStart":
            return .idle
        case "Stop", "SessionEnd":
            return .completed
        case "StopFailure":
            return .failed
        default:
            if event.event == "Notification",
               event.status == .waitingForInput,
               isStopMessage(event.question) {
                return .completed
            }
            if event.event == "UserPromptSubmit",
               event.agent == .codex,
               isCodexAmbientSuggestionPrompt(event.question) {
                return .idle
            }
            return event.status
        }
    }

    private static func isStopMessage(_ message: String?) -> Bool {
        let value = message?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return value == "stop" || value == "sessionend" || value == "session end"
    }

    private static func isCodexAmbientSuggestionPrompt(_ message: String?) -> Bool {
        let value = message?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return value?.contains("codex ambient suggestions") == true
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

    private mutating func appendHistory(_ event: VibeAgentEvent) {
        let item = Self.historyEvent(for: event)
        guard history.last?.message != item.message || history.last?.title != item.title else { return }
        history.append(item)
        if history.count > 40 {
            history.removeFirst(history.count - 40)
        }
    }

    private static func historyEvent(for event: VibeAgentEvent) -> VibeSessionEvent {
        let detail = detail(for: event)
        let kind: VibeSessionEvent.Kind
        let title: String

        switch event.event {
        case "UserPromptSubmit", "PromptSubmitted":
            kind = .userInput
            title = "你的输入"
        case "Notification", "Stop", "SessionEnd":
            kind = .agentOutput
            title = "Agent 输出"
        case "PermissionRequest", "ApprovalRequest":
            kind = .permission
            title = "权限请求"
        case "PreToolUse", "PostToolUse", "BeforeTool", "AfterTool":
            kind = .processing
            title = "处理记录"
        default:
            kind = event.status == .waitingForInput || event.status == .completed ? .agentOutput : .system
            title = event.status == .processing || event.status == .runningTool ? "处理记录" : "事件"
        }

        return VibeSessionEvent(
            kind: kind,
            title: title,
            message: detail.isEmpty ? event.status.stateLabel : detail,
            codeDiff: event.codeDiff,
            timestamp: event.createdAt
        )
    }
}

final class VibeDashboardSnapshotWriter {
    private let store: VibeIslandDashboardSnapshotStore?
    private let delay: TimeInterval
    private let queue: DispatchQueue
    private let lock = NSLock()
    private var pendingWork: DispatchWorkItem?

    init(
        store: VibeIslandDashboardSnapshotStore?,
        delay: TimeInterval = 0.25,
        queue: DispatchQueue = DispatchQueue(label: "com.notchpaste.vibe.snapshot", qos: .utility)
    ) {
        self.store = store
        self.delay = delay
        self.queue = queue
    }

    deinit {
        lock.lock()
        pendingWork?.cancel()
        lock.unlock()
    }

    func schedule(_ dashboard: VibeIslandDashboard) {
        guard let store else { return }

        if delay <= 0 {
            try? store.save(dashboard)
            return
        }

        let work = DispatchWorkItem { [weak store] in
            try? store?.save(dashboard)
        }

        lock.lock()
        pendingWork?.cancel()
        pendingWork = work
        lock.unlock()

        queue.asyncAfter(deadline: .now() + delay, execute: work)
    }
}

@MainActor
final class VibeAgentStore: ObservableObject {
    static let shared = VibeAgentStore(
        snapshotStore: VibeIslandEventStore.defaultStore(),
        dashboardPublishDelay: 0.08
    )

    @Published private(set) var dashboard: VibeIslandDashboard = .empty
    @Published private(set) var lastAction = "等待 Agent 事件"
    private var sessions: [String: VibeAgentSessionState] = [:]
    private let snapshotWriter: VibeDashboardSnapshotWriter
    private let dashboardPublishDelay: TimeInterval
    private var pendingDashboardPublishWork: DispatchWorkItem?

    init(
        snapshotStore: VibeIslandDashboardSnapshotStore? = nil,
        snapshotSaveDelay: TimeInterval = 0.25,
        dashboardPublishDelay: TimeInterval = 0
    ) {
        self.dashboardPublishDelay = dashboardPublishDelay
        snapshotWriter = VibeDashboardSnapshotWriter(store: snapshotStore, delay: snapshotSaveDelay)
    }

    deinit {
        pendingDashboardPublishWork?.cancel()
    }

    func process(_ event: VibeAgentEvent) {
        removeStaleMismatchedSessions(for: event)
        let key = "\(event.agent.rawValue):\(event.sessionID)"
        var session = sessions[key] ?? VibeAgentSessionState(event: event)
        session.apply(event)
        sessions[key] = session

        if event.requiresImmediateDashboardPublish {
            publishDashboardNow()
        } else {
            scheduleDashboardPublish()
        }
    }

    private func removeStaleMismatchedSessions(for event: VibeAgentEvent) {
        let incomingWorkspace = normalizedWorkspace(event.cwd)
        let staleKeys = sessions.compactMap { key, session -> String? in
            guard session.agent != event.agent else { return nil }
            guard session.sessionID == event.sessionID
                || (normalizedWorkspace(session.cwd) == incomingWorkspace && session.terminal == event.terminal)
            else { return nil }
            return key
        }
        staleKeys.forEach { sessions.removeValue(forKey: $0) }
    }

    private func normalizedWorkspace(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
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
        publishDashboardNow()
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
        publishDashboardNow()
    }

    func answerQuestion(sessionID: UUID?, option: String, deliveredToTerminal: Bool) {
        guard let key = key(for: sessionID), var session = sessions[key] else { return }
        session.status = .waitingForInput
        session.stateOverride = "已回答"
        session.detail = "Answered \(option)"
        session.history.append(
            VibeSessionEvent(kind: .userInput, title: "你的输入", message: option)
        )
        sessions[key] = session
        lastAction = deliveredToTerminal
            ? "\(session.agent.displayName) 已回答 \(option)"
            : "已复制 \(option)，请在 \(session.terminal) 回车发送"
        publishDashboardNow()
    }

    private func key(for id: UUID?) -> String? {
        guard let id else { return nil }
        return sessions.first { $0.value.id == id }?.key
    }

    private func scheduleDashboardPublish() {
        guard dashboardPublishDelay > 0 else {
            publishDashboardNow()
            return
        }

        pendingDashboardPublishWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.publishDashboardNow()
            }
        }
        pendingDashboardPublishWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + dashboardPublishDelay, execute: work)
    }

    private func publishDashboardNow() {
        pendingDashboardPublishWork?.cancel()
        pendingDashboardPublishWork = nil

        let ordered = sessions.values.sorted { $0.lastActivity > $1.lastActivity }
        let terminals = Set(ordered.map(\.terminal).filter { !$0.isEmpty })

        let nextDashboard = VibeIslandDashboard(
            supportedAgentCount: VibeAgentKind.allCases.count,
            supportedTerminalCount: max(terminals.count, 1),
            sessions: ordered.map(\.vibeSession),
            question: nil,
            planReview: VibePlanReview(title: "", summary: "", points: []),
            usageMeters: usageMeters(from: ordered),
            supportedAgents: VibeAgentKind.allCases.map(\.displayName)
        )
        dashboard = nextDashboard
        snapshotWriter.schedule(nextDashboard)
    }

    private func usageMeters(from ordered: [VibeAgentSessionState]) -> [VibeUsageMeter] {
        VibeAgentKind.allCases.compactMap { agent in
            guard let session = ordered.first(where: { $0.agent == agent && $0.countsAsActiveForNotch }) else {
                return nil
            }
            let label = session.usageLabel ?? "live"
            return VibeUsageMeter(agent: agent.displayName, remaining: remaining(from: label), label: label)
        }
    }

    private func remaining(from label: String) -> Double {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix("%"),
           let value = Double(trimmed.dropLast()) {
            return min(max(value / 100, 0), 1)
        }
        return 1
    }
}

private extension VibeAgentEvent {
    var requiresImmediateDashboardPublish: Bool {
        switch status {
        case .processing, .runningTool, .compacting:
            return false
        case .idle, .waitingForApproval, .waitingForInput, .completed, .failed, .unknown:
            return true
        }
    }
}
