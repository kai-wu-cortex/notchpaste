import AppKit
import Carbon.HIToolbox
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
        if sessions.contains(where: { $0.action == .approval || $0.action == .question || $0.needsJumpAttention }) {
            return .needsInteraction
        }

        if sessions.contains(where: { $0.isRunningMonitor }) {
            return .running
        }

        return .idle
    }

    func notchCodeDiff(preferredSessionID: UUID?) -> [VibeCodeDiffLine] {
        if let preferredSessionID,
           let preferred = sessions.first(where: { $0.id == preferredSessionID }),
           !preferred.codeDiff.isEmpty {
            return preferred.codeDiff
        }

        return sessions.first { !$0.codeDiff.isEmpty }?.codeDiff ?? []
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
    let terminalProcessID: Int?
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
    var codeDiff: [VibeCodeDiffLine]
    var questionOptions: [String]
    var history: [VibeSessionEvent]

    init(
        id: UUID = UUID(),
        agent: String,
        terminal: String,
        terminalProcessID: Int? = nil,
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
        claudeToolUseID: String? = nil,
        codeDiff: [VibeCodeDiffLine] = [],
        questionOptions: [String] = [],
        history: [VibeSessionEvent] = []
    ) {
        self.id = id
        self.agent = agent
        self.terminal = terminal
        self.terminalProcessID = terminalProcessID
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
        self.codeDiff = codeDiff
        self.questionOptions = questionOptions
        self.history = history
    }

    var primaryActionTitle: String {
        switch action {
        case .approval: return VibeApprovalAction.allowOnce.title
        case .question: return "Reply"
        case .jump: return "Jump"
        case .monitor: return "Open"
        }
    }

    var approvalActions: [VibeApprovalAction] {
        action == .approval ? VibeApprovalAction.allCases : []
    }

    var secondaryActionTitle: String? {
        action == .approval ? VibeApprovalAction.deny.title : nil
    }

    var needsJumpAttention: Bool {
        guard action == .jump else { return false }
        let terminalHandoffStates = ["Waiting for input", "需要终端确认"]
        return terminalHandoffStates.contains(state)
    }

    var isRunningMonitor: Bool {
        guard action == .monitor else { return false }
        let inactiveStates = [
            "Completed",
            "Failed",
            "Ready",
            "Denied",
            "Approved",
            "Waiting for input",
            "Stop",
            "SessionEnd",
            "Unknown",
            "需要终端确认"
        ]
        return !inactiveStates.contains(state)
    }
}

struct VibeSessionEvent: Identifiable, Equatable {
    enum Kind: Equatable {
        case userInput
        case processing
        case agentOutput
        case permission
        case system
    }

    let id: UUID
    let kind: Kind
    let title: String
    let message: String
    let codeDiff: [VibeCodeDiffLine]
    let timestamp: Date

    init(
        id: UUID = UUID(),
        kind: Kind,
        title: String,
        message: String,
        codeDiff: [VibeCodeDiffLine] = [],
        timestamp: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.message = message
        self.codeDiff = codeDiff
        self.timestamp = timestamp
    }
}

enum VibeSessionAction: String, Codable, Equatable {
    case approval
    case question
    case jump
    case monitor
}

enum VibeApprovalAction: String, CaseIterable, Equatable {
    case deny
    case allowOnce
    case allowAll
    case bypass

    var title: String {
        switch self {
        case .deny: return "Deny"
        case .allowOnce: return "Allow Once"
        case .allowAll: return "Allow All"
        case .bypass: return "Bypass"
        }
    }

    var responseValue: String {
        switch self {
        case .deny: return "denied"
        case .allowOnce: return "allow_once"
        case .allowAll: return "allow_all"
        case .bypass: return "bypass"
        }
    }

    var approvedState: String {
        switch self {
        case .deny: return "Denied"
        case .allowOnce: return "Approved"
        case .allowAll: return "Approved All"
        case .bypass: return "Bypassed"
        }
    }

    var localFeedback: String {
        switch self {
        case .deny: return "已拒绝"
        case .allowOnce: return "已批准一次"
        case .allowAll: return "已全部批准"
        case .bypass: return "已跳过"
        }
    }

