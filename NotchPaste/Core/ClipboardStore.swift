import Foundation
import Combine
import CryptoKit
import GRDB
import os

/// GRDB-backed clipboard history store.
///
/// 设计：
/// - SQLite 单表 `clipboard_item`，kind 字段区分类型（text/file/image/url）。
/// - 写入时按 (kind, content_hash) 去重 —— 重复内容仅刷新 created_at。
/// - 写入后自动裁剪：保留最多 maxItems 条非 pinned 项。
/// - 通过 Combine Publisher `itemsPublisher` 通知订阅者最新列表。
final class ClipboardStore: @unchecked Sendable {

    static let defaultMaxItems = 2_000

    /// 类别筛选，对应 UI 左侧 sidebar。
    enum Category: String, CaseIterable {
        case all      // 最近：按 created_at 排
        case favorite // 常用：按 usageCount 排（仅展示用过的）
        case text
        case image
        case url
        case file
    }

    // MARK: - Schema

    private static let migrator: DatabaseMigrator = {
        var m = DatabaseMigrator()
        m.registerMigration("v1") { db in
            try db.create(table: "clipboard_item") { t in
                t.column("id", .text).primaryKey()
                t.column("kind", .text).notNull()
                t.column("text_content", .text)
                t.column("content_hash", .text).notNull()
                t.column("created_at", .double).notNull()
                t.column("pinned", .boolean).notNull().defaults(to: false)
                t.column("source_app_bundle_id", .text)
            }
            try db.create(index: "idx_item_hash", on: "clipboard_item", columns: ["content_hash"])
            try db.create(index: "idx_item_created", on: "clipboard_item", columns: ["created_at"])
        }
        m.registerMigration("v2_file_paths") { db in
            try db.alter(table: "clipboard_item") { t in
                t.add(column: "file_paths_json", .text)
            }
        }
        m.registerMigration("v3_image_data") { db in
            try db.alter(table: "clipboard_item") { t in
                t.add(column: "image_data", .blob)
            }
        }
        m.registerMigration("v4_url_and_usage") { db in
            // url_string 用于 kind=url 行。
            // usage_count / last_used_at 用于"常用"分类排序与最近使用时间。
            try db.alter(table: "clipboard_item") { t in
                t.add(column: "url_string", .text)
                t.add(column: "usage_count", .integer).notNull().defaults(to: 0)
                t.add(column: "last_used_at", .double)
            }
            try db.create(index: "idx_item_usage", on: "clipboard_item", columns: ["usage_count"])
        }
        return m
    }()

    // MARK: - State

    private let dbQueue: DatabaseQueue
    private let maxItems: Int
    private let subject = CurrentValueSubject<[ClipboardItem], Never>([])
    private let snapshotDelay: TimeInterval
    private let snapshotQueue = DispatchQueue(label: "com.notchpaste.clipboard.snapshot", qos: .userInitiated)
    private let snapshotLock = NSLock()
    private var pendingSnapshotWork: DispatchWorkItem?
    private var nonPinnedItemCount: Int

    var itemsPublisher: AnyPublisher<[ClipboardItem], Never> {
        subject.eraseToAnyPublisher()
    }

    // MARK: - Init

    convenience init(maxItems: Int = ClipboardStore.defaultMaxItems) throws {
        let url = try Self.defaultDatabaseURL()
        let dbQueue = try DatabaseQueue(path: url.path)
        try self.init(dbQueue: dbQueue, maxItems: maxItems)
    }

    init(dbQueue: DatabaseQueue, maxItems: Int, snapshotDelay: TimeInterval = 0.02) throws {
        self.dbQueue = dbQueue
        self.maxItems = maxItems
        self.snapshotDelay = snapshotDelay
        self.nonPinnedItemCount = 0
        try Self.migrator.migrate(dbQueue)
        self.nonPinnedItemCount = try Self.fetchNonPinnedItemCount(dbQueue)
        let snapshot = try fetchAllItems()
        subject.send(snapshot)
    }

