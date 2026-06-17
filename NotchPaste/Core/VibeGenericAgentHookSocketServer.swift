import Foundation
import Darwin

struct VibeGenericAgentHookEvent: Codable, Equatable, Sendable {
    let agent: String
    let sessionId: String
    let cwd: String
    let event: String
    let status: String
    let pid: Int?
    let tty: String?
    let tool: String?
    let toolInput: [String: AnyCodable]?
    let toolUseId: String?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case agent
        case sessionId = "session_id"
        case cwd
        case event
        case status
        case pid
        case tty
        case tool
        case toolInput = "tool_input"
        case toolUseId = "tool_use_id"
        case message
    }

    var agentEvent: VibeAgentEvent? {
        switch agent {
        case "codex":
            return VibeCodexHookEvent(
                sessionId: sessionId,
                cwd: cwd,
                event: event,
                status: status,
                pid: pid,
                tty: tty,
                tool: tool,
                toolInput: toolInput,
                toolUseId: toolUseId,
                message: message
            ).agentEvent
        case "gemini":
            return VibeGeminiHookEvent(
                sessionId: sessionId,
                cwd: cwd,
                event: event,
                status: status,
                pid: pid,
                tty: tty,
                tool: tool,
                toolInput: toolInput,
                toolUseId: toolUseId,
                message: message
            ).agentEvent
        default:
            return nil
        }
    }
}

final class VibeGenericAgentHookSocketServer {
    static let shared = VibeGenericAgentHookSocketServer()

    private var serverSocket: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var eventHandler: ((VibeGenericAgentHookEvent) -> Void)?
    private let queue = DispatchQueue(label: "com.notchpaste.vibe-agent.socket", qos: .userInitiated)
    private let socketPath: String

    init(socketPath: String = VibeCodexHookInstaller.defaultSocketPath) {
        self.socketPath = socketPath
    }

    func start(onEvent: @escaping (VibeGenericAgentHookEvent) -> Void) {
        queue.async { [weak self] in
            self?.startServer(onEvent: onEvent)
        }
    }

    func stop() {
        queue.sync {
            acceptSource?.cancel()
            acceptSource = nil
            if serverSocket >= 0 {
                close(serverSocket)
                serverSocket = -1
            }
            unlink(socketPath)
        }
    }

    private func startServer(onEvent: @escaping (VibeGenericAgentHookEvent) -> Void) {
        guard serverSocket < 0 else { return }
        eventHandler = onEvent
        unlink(socketPath)

        serverSocket = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverSocket >= 0 else { return }

        let flags = fcntl(serverSocket, F_GETFL)
        _ = fcntl(serverSocket, F_SETFL, flags | O_NONBLOCK)

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        socketPath.withCString { path in
            withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
                let raw = UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: CChar.self)
                strncpy(raw, path, 103)
            }
        }

        let bound = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                bind(serverSocket, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, listen(serverSocket, 16) == 0 else {
            close(serverSocket)
            serverSocket = -1
            return
        }
        chmod(socketPath, 0o600)

        let source = DispatchSource.makeReadSource(fileDescriptor: serverSocket, queue: queue)
        source.setEventHandler { [weak self] in
            self?.acceptConnection()
        }
        source.setCancelHandler { [weak self] in
            guard let self, self.serverSocket >= 0 else { return }
            close(self.serverSocket)
            self.serverSocket = -1
        }
        acceptSource = source
        source.resume()
    }

    private func acceptConnection() {
        let clientSocket = accept(serverSocket, nil, nil)
        guard clientSocket >= 0 else { return }
        handleClient(clientSocket)
    }

    private func handleClient(_ clientSocket: Int32) {
        defer { close(clientSocket) }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 128 * 1024)
        var fd = pollfd(fd: clientSocket, events: Int16(POLLIN), revents: 0)
        let deadline = Date().addingTimeInterval(0.5)

        while Date() < deadline {
            let result = poll(&fd, 1, 50)
            if result > 0, (fd.revents & Int16(POLLIN)) != 0 {
                let bytesRead = read(clientSocket, &buffer, buffer.count)
                if bytesRead > 0 {
                    data.append(contentsOf: buffer[0..<bytesRead])
                } else {
                    break
                }
            } else if !data.isEmpty {
                break
            }
        }

        guard !data.isEmpty,
              let event = try? JSONDecoder().decode(VibeGenericAgentHookEvent.self, from: data) else {
            return
        }
        eventHandler?(event)
    }
}