    var isDeny: Bool {
        self == .deny
    }

    var backgroundColor: Color {
        switch self {
        case .deny:
            return Color.white.opacity(0.13)
        case .allowOnce:
            return Color.white.opacity(0.92)
        case .allowAll:
            return Color(red: 1.0, green: 0.53, blue: 0.13)
        case .bypass:
            return Color(red: 0.82, green: 0.16, blue: 0.22)
        }
    }

    var pressedBackgroundColor: Color {
        switch self {
        case .deny:
            return Color.white.opacity(0.20)
        case .allowOnce:
            return Color.white.opacity(0.78)
        case .allowAll:
            return Color(red: 0.88, green: 0.43, blue: 0.08)
        case .bypass:
            return Color(red: 0.68, green: 0.12, blue: 0.18)
        }
    }

    var foregroundColor: Color {
        switch self {
        case .deny:
            return .white.opacity(0.84)
        case .allowOnce, .allowAll:
            return .black.opacity(0.88)
        case .bypass:
            return .white.opacity(0.9)
        }
    }
}

struct VibeCodeDiffLine: Equatable {
    enum Style: Equatable {
        case context
        case removed
        case added
    }

    let text: String
    let style: Style

    init(_ text: String, style: Style) {
        self.text = text
        self.style = style
    }
}

enum VibeNativeMode: CaseIterable, Equatable {
    case overview
    case approvals
    case questions
    case jump

    var title: String {
        switch self {
        case .overview: return "总览"
        case .approvals: return "批准"
        case .questions: return "询问"
        case .jump: return "跳回"
        }
    }

    var iconName: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .approvals: return "checkmark.seal"
        case .questions: return "bubble.left.and.bubble.right"
        case .jump: return "arrow.turn.down.right"
        }
    }
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
    let codeDiff: [VibeCodeDiffLine]
    let questionOptions: [String]
    let history: [VibeSessionEvent]
    let approvalActions: [VibeApprovalAction]

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
        codeDiff = session.codeDiff
        questionOptions = session.questionOptions
        history = session.history
        approvalActions = session.approvalActions
    }

    var showsInlineApproval: Bool {
        isWaitingForApproval
    }
}

@MainActor
final class VibeIslandDashboardModel: ObservableObject {
    private static let restoredDashboardLoadQueue = DispatchQueue(label: "com.notchpaste.vibe.dashboard-load", qos: .userInitiated)

    @Published var dashboard: VibeIslandDashboard
    @Published var selectedSessionID: UUID?
    @Published var selectedPermissionSessionID: UUID?
    @Published var selectedQuestionOption: String?
    @Published var mode: VibeNativeMode = .overview
    @Published var lastAction = "等待 Agent 事件"
    private let eventStore: VibeIslandEventStore?
    private let agentStore: VibeAgentStore?
    private let terminalJumper: (VibeSession) -> Void
    private let replySender: (VibeSession, String) -> Bool
    private var cancellables = Set<AnyCancellable>()
    private var didRequestRestoredDashboard = false

    init(
        dashboard: VibeIslandDashboard = .empty,
        eventStore: VibeIslandEventStore? = nil,
        agentStore: VibeAgentStore? = nil,
        terminalJumper: @escaping (VibeSession) -> Void = VibeTerminalJumper.jump,
        replySender: @escaping (VibeSession, String) -> Bool = VibeTerminalReplySender.send
    ) {
        self.dashboard = dashboard
        self.eventStore = eventStore
        self.agentStore = agentStore
        self.terminalJumper = terminalJumper
        self.replySender = replySender

        agentStore?.$dashboard
            .sink { [weak self] dashboard in
                guard let self else { return }
                guard !dashboard.sessions.isEmpty || self.dashboard.sessions.isEmpty else { return }
                self.dashboard = dashboard
            }
            .store(in: &cancellables)

        agentStore?.$lastAction
            .sink { [weak self] action in
                self?.lastAction = action
            }
            .store(in: &cancellables)
    }

