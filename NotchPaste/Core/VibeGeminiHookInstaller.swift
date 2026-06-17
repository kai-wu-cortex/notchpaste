import Foundation

enum VibeGeminiHookInstaller {
    static let defaultSocketPath = "/tmp/notchpaste-agent.sock"

    static func installIfNeeded(
        geminiDir: URL = resolvedGeminiDirectory(),
        socketPath: String = defaultSocketPath
    ) throws {
        let hooksDir = geminiDir.appendingPathComponent("hooks", isDirectory: true)
        let scriptURL = hooksDir.appendingPathComponent("notchpaste-agent-state.py")

        try FileManager.default.createDirectory(at: hooksDir, withIntermediateDirectories: true)
        try scriptContents(socketPath: socketPath).write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        try updateSettings(geminiDir: geminiDir, scriptURL: scriptURL)
    }

    static func resolvedGeminiDirectory() -> URL {
        if let envDir = ProcessInfo.processInfo.environment["GEMINI_HOME"], !envDir.isEmpty {
            return URL(fileURLWithPath: (envDir as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".gemini", isDirectory: true)
    }

    private static func updateSettings(geminiDir: URL, scriptURL: URL) throws {
        let settingsURL = geminiDir.appendingPathComponent("settings.json")
        var json: [String: Any] = [:]
        if let data = try? Data(contentsOf: settingsURL),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            json = existing
        }

        var hooks = json["hooks"] as? [String: Any] ?? [:]
        hooks = removeExistingNotchPasteHooks(from: hooks)

        let command = "python3 \(shellQuote(scriptURL.path))"
        let entries = [["command": command]]
        for event in ["PromptSubmitted", "BeforeTool", "AfterTool", "PermissionRequest", "Notification", "SessionStart", "SessionEnd"] {
            let existing = hooks[event] as? [[String: Any]] ?? []
            hooks[event] = existing + entries
        }

        json["hooks"] = hooks
        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: settingsURL, options: .atomic)
    }

    private static func removeExistingNotchPasteHooks(from hooks: [String: Any]) -> [String: Any] {
        var cleaned: [String: Any] = [:]
        for (event, value) in hooks {
            guard let entries = value as? [[String: Any]] else {
                cleaned[event] = value
                continue
            }
            let filtered = entries.filter { entry in
                let command = entry["command"] as? String ?? ""
                return !command.contains("notchpaste-agent-state.py")
            }
            if !filtered.isEmpty {
                cleaned[event] = filtered
            }
        }
        return cleaned
    }

    static func scriptContents(socketPath: String) -> String {
        VibeGenericAgentHookScript.contents(agent: "gemini", socketPath: socketPath)
    }

    private static func shellQuote(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
