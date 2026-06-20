import Foundation
import Darwin

final class VibeClaudeHookSocketServer {
    static let shared = VibeClaudeHookSocketServer()

    private var serverSocket: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var eventHandler: ((VibeClaudeHookEvent) -> Void)?
    private let queue = DispatchQueue(label: "com.notchpaste.vibe-claude.socket", qos: .userInitiated)
    private let lock = NSLock()
    private var pendingPermissions: [String: PendingPermission] = [:]
    private var toolUseIdCache: [String: [String]] = [:]
    private let socketPath: String

    init(socketPath: String = VibeClaudeHookInstaller.defaultSocketPath) {
        self.socketPath = socketPath
    }

    func start(onEvent: @escaping (VibeClaudeHookEvent) -> Void) {
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
            lock.lock()
            pendingPermissions.values.forEach { close($0.clientSocket) }
            pendingPermissions.removeAll()
            toolUseIdCache.removeAll()
            lock.unlock()
        }
    }

    func respondToPermission(toolUseId: String, decision: String, reason: String? = nil) {
        queue.async { [weak self] in
            self?.sendPermissionResponse(toolUseId: toolUseId, decision: decision, reason: reason)
        }
    }

    private func startServer(onEvent: @escaping (VibeClaudeHookEvent) -> Void) {
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
        var nosigpipe: Int32 = 1
        setsockopt(clientSocket, SOL_SOCKET, SO_NOSIGPIPE, &nosigpipe, socklen_t(MemoryLayout<Int32>.size))
        handleClient(clientSocket)
    }

    private func handleClient(_ clientSocket: Int32) {
        let flags = fcntl(clientSocket, F_GETFL)
        _ = fcntl(clientSocket, F_SETFL, flags | O_NONBLOCK)

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

        guard !data.isEmpty, var event = try? JSONDecoder().decode(VibeClaudeHookEvent.self, from: data) else {
            close(clientSocket)
            return
        }

        if event.event == "PreToolUse", let toolUseId = event.toolUseId {
            cache(toolUseId: toolUseId, for: event)
        }

        if event.expectsResponse {
            guard let toolUseId = event.toolUseId ?? popCachedToolUseId(for: event) else {
                close(clientSocket)
                eventHandler?(event)
                return
            }
            event = VibeClaudeHookEvent(
                sessionId: event.sessionId,
                cwd: event.cwd,
                event: event.event,
                status: event.status,
                pid: event.pid,
                tty: event.tty,
                tool: event.tool,
                toolInput: event.toolInput,
                toolUseId: toolUseId,
                notificationType: event.notificationType,
                message: event.message,
                questionOptions: event.questionOptions,
                agent: event.agent
            )
            lock.lock()
            pendingPermissions[toolUseId] = PendingPermission(toolUseId: toolUseId, clientSocket: clientSocket, receivedAt: Date())
            lock.unlock()
            eventHandler?(event)
            return
        }

        close(clientSocket)
        eventHandler?(event)
    }

    private func sendPermissionResponse(toolUseId: String, decision: String, reason: String?) {
        lock.lock()
        guard let pending = pendingPermissions.removeValue(forKey: toolUseId) else {
            lock.unlock()
            return
        }
        lock.unlock()

        let response = VibeClaudeHookResponse(decision: decision, reason: reason)
        if let data = try? JSONEncoder().encode(response) {
            data.withUnsafeBytes { bytes in
                guard let base = bytes.baseAddress else { return }
                _ = write(pending.clientSocket, base, data.count)
            }
        }
        close(pending.clientSocket)
    }

    private func cache(toolUseId: String, for event: VibeClaudeHookEvent) {
        let key = cacheKey(for: event)
        lock.lock()
        toolUseIdCache[key, default: []].append(toolUseId)
        lock.unlock()
    }

    private func popCachedToolUseId(for event: VibeClaudeHookEvent) -> String? {
        let key = cacheKey(for: event)
        lock.lock()
        defer { lock.unlock() }
        guard var ids = toolUseIdCache[key], !ids.isEmpty else { return nil }
        let id = ids.removeFirst()
        if ids.isEmpty {
            toolUseIdCache.removeValue(forKey: key)
        } else {
            toolUseIdCache[key] = ids
        }
        return id
    }

    private func cacheKey(for event: VibeClaudeHookEvent) -> String {
        let input = event.toolInput?
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.description)" }
            .joined(separator: "&") ?? ""
        return "\(event.sessionId):\(event.tool ?? ""):\(input)"
    }
}

private struct PendingPermission {
    let toolUseId: String
    let clientSocket: Int32
    let receivedAt: Date
}
