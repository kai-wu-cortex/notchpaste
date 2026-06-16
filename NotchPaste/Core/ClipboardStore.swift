import Foundation
import Combine
import CryptoKit
import GRDB
import os

/// GRDB-backed clipboard history store.
///
/// 设计：
/// - SQLite 单表 `clipboard_item`（v0.1 仅 text；image/file 列预留可空）。
/// - 写入时按 (type, content_hash) 去重 —— 重复文本仅刷新 created_at。
/// - 写入后自动裁剪：保留最多 maxItems 条非 pinned 项。
/// - 通过 Combine Publisher `itemsPublisher` 通知订阅者最新列表。
final class ClipboardStore {

    // MARK: - Schema

    private static let migrator: DatabaseMigrator = {
        var m = DatabaseMigrator()
        m.registerMigration("v1") { db in
            try db.create(table: "clipboard_item") { t in
                t.column("id", .text).primaryKey()
                t.column("kind", .text).notNull()              // "text" (v0.1) — extensible
                t.column("text_content", .text)                // for kind=text
                t.column("content_hash", .text).notNull()      // for dedup
                t.column("created_at", .double).notNull()
                t.column("pinned", .boolean).notNull().defaults(to: false)
                t.column("source_app_bundle_id", .text)
            }
            try db.create(index: "idx_item_hash", on: "clipboard_item", columns: ["content_hash"])
            try db.create(index: "idx_item_created", on: "clipboard_item", columns: ["created_at"])
        }
        return m
    }()

    // MARK: - State

    private let dbQueue: DatabaseQueue
    private let maxItems: Int
    private let subject = CurrentValueSubject<[ClipboardItem], Never>([])

    var itemsPublisher: AnyPublisher<[ClipboardItem], Never> {
        subject.eraseToAnyPublisher()
    }

    // MARK: - Init

    /// 用于生产：自动选 Application Support 路径建库。
    convenience init(maxItems: Int = 200) throws {
        let url = try Self.defaultDatabaseURL()
        let dbQueue = try DatabaseQueue(path: url.path)
        try self.init(dbQueue: dbQueue, maxItems: maxItems)
    }

    /// 用于测试：注入自定义 DatabaseQueue（如内存）。
    init(dbQueue: DatabaseQueue, maxItems: Int) throws {
        self.dbQueue = dbQueue
        self.maxItems = maxItems
        try Self.migrator.migrate(dbQueue)
        // 初始快照
        let snapshot = try fetchAllItems()
        subject.send(snapshot)
    }

    private static func defaultDatabaseURL() throws -> URL {
        let fm = FileManager.default
        let appSupport = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = appSupport.appendingPathComponent("NotchPaste", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("clipboard.sqlite")
    }

    // MARK: - Public API

    /// 添加一项。如已存在相同内容（按内容哈希去重），保留原行 id 与 pinned 状态，
    /// 仅刷新 created_at 与 sourceAppBundleID；调用方应预期传入的 `item.id`
    /// 在去重场景下不会成为最终存储的 id。
    func add(_ item: ClipboardItem) throws {
        let hash = Self.contentHash(for: item.type)
        try dbQueue.write { db in
            // Dedup: same content_hash → update timestamp & id only (keep pinned state)
            if let existingId: String = try String.fetchOne(db, sql: "SELECT id FROM clipboard_item WHERE content_hash = ?", arguments: [hash]) {
                try db.execute(
                    sql: "UPDATE clipboard_item SET created_at = ?, source_app_bundle_id = ? WHERE id = ?",
                    arguments: [item.createdAt.timeIntervalSince1970, item.sourceAppBundleID, existingId]
                )
            } else {
                try db.execute(
                    sql: """
                    INSERT INTO clipboard_item
                        (id, kind, text_content, content_hash, created_at, pinned, source_app_bundle_id)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        item.id.uuidString,
                        Self.kindString(for: item.type),
                        Self.textContent(for: item.type),
                        hash,
                        item.createdAt.timeIntervalSince1970,
                        item.pinned,
                        item.sourceAppBundleID
                    ]
                )
            }
            // Trim: drop oldest non-pinned beyond maxItems
            try db.execute(
                sql: """
                DELETE FROM clipboard_item
                WHERE pinned = 0
                  AND id NOT IN (
                    SELECT id FROM clipboard_item
                    WHERE pinned = 0
                    ORDER BY created_at DESC
                    LIMIT ?
                  )
                """,
                arguments: [maxItems]
            )
        }
        try emitSnapshot()
    }

    func delete(id: UUID) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM clipboard_item WHERE id = ?", arguments: [id.uuidString])
        }
        try emitSnapshot()
    }

    func togglePin(id: UUID) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE clipboard_item SET pinned = NOT pinned WHERE id = ?",
                arguments: [id.uuidString]
            )
        }
        try emitSnapshot()
    }

    /// 返回全部历史（newest first）。
    func allItems() throws -> [ClipboardItem] {
        try fetchAllItems()
    }

    /// 模糊搜索（仅 text 内容）。
    func query(search: String?) throws -> [ClipboardItem] {
        let all = try fetchAllItems()
        guard let q = search?.trimmingCharacters(in: .whitespacesAndNewlines), !q.isEmpty else {
            return all
        }
        let lower = q.lowercased()
        return all.filter { item in
            switch item.type {
            case .text(let s): return s.lowercased().contains(lower)
            }
        }
    }

    // MARK: - Internals

    private func emitSnapshot() throws {
        subject.send(try fetchAllItems())
    }

    private func fetchAllItems() throws -> [ClipboardItem] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT id, kind, text_content, created_at, pinned, source_app_bundle_id
                FROM clipboard_item
                ORDER BY pinned DESC, created_at DESC
                """)
            return rows.compactMap(Self.itemFromRow)
        }
    }

    private static func itemFromRow(_ row: Row) -> ClipboardItem? {
        let idString: String? = row["id"]
        guard
            let idStr = idString,
            let id = UUID(uuidString: idStr),
            let kind: String = row["kind"],
            let createdAtRaw: Double = row["created_at"]
        else {
            AppLogger.store.error("Dropping unparseable row id=\(idString ?? "<nil>", privacy: .public)")
            return nil
        }
        let pinned: Bool = row["pinned"] ?? false
        let sourceApp: String? = row["source_app_bundle_id"]

        let type: ItemType
        switch kind {
        case "text":
            guard let text: String = row["text_content"] else {
                AppLogger.store.error("Row \(idStr, privacy: .public) kind=text has nil text_content")
                return nil
            }
            type = .text(text)
        default:
            AppLogger.store.error("Row \(idStr, privacy: .public) has unknown kind=\(kind, privacy: .public)")
            return nil
        }

        return ClipboardItem(
            id: id,
            type: type,
            createdAt: Date(timeIntervalSince1970: createdAtRaw),
            pinned: pinned,
            sourceAppBundleID: sourceApp
        )
    }

    private static func kindString(for type: ItemType) -> String {
        switch type {
        case .text: return "text"
        }
    }

    private static func textContent(for type: ItemType) -> String? {
        switch type {
        case .text(let s): return s
        }
    }

    private static func contentHash(for type: ItemType) -> String {
        switch type {
        case .text(let s):
            let data = Data(("text:" + s).utf8)
            let digest = SHA256.hash(data: data)
            return digest.map { String(format: "%02x", $0) }.joined()
        }
    }
}
