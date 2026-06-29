import Testing
import Foundation
import AppKit
import GRDB
@testable import NotchPaste

@Suite("ClipboardStore")
struct ClipboardStoreTests {

    /// 给每个测试一个隔离的内存 DB。
    func makeStore(maxItems: Int = ClipboardStore.defaultMaxItems, snapshotDelay: TimeInterval = 0.02) throws -> ClipboardStore {
        let dbQueue = try DatabaseQueue() // in-memory
        return try ClipboardStore(dbQueue: dbQueue, maxItems: maxItems, snapshotDelay: snapshotDelay)
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

    @Test("pinned items do not sort above newer recent items")
    func pinnedItemsDoNotSortAboveNewerRecentItems() throws {
        let store = try makeStore()
        let oldPinned = ClipboardItem(
            id: UUID(),
            type: .text("old pinned"),
            createdAt: Date(timeIntervalSince1970: 100),
            pinned: true,
            sourceAppBundleID: nil
        )
        let newer = ClipboardItem(
            id: UUID(),
            type: .text("newer"),
            createdAt: Date(timeIntervalSince1970: 200),
            pinned: false,
            sourceAppBundleID: nil
        )

        try store.add(oldPinned)
        try store.add(newer)

        let items = try store.allItems()
        #expect(items.map(\.id) == [newer.id, oldPinned.id])
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

    @Test("default capacity is larger than visible clipboard list count")
    func defaultCapacityIsLargerThanVisibleClipboardListCount() throws {
        let store = try makeStore()
        for i in 0..<250 {
            let item = ClipboardItem(
                id: UUID(),
                type: .text("default capacity \(i)"),
                createdAt: Date(timeIntervalSince1970: TimeInterval(i)),
                pinned: false,
                sourceAppBundleID: nil
            )
            try store.add(item)
        }

        #expect(try store.allItems().count == 250)
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

    @Test("memory filter matches store query")
    func memoryFilterMatchesStoreQuery() throws {
        let store = try makeStore(snapshotDelay: 0)
        let hello = ClipboardItem(id: UUID(), type: .text("Hello World"), createdAt: Date(timeIntervalSince1970: 100), pinned: true, sourceAppBundleID: nil)
        let moon = ClipboardItem(id: UUID(), type: .text("Goodbye Moon"), createdAt: Date(timeIntervalSince1970: 200), pinned: false, sourceAppBundleID: nil)
        try store.add(hello)
        try store.add(moon)

        let all = try store.allItems()
        #expect(ClipboardStore.filter(all, category: .all, search: "hello") == (try store.query(category: .all, search: "hello")))
        #expect(ClipboardStore.filter(all, category: .favorite) == (try store.query(category: .favorite)))
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

    @Test("publisher coalesces rapid adds")
    func publisherCoalescesRapidAdds() async throws {
        let store = try makeStore(maxItems: 50, snapshotDelay: 0.04)
        var received: [[ClipboardItem]] = []
        let cancellable = store.itemsPublisher.sink { received.append($0) }

        for index in 0..<10 {
            try store.add(ClipboardItem.text("rapid \(index)"))
        }

        #expect(received.map(\.count) == [0])
        try await Task.sleep(nanoseconds: 90_000_000)
        #expect(received.map(\.count) == [0, 10])
        cancellable.cancel()
    }

    @MainActor
    @Test("panel view model refreshes asynchronously and caches filtered items")
    func panelViewModelRefreshesAsynchronously() async throws {
        let store = try makeStore(snapshotDelay: 10)
        let item = ClipboardItem.text("async panel item")
        try store.add(item)
        let viewModel = PanelViewModel(
            store: store,
            paster: PasteService(),
            onCommit: { nil }
        )

        viewModel.searchTerm = "async"
        viewModel.refreshAsync()

        for _ in 0..<20 where viewModel.filteredItems.map(\.id) != [item.id] {
            try await Task.sleep(nanoseconds: 25_000_000)
        }

        #expect(viewModel.filteredItems.map(\.id) == [item.id])
    }

    @Test("file drag pasteboard item exposes file URL type")
    func fileDragPasteboardItemExposesFileURLType() throws {
        let url = URL(fileURLWithPath: "/tmp/notchpaste-drag-test.txt")
        let item = FileDragPasteboardFactory.makePasteboardItem(for: url)

        #expect(item.string(forType: .fileURL) == url.absoluteString)
        #expect(item.string(forType: .URL) == url.absoluteString)
    }

    @Test("file drag pasteboard items expose every file URL")
    func fileDragPasteboardItemsExposeEveryFileURL() throws {
        let urls = [
            URL(fileURLWithPath: "/tmp/notchpaste-drag-a.txt"),
            URL(fileURLWithPath: "/tmp/notchpaste-drag-b.txt")
        ]

        let items = FileDragPasteboardFactory.makePasteboardItems(for: urls)

        #expect(items.map { $0.string(forType: .fileURL) } == urls.map(\.absoluteString))
    }

    @Test("file drag starts after pointer movement threshold")
    func fileDragStartsAfterPointerMovementThreshold() {
        #expect(!FileDragGesturePolicy.shouldStartDrag(from: .zero, to: CGPoint(x: 2, y: 2)))
        #expect(FileDragGesturePolicy.shouldStartDrag(from: .zero, to: CGPoint(x: 5, y: 0)))
    }

    @Test("image drag pasteboard item exposes image data")
    func imageDragPasteboardItemExposesImageData() throws {
        let data = try #require(Self.makePNGData())
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("notchpaste-image-drag-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }

        let item = ImageDragPasteboardFactory.makePasteboardItem(for: data, fileURL: url)

        #expect(item.data(forType: .png) == data)
        #expect(item.data(forType: .tiff) != nil)
        #expect(item.string(forType: .fileURL) == url.absoluteString)
        #expect(FileManager.default.fileExists(atPath: url.path))
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

    static func makePNGData() -> Data? {
        let image = NSImage(size: NSSize(width: 4, height: 4))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: 4, height: 4).fill()
        image.unlockFocus()

        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff)
        else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

}
