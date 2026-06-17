import Foundation

enum VibeGenericAgentHookScript {
    static func contents(agent: String, socketPath: String) -> String {
        """
        #!/usr/bin/env python3
        import json
        import os
        import socket
        import subprocess
        import sys

        AGENT = "\(agent)"
        SOCKET_PATH = "\(socketPath)"

        def get_tty():
            try:
                result = subprocess.run(["ps", "-p", str(os.getppid()), "-o", "tty="], capture_output=True, text=True, timeout=2)
                tty = result.stdout.strip()
                if tty and tty not in ("??", "-"):
                    return tty if tty.startswith("/dev/") else "/dev/" + tty
            except Exception:
                pass
            return None

        def status_for_event(event):
            if event in ("PreToolUse", "BeforeTool"):
                return "running_tool"
            if event in ("PermissionRequest", "ApprovalRequest"):
                return "waiting_for_approval"
            if event in ("Stop", "SessionEnd"):
                return "ended"
            if event in ("Notification",):
                return "waiting_for_input"
            return "processing"

        def send_event(state):
            try:
                sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                sock.settimeout(0.4)
                sock.connect(SOCKET_PATH)
                sock.sendall(json.dumps(state).encode())
                sock.close()
            except Exception:
                pass

        def first_value(data, names, default=None):
            for name in names:
                if name in data and data.get(name) is not None:
                    return data.get(name)
            return default

        def usage_label(data):
            usage = first_value(data, ["usage", "token_usage", "tokenUsage"])
            if isinstance(usage, dict):
                percent = first_value(usage, ["percent", "percentage", "remaining_percent", "remainingPercentage"])
                if percent is not None:
                    try:
                        value = float(percent)
                        if value <= 1:
                            value = value * 100
                        return str(int(round(value))) + "%"
                    except Exception:
                        return str(percent)
                total = first_value(usage, ["total_tokens", "totalTokens", "tokens"])
                if total is not None:
                    return str(total) + " tok"
            label = first_value(data, ["usage_label", "usageLabel", "token_usage_label", "tokenUsageLabel"])
            if label is not None:
                return str(label)
            return None

        def main():
            try:
                data = json.load(sys.stdin)
            except Exception:
                data = {}

            event = first_value(data, ["hook_event_name", "event", "name"], "Unknown")
            state = {
                "agent": AGENT,
                "session_id": first_value(data, ["session_id", "sessionId", "conversation_id"], "unknown"),
                "cwd": first_value(data, ["cwd", "workspace", "working_directory"], os.getcwd()),
                "event": event,
                "status": first_value(data, ["status"], status_for_event(event)),
                "pid": os.getppid(),
                "tty": get_tty(),
                "tool": first_value(data, ["tool_name", "tool", "name"]),
                "tool_input": first_value(data, ["tool_input", "toolInput", "args"], {}),
                "tool_use_id": first_value(data, ["tool_use_id", "toolUseId", "call_id"]),
                "usage_label": usage_label(data),
                "message": first_value(data, ["message", "prompt", "text"]),
            }
            send_event(state)

        if __name__ == "__main__":
            main()
        """
    }
}
