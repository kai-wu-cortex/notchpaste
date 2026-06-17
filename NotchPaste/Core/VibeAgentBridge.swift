import Foundation

final class VibeAgentBridge {
    static let shared = VibeAgentBridge()

    private var started = false

    func start() {
        guard !started else { return }
        started = true

        installHooks()

        VibeClaudeHookSocketServer.shared.start { event in
            Task { @MainActor in
                VibeAgentStore.shared.process(event.agentEvent)
            }
        }

        VibeGenericAgentHookSocketServer.shared.start { event in
            guard let agentEvent = event.agentEvent else { return }
            Task { @MainActor in
                VibeAgentStore.shared.process(agentEvent)
            }
        }
    }

    private func installHooks() {
        do {
            try VibeClaudeHookInstaller.installIfNeeded()
        } catch {
            AppLogger.app.error("Claude hook install failed: \(error.localizedDescription, privacy: .public)")
        }

        do {
            try VibeCodexHookInstaller.installIfNeeded()
        } catch {
            AppLogger.app.error("Codex hook install failed: \(error.localizedDescription, privacy: .public)")
        }

        do {
            try VibeGeminiHookInstaller.installIfNeeded()
        } catch {
            AppLogger.app.error("Gemini hook install failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
