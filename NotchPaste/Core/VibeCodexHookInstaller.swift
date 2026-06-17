import Foundation

enum VibeCodexHookInstaller {
    static let defaultSocketPath = "/tmp/notchpaste-agent.sock"

    static func installIfNeeded(
        codexDir: URL = resolvedCodexDirectory(),
        socketPath: String = defaultSocketPath
    ) throws {
        let hooksDir = codexDir.appendingPathComponent("hooks", isDirectory: true)
        let scriptURL = hooksDir.appendingPathComponent("notchpaste-agent-state.py")

        try FileManager.default.createDirectory(at: hooksDir, withIntermediateDirectories: true)
        try scriptContents(socketPath: socketPath).write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        try updateHooks(codexDir: codexDir, scriptURL: scriptURL)
    }

    static func resolvedCodexDirectory() -> URL {
        if let envDir = ProcessInfo.processInfo.environment["CODEX_HOME"], !envDir.isEmpty {
            return URL(fileURLWithPath: (envDir as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
    }

    private static func updateHooks(codexDir: URL, scriptURL: URL) throws {
        let settingsURL = codexDir.appendingPathComponent("hooks.json")
        var json: [String: Any] = [:]
        if let data = try? Data(contentsOf: settingsURL),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            json = existing
        }

        var hooks = json["hooks"] as? [String: Any] ?? [:]
        hooks = removeExistingNotchPasteHooks(from: hooks)

        let commandHook = [["type": "command", "command": "python3 \(shellQuote(scriptURL.path))"]]
        let entries = [["hooks": commandHook]]
        for event in ["UserPromptSubmit", "PreToolUse", "PostToolUse", "PermissionRequest", "Notification", "Stop", "SessionStart", "SessionEnd"] {
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
            let filtered = entries.compactMap { entry -> [String: Any]? in
                guard var hookEntries = entry["hooks"] as? [[String: Any]] else { return entry }
                hookEntries.removeAll { hook in
                    let command = hook["command"] as? String ?? ""
                    return command.contains("notchpaste-agent-state.py")
                }
                guard !hookEntries.isEmpty else { return nil }
                var updated = entry
                updated["hooks"] = hookEntries
                return updated
            }
            if !filtered.isEmpty {
                cleaned[event] = filtered
            }
        }
        return cleaned
    }

    static func scriptContents(socketPath: String) -> String {
        VibeGenericAgentHookScript.contents(agent: "codex", socketPath: socketPath)
    }

    private static func shellQuote(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
