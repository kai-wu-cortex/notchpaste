import Testing
import Foundation
import GRDB
@testable import NotchPaste

@Suite("ClipboardStore")
struct ClipboardStoreTests {

    /// 给每个测试一个隔离的内存 DB。
    func makeStore(maxItems: Int = 200) throws -> ClipboardStore {
        let dbQueue = try DatabaseQueue() // in-memory
        return try ClipboardStore(dbQueue: dbQueue, maxItems: maxItems)
    }

    @Test("add then list returns the item")
    func addAndList() throws {
        let store = try makeStore()
        let item = ClipboardItem.text("hello")
        try store.add(item)
        let items = try store.allItems()
        #expect(items.count == 1)
        #expect(items.first?.id == item.id)
        if case .text(let s) = items.first?.type { #expect(s == "hello") }
        else { Issue.record("Expected .text") }
    }

    @Test("items returned newest first")
    func ordering() throws {
        let store = try makeStore()
        let a = ClipboardItem(id: UUID(), type: .text("a"), createdAt: Date(timeIntervalSince1970: 100), pinned: false, sourceAppBundleID: nil)
        let b = ClipboardItem(id: UUID(), type: .text("b"), createdAt: Date(timeIntervalSince1970: 200), pinned: false, sourceAppBundleID: nil)
        try store.add(a)
        try store.add(b)
        let items = try store.allItems()
        #expect(items.map(\.id) == [b.id, a.id])
    }

    @Test("delete removes by id")
    func deleteById() throws {
        let store = try makeStore()
        let item = ClipboardItem.text("rm")
        try store.add(item)
        try store.delete(id: item.id)
        let items = try store.allItems()
        #expect(items.isEmpty)
    }

    @Test("capacity trim drops oldest non-pinned beyond maxItems")
    func capacityTrim() throws {
        let store = try makeStore(maxItems: 3)
        for i in 0..<5 {
            let item = ClipboardItem(
                id: UUID(),
                type: .text("\(i)"),
                createdAt: Date(timeIntervalSince1970: TimeInterval(i)),
                pinned: false,
                sourceAppBundleID: nil
            )
            try store.add(item)
        }
        let items = try store.allItems()
        #expect(items.count == 3)
        // newest first: 4, 3, 2 — 0 and 1 dropped
        #expect(items.map { if case .text(let s) = $0.type { return s } else { return "" } } == ["4", "3", "2"])
    }

    @Test("duplicate text moves existing to top instead of adding new row")
    func duplicateTextDedup() throws {
        let store = try makeStore()
        let first = ClipboardItem(id: UUID(), type: .text("same"), createdAt: Date(timeIntervalSince1970: 100), pinned: false, sourceAppBundleID: nil)
        try store.add(first)
        let dup = ClipboardItem(id: UUID(), type: .text("same"), createdAt: Date(timeIntervalSince1970: 200), pinned: false, sourceAppBundleID: nil)
        try store.add(dup)
        let items = try store.allItems()
        #expect(items.count == 1)
        // The kept row should have the newer createdAt
        #expect(items.first?.createdAt == Date(timeIntervalSince1970: 200))
    }

    @Test("query filters by search term (case-insensitive)")
    func querySearch() throws {
        let store = try makeStore()
        try store.add(ClipboardItem.text("Hello World"))
        try store.add(ClipboardItem.text("Goodbye Moon"))
        let results = try store.query(search: "hello")
        #expect(results.count == 1)
        if case .text(let s) = results.first?.type { #expect(s == "Hello World") }
        else { Issue.record("Expected .text") }
    }

    @Test("publisher emits after add")
    func publisherEmits() async throws {
        let store = try makeStore()
        var received: [[ClipboardItem]] = []
        let cancellable = store.itemsPublisher.sink { received.append($0) }
        try store.add(ClipboardItem.text("a"))
        // Allow Combine to flush on main loop
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(received.contains { $0.count == 1 })
        cancellable.cancel()
    }

    @Test("dedup is stable across reopened store (SHA-256 hash, not Swift hashValue)")
    func dedupSurvivesReopen() throws {
        // Use a temp file path so we can close and reopen the same DB.
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("notchpaste-test-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            let q = try DatabaseQueue(path: url.path)
            let store = try ClipboardStore(dbQueue: q, maxItems: 50)
            try store.add(ClipboardItem.text("persisted"))
        } // store + queue go out of scope here

        // Reopen with a fresh queue/store (simulates app relaunch).
        let q2 = try DatabaseQueue(path: url.path)
        let store2 = try ClipboardStore(dbQueue: q2, maxItems: 50)
        try store2.add(ClipboardItem.text("persisted"))   // same content
        let items = try store2.allItems()
        #expect(items.count == 1, "Dedup must work across store reopens — got \(items.count) rows")
    }
}
