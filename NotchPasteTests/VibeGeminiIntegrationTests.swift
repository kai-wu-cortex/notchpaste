import Foundation
import Testing
@testable import NotchPaste

@MainActor
@Suite("VibeGeminiIntegration")
struct VibeGeminiIntegrationTests {
    @Test("installer preserves Gemini settings and adds NotchPaste hooks")
    func installerAddsGeminiHooks() throws {
        let directory = try temporaryDirectory()
        let settingsURL = directory.appendingPathComponent("settings.json")
        let existing = """
        {
          "mcpServers": {
            "local": { "command": "node" }
          }
        }
        """
        try existing.write(to: settingsURL, atomically: true, encoding: .utf8)

        try VibeGeminiHookInstaller.installIfNeeded(geminiDir: directory, socketPath: "/tmp/notchpaste-gemini-test.sock")

        let scriptURL = directory.appendingPathComponent("hooks/notchpaste-agent-state.py")
        let script = try String(contentsOf: scriptURL)
        #expect(script.contains("AGENT = \"gemini\""))
        #expect(script.contains("/tmp/notchpaste-gemini-test.sock"))

        let data = try Data(contentsOf: settingsURL)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["mcpServers"] != nil)
        let hooks = try #require(json["hooks"] as? [String: Any])
        #expect(hooks["BeforeTool"] != nil)
        #expect(hooks["AfterTool"] != nil)
        #expect(hooks["PromptSubmitted"] != nil)
    }

    @Test("Gemini hook event maps to dashboard session")
    func geminiEventMapsToDashboardSession() {
        let event = VibeGeminiHookEvent(
            sessionId: "gemini-session",
            cwd: "/Users/kyle/project/search",
            event: "BeforeTool",
            status: "running_tool",
            pid: 456,
            tty: "/dev/ttys005",
            tool: "ShellTool",
            toolInput: ["command": AnyCodable("pnpm lint")],
            toolUseId: nil,
            usageLabel: nil,
            message: nil
        )

        let store = VibeAgentStore()
        store.process(event.agentEvent)

        let session = try? #require(store.dashboard.sessions.first)
        #expect(session?.agent == "Gemini")
        #expect(session?.terminal == "ttys005")
        #expect(session?.state == "Running Tool")
        #expect(session?.action == .monitor)
        #expect(session?.responseMode == VibeAgentResponseMode.none)
        #expect(session?.terminalProcessID == 456)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("notchpaste-gemini-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
