import Foundation

enum VibeClaudeHookInstaller {
    static let defaultSocketPath = "/tmp/claude-island.sock"

    static func installIfNeeded(
        claudeDir: URL = resolvedClaudeDirectory(),
        socketPath: String = defaultSocketPath
    ) throws {
        let hooksDir = claudeDir.appendingPathComponent("hooks", isDirectory: true)
        let scriptURL = hooksDir.appendingPathComponent("claude-island-state.py")

        try FileManager.default.createDirectory(at: hooksDir, withIntermediateDirectories: true)
        try scriptContents(socketPath: socketPath).write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        try updateSettings(claudeDir: claudeDir, scriptURL: scriptURL)
    }

    static func isInstalled(claudeDir: URL = resolvedClaudeDirectory()) throws -> Bool {
        let settingsURL = claudeDir.appendingPathComponent("settings.json")
        guard let data = try? Data(contentsOf: settingsURL),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any] else {
            return false
        }

        return hooks.values.contains { value in
            guard let entries = value as? [[String: Any]] else { return false }
            return entries.contains { entry in
                guard let hookEntries = entry["hooks"] as? [[String: Any]] else { return false }
                return hookEntries.contains { hook in
                    (hook["command"] as? String)?.contains("claude-island-state.py") == true
                }
            }
        }
    }

    static func resolvedClaudeDirectory() -> URL {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser

        if let envDir = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"] {
            let expanded = (envDir as NSString).expandingTildeInPath
            if fm.fileExists(atPath: expanded) {
                return URL(fileURLWithPath: expanded)
            }
        }

        let configDir = home.appendingPathComponent(".config/claude", isDirectory: true)
        if fm.fileExists(atPath: configDir.appendingPathComponent("projects").path) {
            return configDir
        }

        return home.appendingPathComponent(".claude", isDirectory: true)
    }

    private static func updateSettings(claudeDir: URL, scriptURL: URL) throws {
        let settingsURL = claudeDir.appendingPathComponent("settings.json")
        var json: [String: Any] = [:]
        if let data = try? Data(contentsOf: settingsURL),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            json = existing
        }

        var hooks = json["hooks"] as? [String: Any] ?? [:]
        hooks = removeExistingVibeHooks(from: hooks)

        let command = "python3 \(shellQuote(scriptURL.path))"
        let commandHook = [["type": "command", "command": command]]
        let commandHookWithTimeout = [["type": "command", "command": command, "timeout": 86400]] as [[String: Any]]
        let withMatcher = [["matcher": "*", "hooks": commandHook]]
        let withMatcherAndTimeout = [["matcher": "*", "hooks": commandHookWithTimeout]]
        let withoutMatcher = [["hooks": commandHook]]
        let preCompact = [
            ["matcher": "auto", "hooks": commandHook],
            ["matcher": "manual", "hooks": commandHook]
        ]

        let eventConfigs: [(String, [[String: Any]])] = [
            ("UserPromptSubmit", withoutMatcher),
            ("PreToolUse", withMatcher),
            ("PostToolUse", withMatcher),
            ("PermissionRequest", withMatcherAndTimeout),
            ("Notification", withMatcher),
            ("Stop", withoutMatcher),
            ("SubagentStop", withoutMatcher),
            ("SessionStart", withoutMatcher),
            ("SessionEnd", withoutMatcher),
            ("PreCompact", preCompact)
        ]

        for (event, config) in eventConfigs {
            let existing = hooks[event] as? [[String: Any]] ?? []
            hooks[event] = existing + config
        }

        json["hooks"] = hooks
        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: settingsURL, options: .atomic)
    }

    private static func removeExistingVibeHooks(from hooks: [String: Any]) -> [String: Any] {
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
                    return command.contains("claude-island-state.py")
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
        """
        #!/usr/bin/env python3
        import json
        import os
        import socket
        import subprocess
        import sys

        SOCKET_PATH = "\(socketPath)"
        TIMEOUT_SECONDS = 300

        def get_tty():
            try:
                result = subprocess.run(["ps", "-p", str(os.getppid()), "-o", "tty="], capture_output=True, text=True, timeout=2)
                tty = result.stdout.strip()
                if tty and tty not in ("??", "-"):
                    return tty if tty.startswith("/dev/") else "/dev/" + tty
            except Exception:
                pass
            return None

        def process_output(args):
            try:
                result = subprocess.run(args, capture_output=True, text=True, timeout=2)
                return result.stdout.strip()
            except Exception:
                return ""

        def detect_agent():
            pid = os.getppid()
            seen = set()
            for _ in range(12):
                if not pid or pid <= 1 or pid in seen:
                    break
                seen.add(pid)
                command = process_output(["ps", "-p", str(pid), "-o", "args="]).lower()
                tokens = command.replace("/", " ").replace("\\t", " ").split()
                if "codex" in tokens:
                    return "codex"
                if "gemini" in tokens:
                    return "gemini"
                if "claude" in tokens:
                    return "claude"
                parent = process_output(["ps", "-p", str(pid), "-o", "ppid="])
                try:
                    pid = int(parent)
                except Exception:
                    break
            return "claude"

        def send_event(state):
            try:
                sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                sock.settimeout(TIMEOUT_SECONDS)
                sock.connect(SOCKET_PATH)
                sock.sendall(json.dumps(state).encode())
                if state.get("status") == "waiting_for_approval":
                    response = sock.recv(4096)
                    sock.close()
                    return json.loads(response.decode()) if response else None
                sock.close()
            except Exception:
                return None
            return None

        def first_value(data, names, default=None):
            for name in names:
                if name in data and data.get(name) is not None:
                    return data.get(name)
            return default

        def main():
            try:
                data = json.load(sys.stdin)
            except Exception:
                sys.exit(1)

            event = data.get("hook_event_name", "")
            state = {
                "session_id": data.get("session_id", "unknown"),
                "cwd": data.get("cwd", ""),
                "event": event,
                "agent": detect_agent(),
                "pid": os.getppid(),
                "tty": get_tty(),
                "message": first_value(data, ["message", "prompt", "text", "output", "response", "content", "assistant_message", "assistantMessage"]),
            }

            if event == "UserPromptSubmit":
                state["status"] = "processing"
            elif event == "PreToolUse":
                state["status"] = "running_tool"
                state["tool"] = data.get("tool_name")
                state["tool_input"] = data.get("tool_input", {})
                if data.get("tool_use_id"):
                    state["tool_use_id"] = data.get("tool_use_id")
            elif event == "PostToolUse":
                state["status"] = "processing"
                state["tool"] = data.get("tool_name")
                state["tool_input"] = data.get("tool_input", {})
                if data.get("tool_use_id"):
                    state["tool_use_id"] = data.get("tool_use_id")
            elif event == "PermissionRequest":
                state["status"] = "waiting_for_approval"
                state["tool"] = data.get("tool_name")
                state["tool_input"] = data.get("tool_input", {})
                response = send_event(state)
                if response and response.get("decision") == "allow":
                    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PermissionRequest", "decision": {"behavior": "allow"}}}))
                    sys.exit(0)
                if response and response.get("decision") == "deny":
                    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PermissionRequest", "decision": {"behavior": "deny", "message": response.get("reason") or "Denied by NotchPaste"}}}))
                    sys.exit(0)
                sys.exit(0)
            elif event == "Notification":
                if data.get("notification_type") == "permission_prompt":
                    sys.exit(0)
                state["status"] = "waiting_for_input" if data.get("notification_type") == "idle_prompt" else "notification"
                state["notification_type"] = data.get("notification_type")
                state["message"] = first_value(data, ["message", "prompt", "text", "output", "response", "content", "assistant_message", "assistantMessage"])
            elif event in ("Stop", "StopFailure", "SessionStart"):
                state["status"] = "waiting_for_input"
            elif event == "SessionEnd":
                state["status"] = "ended"
            elif event == "PreCompact":
                state["status"] = "compacting"
            else:
                state["status"] = "processing"

            send_event(state)

        if __name__ == "__main__":
            main()
        """
    }

    private static func shellQuote(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
