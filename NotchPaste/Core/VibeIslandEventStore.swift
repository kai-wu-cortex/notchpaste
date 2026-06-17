import Foundation
import SwiftUI

struct VibeIslandAgentEvent: Codable, Equatable, Identifiable {
    let id: UUID
    let agent: String
    let terminal: String
    let title: String
    let detail: String
    let elapsed: String
    let state: String
    let action: VibeSessionAction
    let tint: String
}

struct VibeIslandAgentResponse: Codable, Equatable {
    let sessionID: UUID?
    let action: VibeIslandAgentResponseAction
    let value: String
    let createdAt: Date
}

enum VibeIslandAgentResponseAction: String, Codable, Equatable {
    case allow
    case deny
    case reply
    case reviewPlan
    case open
    case jump
}

final class VibeIslandEventStore {
    private let directory: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(directory: URL, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    convenience init() throws {
        let fm = FileManager.default
        let appSupport = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = appSupport
            .appendingPathComponent("NotchPaste", isDirectory: true)
            .appendingPathComponent("VibeIsland", isDirectory: true)
        self.init(directory: dir, fileManager: fm)
    }

    static func defaultStore() -> VibeIslandEventStore? {
        try? VibeIslandEventStore()
    }

    func loadDashboard() throws -> VibeIslandDashboard {
        let events = try loadEvents()
        guard !events.isEmpty else { return .empty }

        var dashboard = VibeIslandDashboard.empty
        dashboard.sessions = events.map { $0.session }
        return dashboard
    }

    func save(_ events: [VibeIslandAgentEvent]) throws {
        try ensureDirectory()
        let data = try encoder.encode(events)
        try data.write(to: sessionsURL, options: .atomic)
    }

    func appendResponse(_ response: VibeIslandAgentResponse) throws {
        try ensureDirectory()
        let data = try encoder.encode(response)
        var line = data
        line.append(0x0A)

        if fileManager.fileExists(atPath: responsesURL.path) {
            let handle = try FileHandle(forWritingTo: responsesURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
            try handle.close()
        } else {
            try line.write(to: responsesURL, options: .atomic)
        }
    }

    func loadResponses() throws -> [VibeIslandAgentResponse] {
        guard fileManager.fileExists(atPath: responsesURL.path) else { return [] }
        let data = try Data(contentsOf: responsesURL)
        let lines = String(decoding: data, as: UTF8.self)
            .split(separator: "\n")
            .map(String.init)
        return try lines.map { line in
            guard let data = line.data(using: .utf8) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            return try decoder.decode(VibeIslandAgentResponse.self, from: data)
        }
    }

    private func loadEvents() throws -> [VibeIslandAgentEvent] {
        guard fileManager.fileExists(atPath: sessionsURL.path) else { return [] }
        let data = try Data(contentsOf: sessionsURL)
        return try decoder.decode([VibeIslandAgentEvent].self, from: data)
    }

    private func ensureDirectory() throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private var sessionsURL: URL {
        directory.appendingPathComponent("sessions.json")
    }

    private var responsesURL: URL {
        directory.appendingPathComponent("responses.jsonl")
    }
}

private extension VibeIslandAgentEvent {
    var session: VibeSession {
        VibeSession(
            id: id,
            agent: agent,
            terminal: terminal,
            title: title,
            detail: detail,
            elapsed: elapsed,
            state: state,
            action: action,
            tint: tint.color
        )
    }
}

private extension String {
    var color: Color {
        switch lowercased() {
        case "orange": return .orange
        case "cyan": return .cyan
        case "green": return .green
        case "mint": return .mint
        case "pink": return .pink
        case "yellow": return .yellow
        default: return .white
        }
    }
}