    deinit {
        snapshotLock.lock()
        pendingSnapshotWork?.cancel()
        snapshotLock.unlock()
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

    /// 添加一项。如已存在相同内容（按 content_hash 去重），保留原行 id 与 pinned/usage 状态，
    /// 仅刷新 created_at 与 sourceAppBundleID；调用方应预期传入的 `item.id`
    /// 在去重场景下不会成为最终存储的 id。
    func add(_ item: ClipboardItem) throws {
        let hash = Self.contentHash(for: item.type)
        try dbQueue.write { db in
            if let existingId: String = try String.fetchOne(db, sql: "SELECT id FROM clipboard_item WHERE content_hash = ?", arguments: [hash]) {
                try db.execute(
                    sql: "UPDATE clipboard_item SET created_at = ?, source_app_bundle_id = ? WHERE id = ?",
                    arguments: [item.createdAt.timeIntervalSince1970, item.sourceAppBundleID, existingId]
                )
            } else {
                try db.execute(
                    sql: """
                    INSERT INTO clipboard_item
                        (id, kind, text_content, file_paths_json, image_data, url_string,
                         content_hash, created_at, pinned, source_app_bundle_id,
                         usage_count, last_used_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        item.id.uuidString,
                        Self.kindString(for: item.type),
                        Self.textContent(for: item.type),
                        Self.filePathsJSON(for: item.type),
                        Self.imageData(for: item.type),
                        Self.urlString(for: item.type),
                        hash,
                        item.createdAt.timeIntervalSince1970,
                        item.pinned,
                        item.sourceAppBundleID,
                        item.usageCount,
                        item.lastUsedAt?.timeIntervalSince1970
                    ]
                )
                if !item.pinned {
                    nonPinnedItemCount += 1
                }
            }
            if nonPinnedItemCount > maxItems {
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
                nonPinnedItemCount = maxItems
            }
        }
        scheduleSnapshotEmit()
    }

    func delete(id: UUID) throws {
        try dbQueue.write { db in
            let pinned: Bool? = try Bool.fetchOne(
                db,
                sql: "SELECT pinned FROM clipboard_item WHERE id = ?",
                arguments: [id.uuidString]
            )
            try db.execute(sql: "DELETE FROM clipboard_item WHERE id = ?", arguments: [id.uuidString])
            if pinned == false {
                nonPinnedItemCount = max(0, nonPinnedItemCount - 1)
            }
        }
        scheduleSnapshotEmit()
    }

    func togglePin(id: UUID) throws {
        try dbQueue.write { db in
            let wasPinned: Bool? = try Bool.fetchOne(
                db,
                sql: "SELECT pinned FROM clipboard_item WHERE id = ?",
                arguments: [id.uuidString]
            )
            try db.execute(
                sql: "UPDATE clipboard_item SET pinned = NOT pinned WHERE id = ?",
                arguments: [id.uuidString]
            )
            if wasPinned == true {
                nonPinnedItemCount += 1
            } else if wasPinned == false {
                nonPinnedItemCount = max(0, nonPinnedItemCount - 1)
            }
        }
        scheduleSnapshotEmit()
    }

    /// 标记一项被使用：usage_count +1，last_used_at = now。
    /// 用户从历史里点击复制 / Enter 时调用，驱动"常用"分类的排序。
    func markUsed(id: UUID, at date: Date = Date()) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE clipboard_item SET usage_count = usage_count + 1, last_used_at = ? WHERE id = ?",
                arguments: [date.timeIntervalSince1970, id.uuidString]
            )
        }
        scheduleSnapshotEmit()
    }

    /// 返回全部历史（newest first）。
    func allItems() throws -> [ClipboardItem] {
        try fetchAllItems()
    }

    /// 按类别 + 搜索词查询。
    /// .all → newest first；.favorite → usage 多的在前（仅 usage_count > 0）；
    /// 其它 → 该 kind 的 newest first。
    func query(category: Category, search: String? = nil) throws -> [ClipboardItem] {
        let all = try fetchAllItems()
        return Self.filter(all, category: category, search: search)
    }

    static func filter(_ all: [ClipboardItem], category: Category, search: String? = nil) -> [ClipboardItem] {
        let filtered: [ClipboardItem]

        switch category {
        case .all:
            filtered = all
        case .favorite:
            // 常用 = 已加星（pinned）的项，按使用次数排序，未用过的按加星时间近的在前
            filtered = all
                .filter { $0.pinned }
                .sorted { lhs, rhs in
                    if lhs.usageCount != rhs.usageCount {
                        return lhs.usageCount > rhs.usageCount
                    }
                    return (lhs.lastUsedAt ?? lhs.createdAt) > (rhs.lastUsedAt ?? rhs.createdAt)
                }
        case .text:
            filtered = all.filter { if case .text = $0.type { return true } else { return false } }
        case .image:
            filtered = all.filter { if case .image = $0.type { return true } else { return false } }
        case .url:
            filtered = all.filter { if case .url = $0.type { return true } else { return false } }
        case .file:
            filtered = all.filter { if case .file = $0.type { return true } else { return false } }
        }

        guard let q = search?.trimmingCharacters(in: .whitespacesAndNewlines), !q.isEmpty else {
            return filtered
        }
        let lower = q.lowercased()
        return filtered.filter { item in
            switch item.type {
            case .text(let s):
                return s.lowercased().contains(lower)
            case .file(let urls):
                return urls.contains { $0.lastPathComponent.lowercased().contains(lower) }
            case .image:
                return false
            case .url(let raw, let url):
                return raw.lowercased().contains(lower)
                    || url.host?.lowercased().contains(lower) == true
            }
        }
    }

    /// 兼容旧调用：仅按搜索词过滤所有内容。
    func query(search: String?) throws -> [ClipboardItem] {
        try query(category: .all, search: search)
    }

    // MARK: - Internals

    private func scheduleSnapshotEmit() {
        if snapshotDelay <= 0 {
            emitSnapshot()
            return
        }

        let work = DispatchWorkItem { [weak self] in
            self?.emitSnapshot()
        }

        snapshotLock.lock()
        pendingSnapshotWork?.cancel()
        pendingSnapshotWork = work
        snapshotLock.unlock()

        snapshotQueue.asyncAfter(deadline: .now() + snapshotDelay, execute: work)
    }

    private func emitSnapshot() {
        do {
            subject.send(try fetchAllItems())
        } catch {
            AppLogger.store.error("snapshot emit failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func fetchAllItems() throws -> [ClipboardItem] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT id, kind, text_content, file_paths_json, image_data, url_string,
                       created_at, pinned, source_app_bundle_id,
                       usage_count, last_used_at
                FROM clipboard_item
                ORDER BY created_at DESC
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
        let usageCount: Int = row["usage_count"] ?? 0
        let lastUsedRaw: Double? = row["last_used_at"]
        let lastUsedAt = lastUsedRaw.map { Date(timeIntervalSince1970: $0) }

        let type: ItemType
        switch kind {
        case "text":
            guard let text: String = row["text_content"] else {
                AppLogger.store.error("Row \(idStr, privacy: .public) kind=text has nil text_content")
                return nil
            }
            type = .text(text)
        case "file":
            guard let json: String = row["file_paths_json"],
                  let data = json.data(using: .utf8),
                  let paths = try? JSONDecoder().decode([String].self, from: data) else {
                AppLogger.store.error("Row \(idStr, privacy: .public) kind=file has bad file_paths_json")
                return nil
            }
            let urls = paths.map { URL(fileURLWithPath: $0) }
            type = .file(urls)
        case "image":
            guard let data: Data = row["image_data"] else {
                AppLogger.store.error("Row \(idStr, privacy: .public) kind=image has nil image_data")
                return nil
            }
            type = .image(data)
        case "url":
            guard let raw: String = row["url_string"],
                  let url = URL(string: raw) else {
                // 老库可能没填 url_string；尝试用 text_content 兜底
                if let raw: String = row["text_content"], let url = URL(string: raw) {
                    type = .url(raw: raw, url: url)
                    break
                }
                AppLogger.store.error("Row \(idStr, privacy: .public) kind=url has bad url_string")
                return nil
            }
            type = .url(raw: raw, url: url)
        default:
            AppLogger.store.error("Row \(idStr, privacy: .public) has unknown kind=\(kind, privacy: .public)")
            return nil
        }

        return ClipboardItem(
            id: id,
            type: type,
            createdAt: Date(timeIntervalSince1970: createdAtRaw),
            pinned: pinned,
            sourceAppBundleID: sourceApp,
            usageCount: usageCount,
            lastUsedAt: lastUsedAt
        )
    }

    private static func fetchNonPinnedItemCount(_ dbQueue: DatabaseQueue) throws -> Int {
        try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM clipboard_item WHERE pinned = 0") ?? 0
        }
    }

    private static func kindString(for type: ItemType) -> String {
        switch type {
        case .text: return "text"
        case .file: return "file"
        case .image: return "image"
        case .url: return "url"
        }
    }

    private static func textContent(for type: ItemType) -> String? {
        switch type {
        case .text(let s): return s
        case .url(let raw, _): return raw   // 链接也写入 text_content 方便老查询逻辑
        case .file, .image: return nil
        }
    }

    private static func urlString(for type: ItemType) -> String? {
        switch type {
        case .url(_, let url): return url.absoluteString
        default: return nil
        }
    }

    private static func filePathsJSON(for type: ItemType) -> String? {
        switch type {
        case .text, .image, .url: return nil
        case .file(let urls):
            let paths = urls.map(\.path)
            guard let data = try? JSONEncoder().encode(paths),
                  let s = String(data: data, encoding: .utf8) else { return nil }
            return s
        }
    }

    private static func imageData(for type: ItemType) -> Data? {
        switch type {
        case .text, .file, .url: return nil
        case .image(let d): return d
        }
    }

    private static func contentHash(for type: ItemType) -> String {
        let raw: Data
        switch type {
        case .text(let s):
            raw = Data(("text:" + s).utf8)
        case .url(_, let url):
            raw = Data(("url:" + url.absoluteString).utf8)
        case .file(let urls):
            raw = Data(("file:" + urls.map(\.path).joined(separator: "|")).utf8)
        case .image(let d):
            var prefixed = Data("image:".utf8)
            prefixed.append(d)
            raw = prefixed
        }
        let digest = SHA256.hash(data: raw)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
