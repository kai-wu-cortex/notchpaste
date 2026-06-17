import Foundation
import Testing
@testable import NotchPaste

@MainActor
@Suite("VibeCodexIntegration")
struct VibeCodexIntegrationTests {
    @Test("installer preserves existing hooks and adds NotchPaste Codex hooks")
    func installerAddsCodexHooks() throws {
        let directory = try temporaryDirectory()
        let settingsURL = directory.appendingPathComponent("hooks.json")
        let existing = """
        {
          "hooks": {
            "PreToolUse": [
              {
                "hooks": [
                  { "type": "command", "command": "/existing/hook.sh PreToolUse" }
                ]
              }
            ]
          }
        }
        """
        try existing.write(to: settingsURL, atomically: true, encoding: .utf8)

        try VibeCodexHookInstaller.installIfNeeded(codexDir: directory, socketPath: "/tmp/notchpaste-codex-test.sock")

        let scriptURL = directory.appendingPathComponent("hooks/notchpaste-agent-state.py")
        let script = try String(contentsOf: scriptURL)
        #expect(script.contains("AGENT = \"codex\""))
        #expect(script.contains("/tmp/notchpaste-codex-test.sock"))

        let data = try Data(contentsOf: settingsURL)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let hooks = try #require(json["hooks"] as? [String: Any])
        let preToolUse = try #require(hooks["PreToolUse"] as? [[String: Any]])
        let commands = preToolUse.flatMap { ($0["hooks"] as? [[String: Any]]) ?? [] }
            .compactMap { $0["command"] as? String }

        #expect(commands.contains("/existing/hook.sh PreToolUse"))
        #expect(commands.contains { $0.contains("notchpaste-agent-state.py") })
        #expect(hooks["UserPromptSubmit"] != nil)
        #expect(hooks["Stop"] != nil)
    }

    @Test("Codex hook event maps to terminal handoff dashboard session")
    func codexEventMapsToDashboardSession() {
        let event = VibeCodexHookEvent(
            sessionId: "codex-session",
            cwd: "/Users/kyle/project/api",
            event: "PermissionRequest",
            status: "waiting_for_approval",
            pid: 123,
            tty: "/dev/ttys004",
            tool: "Bash",
            toolInput: ["command": AnyCodable("npm test")],
            toolUseId: "codex-tool-1",
            message: nil
        )

        let store = VibeAgentStore()
        store.process(event.agentEvent)

        let session = try? #require(store.dashboard.sessions.first)
        #expect(session?.agent == "Codex")
        #expect(session?.terminal == "ttys004")
        #expect(session?.state == "Permission Request")
        #expect(session?.action == .jump)
        #expect(session?.responseMode == .terminalHandoff)
        #expect(session?.approvalID == "codex-tool-1")
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("notchpaste-codex-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