    func loadRestoredDashboardIfNeeded() {
        guard !didRequestRestoredDashboard, dashboard.sessions.isEmpty, let eventStore else { return }
        didRequestRestoredDashboard = true

        Self.restoredDashboardLoadQueue.async { [weak eventStore] in
            let restoredDashboard = try? eventStore?.loadDashboard()

            Task { @MainActor [weak self] in
                guard
                    let self,
                    self.dashboard.sessions.isEmpty,
                    let restoredDashboard,
                    !restoredDashboard.sessions.isEmpty
                else {
                    return
                }
                self.dashboard = restoredDashboard
            }
        }
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

    var selectedPermissionRow: VibeNativeSessionRow? {
        guard let selectedPermissionSessionID else { return nil }
        return nativeRows.first { $0.id == selectedPermissionSessionID && $0.showsInlineApproval }
    }

    var pendingInteractionRow: VibeNativeSessionRow? {
        nativeRows.first { $0.showsInlineApproval }
    }

    var visibleRows: [VibeNativeSessionRow] {
        switch mode {
        case .overview:
            return nativeRows
        case .approvals:
            return nativeRows.filter(\.showsInlineApproval)
        case .questions:
            return nativeRows.filter { $0.primaryActionTitle == "Reply" }
        case .jump:
            return nativeRows.filter { $0.primaryActionTitle == "Jump" }
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

    func performApproval(_ action: VibeApprovalAction, sessionID: UUID?) {
        if action.isDeny {
            deny(sessionID: sessionID)
            return
        }

        if let agentStore {
            agentStore.allow(sessionID: sessionID)
        } else {
            updateApproval(
                sessionID: sessionID,
                state: action.approvedState,
                detail: "\(action.title) - click to jump",
                feedback: action.localFeedback
            )
        }
        writeResponse(sessionID: sessionID, action: .allow, value: action.responseValue)
    }

    func reply(_ option: String) {
        selectedQuestionOption = option
        lastAction = "已回答 \(option)"
        writeResponse(sessionID: nil, action: .reply, value: option)
    }

    func submitReply(_ text: String, sessionID: UUID?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, let index = sessionIndex(for: sessionID) else { return }

        let session = dashboard.sessions[index]
        dashboard.sessions[index].history.append(
            VibeSessionEvent(kind: .userInput, title: "你的输入", message: value)
        )
        selectedSessionID = session.id
        if replySender(session, value) {
            lastAction = "已发送给 \(session.agent)"
        } else {
            lastAction = "已复制回复，请在 \(session.terminal) 回车发送"
        }
        writeResponse(sessionID: session.id, action: .reply, value: value)
    }

    func reviewPlan() {
        lastAction = dashboard.planReview.title.isEmpty ? "无审阅计划" : "正在审阅 \(dashboard.planReview.title)"
        writeResponse(sessionID: nil, action: .reviewPlan, value: dashboard.planReview.title)
    }

    func open(sessionID: UUID?) {
        guard let index = sessionIndex(for: sessionID) else { return }
        let session = dashboard.sessions[index]
        selectedSessionID = session.id
        selectedPermissionSessionID = nil
        lastAction = "打开 \(session.agent) 状态"
        writeResponse(sessionID: sessionID, action: .open, value: session.agent)
    }

    func openConversation(sessionID: UUID?) {
        guard let index = sessionIndex(for: sessionID) else { return }
        let session = dashboard.sessions[index]

        if session.action == .approval {
            selectedPermissionSessionID = session.id
            selectedSessionID = nil
            mode = .approvals
        } else {
            selectedPermissionSessionID = nil
            selectedSessionID = session.id
        }

        lastAction = "打开 \(session.agent) 状态"
        writeResponse(sessionID: sessionID, action: .open, value: session.agent)
    }

    func jump(sessionID: UUID?) {
        guard let index = sessionIndex(for: sessionID) else { return }
        let session = dashboard.sessions[index]
        selectedSessionID = session.id
        selectedPermissionSessionID = nil
        lastAction = "跳回 \(session.terminal)"
        terminalJumper(session)
        writeResponse(sessionID: sessionID, action: .jump, value: session.terminal)
    }

    func closeConversation() {
        selectedSessionID = nil
        selectedPermissionSessionID = nil
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

private enum VibeTerminalJumper {
    static func jump(to session: VibeSession) {
        guard let app = app(for: session) else { return }
        app.activate(options: [])
    }

    static func app(for session: VibeSession) -> NSRunningApplication? {
        session.terminalProcessID.flatMap(runningApplicationInProcessTree(startingAt:))
            ?? runningApplication(named: session.terminal)
    }

    private static func runningApplication(named terminal: String) -> NSRunningApplication? {
        let names = candidateNames(for: terminal).map { $0.lowercased() }
        return NSWorkspace.shared.runningApplications.first { app in
            guard let localizedName = app.localizedName?.lowercased() else { return false }
            return names.contains(localizedName)
        }
    }

    private static func runningApplicationInProcessTree(startingAt pid: Int) -> NSRunningApplication? {
        var currentPID = pid
        var visited = Set<Int>()

        for _ in 0..<12 {
            guard currentPID > 1, !visited.contains(currentPID) else { return nil }
            visited.insert(currentPID)

            if let app = NSRunningApplication(processIdentifier: pid_t(currentPID)),
               app.activationPolicy == .regular {
                return app
            }

            guard let parentPID = parentProcessID(for: currentPID) else { return nil }
            currentPID = parentPID
        }

        return nil
    }

    private static func parentProcessID(for pid: Int) -> Int? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-p", String(pid), "-o", "ppid="]
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
        return Int(output)
    }

    private static func candidateNames(for terminal: String) -> [String] {
        switch terminal.lowercased() {
        case "iterm", "iterm2":
            return ["iTerm", "iTerm2"]
        case "terminal", "terminal.app":
            return ["Terminal"]
        case "ghostty":
            return ["Ghostty"]
        case "warp":
            return ["Warp"]
        case "wezterm":
            return ["WezTerm"]
        case "mori":
            return ["Mori", "mori"]
        default:
            return [terminal]
        }
    }
}

enum VibeTerminalReplySender {
    static func send(to session: VibeSession, value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        copyReplyToPasteboard(trimmed)

        guard isAccessibilityTrusted(promptIfNeeded: true),
              let app = VibeTerminalJumper.app(for: session)
        else {
            guard let app = VibeTerminalJumper.app(for: session) else { return false }
            app.activate(options: [])
            return sendWithAppleScript(to: app)
        }

        app.activate(options: [])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            postCommandV()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                postReturn()
            }
        }
        return true
    }

    private static func sendWithAppleScript(to app: NSRunningApplication) -> Bool {
        let target: String
        if let bundleIdentifier = app.bundleIdentifier {
            target = #"application id "\#(bundleIdentifier)""#
        } else if let name = app.localizedName {
            target = #"application "\#(name)""#
        } else {
            return false
        }

        let script = """
        tell \(target) to activate
        delay 0.2
        tell application "System Events"
            keystroke "v" using command down
            delay 0.08
            key code 36
        end tell
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            return true
        } catch {
            return false
        }
    }

    private static func copyReplyToPasteboard(_ value: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }

    private static func isAccessibilityTrusted(promptIfNeeded: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue()
        let options: [CFString: Any] = [key: promptIfNeeded]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    private static func postCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let key = CGKeyCode(kVK_ANSI_V)
        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    private static func postReturn() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let key = CGKeyCode(kVK_Return)
        CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)?.post(tap: .cghidEventTap)
        CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)?.post(tap: .cghidEventTap)
    }
}

struct VibeIslandReplicaView: View {

    @StateObject private var model: VibeIslandDashboardModel
    @State private var replyDraft = ""
    @FocusState private var replyFieldFocused: Bool
    private let onJump: () -> Void

    @MainActor
    init(
        dashboard: VibeIslandDashboard? = nil,
        eventStore: VibeIslandEventStore? = VibeIslandEventStore.defaultStore(),
        agentStore: VibeAgentStore? = nil,
        onJump: @escaping () -> Void = {}
    ) {
        self.onJump = onJump
        let liveAgentStore = agentStore ?? VibeAgentStore.shared
        let initialDashboard = dashboard ?? liveAgentStore.dashboard
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
                if let permissionRow = model.selectedPermissionRow {
                    permissionRequestPage(permissionRow)
                } else if let selectedRow = model.selectedNativeRow {
                    conversationDetail(selectedRow)
                } else if model.nativeRows.isEmpty {
                    emptyState
                } else {
                    modeContent
                }
            }

            if model.selectedNativeRow == nil, model.selectedPermissionRow == nil, let row = model.pendingInteractionRow {
                permissionRequestModal(row)
                    .transition(.scale(scale: 0.92, anchor: .top).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .background(Color.black)
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: model.selectedSessionID)
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: model.selectedPermissionSessionID)
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: model.pendingInteractionRow?.id)
        .onAppear {
            model.loadRestoredDashboardIfNeeded()
        }
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

    private var modeContent: some View {
        VStack(spacing: 8) {
            modeSelector

            if model.visibleRows.isEmpty {
                modeEmptyState
            } else {
                sessionList
            }
        }
    }

    private var modeSelector: some View {
        HStack(spacing: 6) {
            ForEach(VibeNativeMode.allCases, id: \.self) { mode in
                Button {
                    model.mode = mode
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: mode.iconName)
                            .font(.system(size: 10, weight: .semibold))
                        Text(mode.title)
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(model.mode == mode ? .black : .white.opacity(0.64))
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(model.mode == mode ? Color.white.opacity(0.9) : Color.white.opacity(0.06))
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
    }

    private var modeEmptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: model.mode.iconName)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.white.opacity(0.28))

            Text("\(model.mode.title)暂无事件")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.42))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var sessionList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 2) {
                ForEach(model.visibleRows) { row in
                    nativeRow(row)
                }
            }
            .padding(.vertical, 6)
        }
        .scrollBounceBehavior(.basedOnSize)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.025))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
        .padding(.horizontal, 10)
    }

    private func permissionRequestPage(_ row: VibeNativeSessionRow) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                iconButton("chevron.left") {
                    model.closeConversation()
                }

                stateIndicator(for: row)
                    .frame(width: 14)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Permission Request")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.88))

                    Text("\(row.title)  \(row.subtitle)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.34))
                }

                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(TerminalPalette.amber)

                    Text(permissionTitle(for: row))
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundColor(TerminalPalette.amber)

                    Text(permissionPath(for: row))
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.86))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                permissionDiffBlock(row)

                HStack(spacing: 10) {
                    ForEach(row.approvalActions, id: \.self) { action in
                        Button(action.title) {
                            model.performApproval(action, sessionID: row.id)
                        }
                        .buttonStyle(VibeApprovalButtonStyle(action: action, height: 31, cornerRadius: 7))
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.black.opacity(0.95))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(row.tint.opacity(0.18), lineWidth: 1)
            )

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .onAppear {
            replyFieldFocused = true
        }
        .onChange(of: row.id) { _, _ in
            replyFieldFocused = true
        }
    }

    private func conversationDetail(_ row: VibeNativeSessionRow) -> some View {
        VStack(alignment: .leading, spacing: 10) {
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
                VStack(alignment: .leading, spacing: 8) {
                    Text(row.state)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(row.isWaitingForApproval ? TerminalPalette.amber : row.tint)

                    conversationHistoryBlock(row)

                    if !model.lastAction.isEmpty {
                        Text(model.lastAction)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white.opacity(0.34))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 4)
            }
            .frame(maxHeight: .infinity)

            replyComposer(row)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func replyComposer(_ row: VibeNativeSessionRow) -> some View {
        HStack(spacing: 8) {
            TextField("回复 \(row.title)", text: $replyDraft)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
                .focused($replyFieldFocused)
                .onSubmit {
                    submitReply(for: row)
                }

            Button {
                submitReply(for: row)
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(replyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .white.opacity(0.26) : .black)
                    .frame(width: 28, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(replyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.white.opacity(0.06) : row.tint)
                    )
            }
            .buttonStyle(.plain)
            .disabled(replyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.leading, 11)
        .padding(.trailing, 6)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.055))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(row.tint.opacity(0.28), lineWidth: 1)
        )
    }

    private func submitReply(for row: VibeNativeSessionRow) {
        let value = replyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        model.submitReply(value, sessionID: row.id)
        replyDraft = ""
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

    private func conversationHistoryBlock(_ row: VibeNativeSessionRow) -> some View {
        let events = row.history.isEmpty
            ? [VibeSessionEvent(kind: .system, title: "Latest event", message: row.detail.isEmpty ? row.state : row.detail)]
            : row.history

        return VStack(alignment: .leading, spacing: 6) {
            Text("历史记录")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.white.opacity(0.36))

            ForEach(events.suffix(12)) { event in
                HStack(alignment: .top, spacing: 6) {
                    Circle()
                        .fill(historyColor(event.kind, tint: row.tint))
                        .frame(width: 5, height: 5)
                        .padding(.top, 5)

                    VStack(alignment: .leading, spacing: 2) {
                        let diffLines = historyDiffLines(for: event)

                        Text(event.title)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.white.opacity(0.42))

                        Text(historyMessage(for: event, hasDiff: diffLines != nil))
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.84))
                            .lineLimit(diffLines == nil ? 3 : 1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if let lines = diffLines {
                            diffLinesBlock(lines)
                                .padding(.top, 3)
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(row.tint.opacity(0.08))
        )
    }

    private func historyColor(_ kind: VibeSessionEvent.Kind, tint: Color) -> Color {
        switch kind {
        case .userInput: return .white.opacity(0.72)
        case .processing: return tint
        case .agentOutput: return .green
        case .permission: return TerminalPalette.amber
        case .system: return .white.opacity(0.36)
        }
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
                ForEach(row.approvalActions, id: \.self) { action in
                    Button(action.title) {
                        model.performApproval(action, sessionID: row.id)
                    }
                    .buttonStyle(VibeApprovalButtonStyle(action: action, height: 31, cornerRadius: 7))
                }
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

        return diffLinesBlock(lines)
    }

    private func diffLinesBlock(_ lines: [PermissionPreviewLine]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line.text)
                    .foregroundColor(line.color)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(line.background)
            }
        }
        .font(.system(size: 9, weight: .medium, design: .monospaced))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func historyDiffLines(for event: VibeSessionEvent) -> [PermissionPreviewLine]? {
        if !event.codeDiff.isEmpty {
            return event.codeDiff.map { permissionLine(from: $0) }
        }

        if let patchLines = patchPreviewLines(from: event.message), !patchLines.isEmpty {
            return patchLines
        }

        guard event.kind == .permission || event.kind == .processing else { return nil }
        let message = event.message
        guard message.localizedCaseInsensitiveContains("edit")
                || message.localizedCaseInsensitiveContains("old_string")
                || message.localizedCaseInsensitiveContains("new_string")
        else { return nil }

        let oldValue = extractedToolValue(named: "old_string", from: message)
        let newValue = extractedToolValue(named: "new_string", from: message)
        let path = extractedToolValue(named: "file_path", from: message)
            ?? extractedToolValue(named: "path", from: message)

        var lines: [PermissionPreviewLine] = []
        lines.append(
            PermissionPreviewLine(
                path.map { "Edit \($0)" } ?? event.title,
                color: .white.opacity(0.28),
                background: .white.opacity(0.04)
            )
        )

        if let oldValue, !oldValue.isEmpty {
            lines.append(
                PermissionPreviewLine(
                    "- \(singleLinePreview(oldValue))",
                    color: Color(red: 1.0, green: 0.55, blue: 0.5),
                    background: .red.opacity(0.14)
                )
            )
        }

        if let newValue, !newValue.isEmpty {
            lines.append(
                PermissionPreviewLine(
                    "+ \(singleLinePreview(newValue))",
                    color: TerminalPalette.green,
                    background: TerminalPalette.green.opacity(0.10)
                )
            )
        }

        if lines.count == 1 {
            lines.append(contentsOf: [
                PermissionPreviewLine("13 - jwt.verify(token);", color: Color(red: 1.0, green: 0.55, blue: 0.5), background: .red.opacity(0.14)),
                PermissionPreviewLine("13 + if (!token) throw new", color: TerminalPalette.green, background: TerminalPalette.green.opacity(0.10)),
                PermissionPreviewLine("14 + AuthError('missing');", color: TerminalPalette.green, background: TerminalPalette.green.opacity(0.10))
            ])
        }

        return lines
    }

    private func historyMessage(for event: VibeSessionEvent, hasDiff: Bool) -> String {
        guard hasDiff else { return event.message }
        if let commandRange = event.message.range(of: " command:") {
            return String(event.message[..<commandRange.lowerBound]) + " command"
        }
        return event.title
    }

    private func patchPreviewLines(from message: String) -> [PermissionPreviewLine]? {
        guard message.contains("*** Begin Patch") else { return nil }

        let rawLines = message.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let lines = rawLines.compactMap { rawLine -> PermissionPreviewLine? in
            if rawLine.hasPrefix("*** Update File: ") || rawLine.hasPrefix("*** Add File: ") {
                let file = rawLine
                    .replacingOccurrences(of: "*** Update File: ", with: "")
                    .replacingOccurrences(of: "*** Add File: ", with: "")
                return PermissionPreviewLine("Edit \(file)", color: .white.opacity(0.24), background: .white.opacity(0.04))
            }
            if rawLine.hasPrefix("+") {
                return PermissionPreviewLine(rawLine, color: TerminalPalette.green, background: TerminalPalette.green.opacity(0.10))
            }
            if rawLine.hasPrefix("-") {
                return PermissionPreviewLine(rawLine, color: Color(red: 1.0, green: 0.55, blue: 0.5), background: .red.opacity(0.14))
            }
            if rawLine.hasPrefix(" ") {
                return PermissionPreviewLine(rawLine, color: .white.opacity(0.24), background: .white.opacity(0.04))
            }
            return nil
        }

        guard !lines.isEmpty else { return nil }
        return Array(lines.prefix(10))
    }

    private func extractedToolValue(named name: String, from text: String) -> String? {
        guard let range = text.range(of: "\(name): ") else { return nil }
        let start = range.upperBound
        let remaining = text[start...]
        let keys = ["file_path: ", "path: ", "old_string: ", "new_string: ", "command: ", "description: "]
            .filter { !$0.hasPrefix("\(name):") }
        let end = keys.compactMap { remaining.range(of: ", \($0)")?.lowerBound }.min() ?? text.endIndex
        let value = String(text[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func singleLinePreview(_ value: String) -> String {
        let normalized = value
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > 88 else { return normalized }
        return "\(normalized.prefix(85))..."
    }

    private func permissionPreviewLines(for row: VibeNativeSessionRow) -> [PermissionPreviewLine] {
        if !row.codeDiff.isEmpty {
            return row.codeDiff.map { permissionLine(from: $0) }
        }

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

    private func permissionLine(from diffLine: VibeCodeDiffLine) -> PermissionPreviewLine {
        switch diffLine.style {
        case .context:
            return PermissionPreviewLine(diffLine.text, color: .white.opacity(0.24), background: .white.opacity(0.04))
        case .removed:
            return PermissionPreviewLine(diffLine.text, color: Color(red: 1.0, green: 0.55, blue: 0.5), background: .red.opacity(0.14))
        case .added:
            return PermissionPreviewLine(diffLine.text, color: TerminalPalette.green, background: TerminalPalette.green.opacity(0.10))
        }
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
                    model.openConversation(sessionID: row.id)
                }

                ForEach(row.approvalActions, id: \.self) { action in
                    Button(action.title) {
                        model.performApproval(action, sessionID: row.id)
                    }
                    .buttonStyle(VibeApprovalButtonStyle(action: action, height: 26, cornerRadius: 8, fontSize: 10))
                }
            }
        } else {
            HStack(spacing: 6) {
                iconButton("bubble.left") {
                    model.openConversation(sessionID: row.id)
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
        case VibeApprovalAction.allowOnce.title:
            model.performApproval(.allowOnce, sessionID: row.id)
        case "Jump":
            model.jump(sessionID: row.id)
            onJump()
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

private struct VibeApprovalButtonStyle: ButtonStyle {
    let action: VibeApprovalAction
    let height: CGFloat
    let cornerRadius: CGFloat
    var fontSize: CGFloat = 12

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: fontSize, weight: .semibold))
            .foregroundColor(action.foregroundColor)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(configuration.isPressed ? action.pressedBackgroundColor : action.backgroundColor)
            )
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
