# NotchPaste v0.1 (MVP) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现 NotchPaste v0.1 MVP —— 一个常驻 macOS 刘海右侧的文本剪贴板历史 app，支持点击 pill 或全局快捷键展开面板，选中后自动粘贴到当前应用。

**Architecture:** SwiftUI App + AppKit `NSPanel`/`NSStatusItem` 混合架构。Core 层（ClipboardMonitor / ClipboardStore / PasteService / HotkeyService / PreferencesStore）通过 Combine Publisher 解耦；UI 层（PillView / PanelView）订阅状态。SQLite (GRDB) 持久化 + 大内容走文件系统。LSUIElement 模式（无 Dock 图标）。

**Tech Stack:** Swift 5.10+, SwiftUI, AppKit, Combine, GRDB.swift 6.x, HotKey 0.2.x, Swift Testing, Xcode 15+, macOS 14 Sonoma 最低部署目标。

---

## File Structure

本次 v0.1 创建以下文件（标注每个文件的单一职责）：

```
NotchPaste/
├── NotchPaste.xcodeproj/                     — Xcode 项目
├── NotchPaste/
│   ├── App/
│   │   ├── NotchPasteApp.swift               — @main + AppDelegate；组装 services + 启动 windows
│   │   ├── Info.plist                        — LSUIElement=YES, NSAppTransportSecurity, etc
│   │   └── Assets.xcassets                   — app icon + 状态栏图标
│   ├── Core/
│   │   ├── ClipboardItem.swift               — 数据模型：UUID + ItemType + createdAt + pinned
│   │   ├── ClipboardMonitor.swift            — 轮询 NSPasteboard.changeCount，发布 AsyncStream<ClipboardItem>
│   │   ├── ClipboardStore.swift              — GRDB 持久化 + Publisher<[ClipboardItem]>
│   │   ├── PasteService.swift                — AXIsProcessTrusted + CGEvent 模拟 ⌘V
│   │   ├── HotkeyService.swift               — HotKey 包装，注册 ⇧⌘V 全局快捷键
│   │   └── PreferencesStore.swift            — UserDefaults 包装（v0.1 仅 maxItems / autoPasteEnabled）
│   ├── UI/
│   │   ├── Pill/
│   │   │   ├── PillWindow.swift              — NSPanel 子类（borderless / nonactivating / cross-space）
│   │   │   └── PillView.swift                — SwiftUI 视图：黑色圆角 + 状态点 + 数字
│   │   └── Panel/
│   │       ├── PanelWindow.swift             — NSPanel 子类，用于展开面板
│   │       ├── PanelView.swift               — 顶层 SwiftUI（搜索框 + 列表 + 键盘事件）
│   │       └── ItemRowView.swift             — 单行：图标 + 预览 + 时间戳
│   └── Util/
│       ├── ScreenGeometry.swift              — 主屏刘海安全区计算（pill 位置）
│       └── AppLogger.swift                   — os.Logger 包装
└── NotchPasteTests/
    ├── ClipboardItemTests.swift
    ├── ClipboardStoreTests.swift
    ├── ClipboardMonitorTests.swift
    └── ScreenGeometryTests.swift
```

**v0.1 范围限制（YAGNI）**：
- 不实现 NotchAppDetector / PositionManager（v0.3 才做避让）
- 不实现 Settings UI（v0.2）—— 偏好设置只通过 UserDefaults，无 GUI
- 不实现 MenuBarController（v0.3 fallback 时才需要）
- 不实现图片/文件类型（v0.2）—— `ItemType` 留扩展点但 v0.1 仅 `.text`
- 不实现 Pinned / 类型过滤（v0.2）—— `pinned` 字段建模但 UI 不暴露
- 不实现 ConcealedType 跳过（v0.2）

---

## Task 1: 初始化 Xcode 项目

**Files:**
- Create: `NotchPaste.xcodeproj/project.pbxproj` (via Xcode)
- Create: `NotchPaste/App/Info.plist`
- Create: `.gitignore`
- Create: `LICENSE` (MIT)
- Create: `README.md`

- [ ] **Step 1: 创建 Xcode 项目**

打开 Xcode → File → New → Project → macOS → App。
- Product Name: `NotchPaste`
- Team: 留空或选择个人 Apple ID（v0.1 不签名）
- Organization Identifier: `com.notchpaste`
- Bundle Identifier: `com.notchpaste.app`
- Interface: **SwiftUI**
- Language: **Swift**
- Minimum Deployment: **macOS 14.0**
- 取消勾选 "Include Tests"（我们用单独 target，下一步加）
- 取消勾选 "Use Core Data"
- 保存到 `/Users/kyle/codex project/pasteboard/`（即项目根目录）

完成后项目应位于 `/Users/kyle/codex project/pasteboard/NotchPaste.xcodeproj`。

- [ ] **Step 2: 修改 Info.plist 设置为 LSUIElement**

在 Xcode 的 NotchPaste target → Info 标签 → Custom macOS Application Target Properties 添加：

```
Application is agent (UIElement)  →  YES
```

或直接编辑 `NotchPaste/Info.plist`（如果使用 Generated 模式则在 target → Info 中加自定义键）：

```xml
<key>LSUIElement</key>
<true/>
<key>LSMinimumSystemVersion</key>
<string>14.0</string>
<key>NSHumanReadableCopyright</key>
<string>Copyright © 2026 NotchPaste. MIT Licensed.</string>
```

- [ ] **Step 3: 添加 Test Target**

Xcode → File → New → Target → macOS → Unit Testing Bundle
- Product Name: `NotchPasteTests`
- Project: NotchPaste
- Target to be tested: NotchPaste
- Testing System: **Swift Testing**

- [ ] **Step 4: 添加 SPM 依赖**

NotchPaste target → Package Dependencies → "+" 添加：
- `https://github.com/groue/GRDB.swift` — Up to Next Major Version 6.0.0
- `https://github.com/soffes/HotKey` — Up to Next Major Version 0.2.0

把 `GRDB` library 加到 NotchPaste target，把 `HotKey` 也加到 NotchPaste target。

- [ ] **Step 5: 写 .gitignore**

在 `/Users/kyle/codex project/pasteboard/.gitignore`：

```
# Xcode
build/
DerivedData/
*.xcuserstate
xcuserdata/
*.xcscmblueprint
*.xccheckout

# SPM
.build/
.swiftpm/
Package.resolved

# macOS
.DS_Store

# Brainstorm artifacts
.superpowers/

# Logs
*.log
```

- [ ] **Step 6: 写 LICENSE（MIT）**

`/Users/kyle/codex project/pasteboard/LICENSE`：

```
MIT License

Copyright (c) 2026 Kyle

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [ ] **Step 7: 写 README.md skeleton**

`/Users/kyle/codex project/pasteboard/README.md`：

```markdown
# NotchPaste

A macOS clipboard history app that lives in your notch and gracefully steps aside when other notch apps run.

**Status:** v0.1 MVP under development.

## Requirements

- macOS 14 Sonoma or later
- A MacBook with a notch (Pro/Air 14"/16" 2021+)

## Development

Open `NotchPaste.xcodeproj` in Xcode 15+.

## License

MIT — see [LICENSE](LICENSE).
```

- [ ] **Step 8: 初始化 git 并提交**

```bash
cd "/Users/kyle/codex project/pasteboard"
git init
git add .gitignore LICENSE README.md NotchPaste.xcodeproj NotchPaste NotchPasteTests
git commit -m "chore: initial Xcode project scaffolding"
```

- [ ] **Step 9: 验证项目可以构建运行**

```bash
xcodebuild -project NotchPaste.xcodeproj -scheme NotchPaste -configuration Debug build
```
Expected: `** BUILD SUCCEEDED **`

```bash
xcodebuild -project NotchPaste.xcodeproj -scheme NotchPaste test
```
Expected: 0 tests run, success exit code（test target 已存在但还没测试）。

---

## Task 2: ClipboardItem 数据模型

**Files:**
- Create: `NotchPaste/Core/ClipboardItem.swift`
- Test: `NotchPasteTests/ClipboardItemTests.swift`

- [ ] **Step 1: 写失败测试**

`NotchPasteTests/ClipboardItemTests.swift`：

```swift
import Testing
import Foundation
@testable import NotchPaste

@Suite("ClipboardItem")
struct ClipboardItemTests {

    @Test("text item equality and basic fields")
    func textItemFields() {
        let id = UUID()
        let date = Date(timeIntervalSince1970: 1_000_000)
        let item = ClipboardItem(
            id: id,
            type: .text("hello"),
            createdAt: date,
            pinned: false,
            sourceAppBundleID: "com.apple.Safari"
        )
        #expect(item.id == id)
        #expect(item.createdAt == date)
        #expect(item.pinned == false)
        #expect(item.sourceAppBundleID == "com.apple.Safari")
        if case .text(let s) = item.type {
            #expect(s == "hello")
        } else {
            Issue.record("Expected .text type")
        }
    }

    @Test("preview returns first 100 chars for long text")
    func previewLongText() {
        let long = String(repeating: "a", count: 500)
        let item = ClipboardItem.text(long)
        #expect(item.preview.count <= 100)
        #expect(item.preview.hasPrefix("a"))
    }

    @Test("preview returns whole text for short text")
    func previewShortText() {
        let item = ClipboardItem.text("short")
        #expect(item.preview == "short")
    }

    @Test("convenience text constructor sets fields")
    func textConvenience() {
        let item = ClipboardItem.text("hi")
        #expect(item.pinned == false)
        if case .text(let s) = item.type { #expect(s == "hi") }
        else { Issue.record("Expected .text") }
    }
}
```

- [ ] **Step 2: 运行测试，确认失败**

```bash
xcodebuild -project NotchPaste.xcodeproj -scheme NotchPaste test -only-testing:NotchPasteTests/ClipboardItemTests
```
Expected: 编译失败 — `cannot find 'ClipboardItem' in scope`。

- [ ] **Step 3: 写 ClipboardItem.swift 最小实现**

`NotchPaste/Core/ClipboardItem.swift`：

```swift
import Foundation

/// 剪贴板内容类型。v0.1 仅 .text；image/file 在 v0.2 加入。
enum ItemType: Equatable {
    case text(String)
    // case image(Data)        — v0.2
    // case file([URL])        — v0.2
}

/// 剪贴板历史中的一项。不可变值类型；修改 pinned 用 `withPinned(_:)`。
struct ClipboardItem: Identifiable, Equatable {
    let id: UUID
    let type: ItemType
    let createdAt: Date
    var pinned: Bool
    var sourceAppBundleID: String?

    /// 最多 100 字符的预览文本。
    var preview: String {
        switch type {
        case .text(let s):
            return String(s.prefix(100))
        }
    }

    /// 便捷构造器：只给文本，其余字段用默认值。
    static func text(_ s: String, sourceAppBundleID: String? = nil) -> ClipboardItem {
        ClipboardItem(
            id: UUID(),
            type: .text(s),
            createdAt: Date(),
            pinned: false,
            sourceAppBundleID: sourceAppBundleID
        )
    }
}
```

- [ ] **Step 4: 运行测试，确认通过**

```bash
xcodebuild -project NotchPaste.xcodeproj -scheme NotchPaste test -only-testing:NotchPasteTests/ClipboardItemTests
```
Expected: 4 tests passed.

- [ ] **Step 5: 提交**

```bash
git add NotchPaste/Core/ClipboardItem.swift NotchPasteTests/ClipboardItemTests.swift
git commit -m "feat(core): add ClipboardItem data model"
```

---

## Task 3: AppLogger 工具

**Files:**
- Create: `NotchPaste/Util/AppLogger.swift`

- [ ] **Step 1: 写实现（无测试 —— 简单包装）**

`NotchPaste/Util/AppLogger.swift`：

```swift
import os

/// 项目统一日志入口，subsystem = com.notchpaste.app。
enum AppLogger {
    static let app = Logger(subsystem: "com.notchpaste.app", category: "app")
    static let clipboard = Logger(subsystem: "com.notchpaste.app", category: "clipboard")
    static let store = Logger(subsystem: "com.notchpaste.app", category: "store")
    static let paste = Logger(subsystem: "com.notchpaste.app", category: "paste")
    static let hotkey = Logger(subsystem: "com.notchpaste.app", category: "hotkey")
    static let ui = Logger(subsystem: "com.notchpaste.app", category: "ui")
}
```

- [ ] **Step 2: 编译验证**

```bash
xcodebuild -project NotchPaste.xcodeproj -scheme NotchPaste build
```
Expected: BUILD SUCCEEDED。

- [ ] **Step 3: 提交**

```bash
git add NotchPaste/Util/AppLogger.swift
git commit -m "feat(util): add AppLogger wrapping os.Logger"
```

---

## Task 4: PreferencesStore（v0.1 最小集）

**Files:**
- Create: `NotchPaste/Core/PreferencesStore.swift`

v0.1 仅需两项偏好：`maxItems`（默认 200）、`autoPasteEnabled`（默认 true）。

- [ ] **Step 1: 写实现（直接做，UserDefaults 包装无需复杂测试）**

`NotchPaste/Core/PreferencesStore.swift`：

```swift
import Foundation
import Combine

/// UserDefaults 包装，集中管理用户偏好。线程安全，可观察。
final class PreferencesStore: ObservableObject {
    static let shared = PreferencesStore()

    private let defaults: UserDefaults

    private enum Key {
        static let maxItems = "NotchPaste.maxItems"
        static let autoPasteEnabled = "NotchPaste.autoPasteEnabled"
    }

    @Published var maxItems: Int {
        didSet { defaults.set(maxItems, forKey: Key.maxItems) }
    }

    @Published var autoPasteEnabled: Bool {
        didSet { defaults.set(autoPasteEnabled, forKey: Key.autoPasteEnabled) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // 注意：直接读 .integer(forKey:) 时，未设置返回 0；这里用 object 检查
        if let v = defaults.object(forKey: Key.maxItems) as? Int {
            self.maxItems = v
        } else {
            self.maxItems = 200
        }
        if let v = defaults.object(forKey: Key.autoPasteEnabled) as? Bool {
            self.autoPasteEnabled = v
        } else {
            self.autoPasteEnabled = true
        }
    }
}
```

- [ ] **Step 2: 编译验证**

```bash
xcodebuild -project NotchPaste.xcodeproj -scheme NotchPaste build
```
Expected: BUILD SUCCEEDED。

- [ ] **Step 3: 提交**

```bash
git add NotchPaste/Core/PreferencesStore.swift
git commit -m "feat(core): add PreferencesStore with maxItems and autoPasteEnabled"
```

---

## Task 5: ClipboardStore（GRDB 持久化）

**Files:**
- Create: `NotchPaste/Core/ClipboardStore.swift`
- Test: `NotchPasteTests/ClipboardStoreTests.swift`

ClipboardStore 用 GRDB 提供：增删改查 + 容量裁剪 + Publisher 通知。

- [ ] **Step 1: 写失败测试 — add / list 基本流程**

`NotchPasteTests/ClipboardStoreTests.swift`：

```swift
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
}
```

- [ ] **Step 2: 运行测试，确认失败**

```bash
xcodebuild -project NotchPaste.xcodeproj -scheme NotchPaste test -only-testing:NotchPasteTests/ClipboardStoreTests
```
Expected: 编译失败 — `cannot find 'ClipboardStore' in scope`。

- [ ] **Step 3: 写 ClipboardStore.swift 实现**

`NotchPaste/Core/ClipboardStore.swift`：

```swift
import Foundation
import Combine
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

    // MARK: - Errors

    enum StoreError: Error {
        case databaseUnavailable
    }

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
                  AND pinned = 0
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
        guard
            let idString: String = row["id"],
            let id = UUID(uuidString: idString),
            let kind: String = row["kind"],
            let createdAtRaw: Double = row["created_at"]
        else { return nil }
        let pinned: Bool = row["pinned"] ?? false
        let sourceApp: String? = row["source_app_bundle_id"]

        let type: ItemType
        switch kind {
        case "text":
            guard let text: String = row["text_content"] else { return nil }
            type = .text(text)
        default:
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
        case .text(let s): return "text:\(s.hashValue)"
        }
    }
}
```

- [ ] **Step 4: 运行测试，确认通过**

```bash
xcodebuild -project NotchPaste.xcodeproj -scheme NotchPaste test -only-testing:NotchPasteTests/ClipboardStoreTests
```
Expected: 7 tests passed.

- [ ] **Step 5: 提交**

```bash
git add NotchPaste/Core/ClipboardStore.swift NotchPasteTests/ClipboardStoreTests.swift
git commit -m "feat(core): add ClipboardStore with GRDB persistence and dedup"
```

---

## Task 6: ClipboardMonitor（轮询 NSPasteboard）

**Files:**
- Create: `NotchPaste/Core/ClipboardMonitor.swift`
- Test: `NotchPasteTests/ClipboardMonitorTests.swift`

监听系统剪贴板变化，检测到新内容时发布 `ClipboardItem`。

- [ ] **Step 1: 写失败测试 — 提取文本**

`NotchPasteTests/ClipboardMonitorTests.swift`：

```swift
import Testing
import AppKit
@testable import NotchPaste

@Suite("ClipboardMonitor")
struct ClipboardMonitorTests {

    @Test("extractItem returns nil if no usable types")
    func extractEmpty() {
        let pb = NSPasteboard(name: NSPasteboard.Name("NotchPasteTest-empty"))
        pb.clearContents()
        let item = ClipboardMonitor.extractItem(from: pb, sourceAppBundleID: nil)
        #expect(item == nil)
    }

    @Test("extractItem returns text item for plain string")
    func extractText() {
        let pb = NSPasteboard(name: NSPasteboard.Name("NotchPasteTest-text"))
        pb.clearContents()
        pb.setString("clipboard text", forType: .string)
        let item = ClipboardMonitor.extractItem(from: pb, sourceAppBundleID: "com.test.app")
        #expect(item != nil)
        if case .text(let s) = item?.type {
            #expect(s == "clipboard text")
        } else {
            Issue.record("Expected .text")
        }
        #expect(item?.sourceAppBundleID == "com.test.app")
    }

    @Test("extractItem ignores empty string")
    func extractEmptyString() {
        let pb = NSPasteboard(name: NSPasteboard.Name("NotchPasteTest-emptystr"))
        pb.clearContents()
        pb.setString("", forType: .string)
        let item = ClipboardMonitor.extractItem(from: pb, sourceAppBundleID: nil)
        #expect(item == nil)
    }
}
```

- [ ] **Step 2: 运行测试，确认失败**

```bash
xcodebuild -project NotchPaste.xcodeproj -scheme NotchPaste test -only-testing:NotchPasteTests/ClipboardMonitorTests
```
Expected: 编译失败 — `cannot find 'ClipboardMonitor' in scope`。

- [ ] **Step 3: 写 ClipboardMonitor.swift 实现**

`NotchPaste/Core/ClipboardMonitor.swift`：

```swift
import Foundation
import AppKit
import os

/// 周期性轮询系统剪贴板（NSPasteboard.general），检测新内容并通过 AsyncStream 发布。
///
/// 设计说明：
/// - macOS 没有 pasteboard change notification，必须轮询 changeCount。
/// - 0.5s 是 Maccy 等同类 app 的成熟取值，对 CPU 影响极小。
/// - `extractItem(from:sourceAppBundleID:)` 是纯函数，便于单测。
final class ClipboardMonitor {

    private let pasteboard: NSPasteboard
    private let interval: TimeInterval
    private var timer: Timer?
    private var lastChangeCount: Int

    private var continuation: AsyncStream<ClipboardItem>.Continuation?

    /// 启动后通过该流发布新项；调用 `stop()` 完成流。
    let stream: AsyncStream<ClipboardItem>

    init(pasteboard: NSPasteboard = .general, interval: TimeInterval = 0.5) {
        self.pasteboard = pasteboard
        self.interval = interval
        self.lastChangeCount = pasteboard.changeCount

        var c: AsyncStream<ClipboardItem>.Continuation!
        self.stream = AsyncStream<ClipboardItem> { cont in c = cont }
        self.continuation = c
    }

    func start() {
        guard timer == nil else { return }
        let t = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        AppLogger.clipboard.info("ClipboardMonitor started, interval=\(self.interval, privacy: .public)s")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        continuation?.finish()
    }

    private func tick() {
        let current = pasteboard.changeCount
        guard current != lastChangeCount else { return }
        lastChangeCount = current

        let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard let item = Self.extractItem(from: pasteboard, sourceAppBundleID: bundleID) else { return }
        AppLogger.clipboard.debug("New clipboard item captured: \(item.preview, privacy: .private)")
        continuation?.yield(item)
    }

    /// 从给定 pasteboard 提取一个 ClipboardItem。
    /// - 返回 nil 表示当前 pasteboard 没有 v0.1 支持的内容（v0.1 仅 .text）。
    /// - v0.2 会扩展 image / file；本签名保持不变。
    static func extractItem(from pasteboard: NSPasteboard, sourceAppBundleID: String?) -> ClipboardItem? {
        // v0.1: 仅文本
        if let s = pasteboard.string(forType: .string), !s.isEmpty {
            return ClipboardItem.text(s, sourceAppBundleID: sourceAppBundleID)
        }
        return nil
    }
}
```

- [ ] **Step 4: 运行测试，确认通过**

```bash
xcodebuild -project NotchPaste.xcodeproj -scheme NotchPaste test -only-testing:NotchPasteTests/ClipboardMonitorTests
```
Expected: 3 tests passed.

- [ ] **Step 5: 提交**

```bash
git add NotchPaste/Core/ClipboardMonitor.swift NotchPasteTests/ClipboardMonitorTests.swift
git commit -m "feat(core): add ClipboardMonitor polling NSPasteboard"
```

---

## Task 7: PasteService（自动 ⌘V 注入）

**Files:**
- Create: `NotchPaste/Core/PasteService.swift`

无单元测试 —— 需要真实辅助功能权限和 CGEvent 系统服务，单测不可靠；改为手动验收。

- [ ] **Step 1: 写实现**

`NotchPaste/Core/PasteService.swift`：

```swift
import Foundation
import AppKit
import Carbon.HIToolbox
import os

/// 把内容写入系统剪贴板，并（若已授权辅助功能）模拟 ⌘V 注入到当前焦点应用。
final class PasteService {

    private let preferences: PreferencesStore

    init(preferences: PreferencesStore = .shared) {
        self.preferences = preferences
    }

    /// 把 item 内容写入系统剪贴板。
    /// 若 `autoPasteEnabled` 且辅助功能已授权，进一步模拟 ⌘V。
    func paste(_ item: ClipboardItem) {
        copyToPasteboard(item)
        guard preferences.autoPasteEnabled else {
            AppLogger.paste.info("auto-paste disabled in prefs; clipboard updated only")
            return
        }
        guard isAccessibilityTrusted() else {
            AppLogger.paste.notice("accessibility not granted; clipboard updated only")
            return
        }
        simulateCommandV()
    }

    /// 检查辅助功能权限。第一次会弹系统对话框（promptIfNeeded=true）。
    @discardableResult
    func isAccessibilityTrusted(promptIfNeeded: Bool = false) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue()
        let opts: [CFString: Any] = [key: promptIfNeeded]
        return AXIsProcessTrustedWithOptions(opts as CFDictionary)
    }

    // MARK: - Internals

    private func copyToPasteboard(_ item: ClipboardItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.type {
        case .text(let s):
            pb.setString(s, forType: .string)
        }
    }

    private func simulateCommandV() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let vCode = CGKeyCode(kVK_ANSI_V)

        let down = CGEvent(keyboardEventSource: src, virtualKey: vCode, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: src, virtualKey: vCode, keyDown: false)
        up?.flags = .maskCommand

        // 微小延迟，让目标 app 有机会处理 pasteboard 写入
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
            AppLogger.paste.debug("posted ⌘V")
        }
    }
}
```

- [ ] **Step 2: 编译验证**

```bash
xcodebuild -project NotchPaste.xcodeproj -scheme NotchPaste build
```
Expected: BUILD SUCCEEDED。

- [ ] **Step 3: 提交**

```bash
git add NotchPaste/Core/PasteService.swift
git commit -m "feat(core): add PasteService with accessibility-gated ⌘V injection"
```

---

## Task 8: HotkeyService（全局快捷键）

**Files:**
- Create: `NotchPaste/Core/HotkeyService.swift`

- [ ] **Step 1: 写实现**

`NotchPaste/Core/HotkeyService.swift`：

```swift
import Foundation
import HotKey
import os

/// 全局快捷键注册器。v0.1 注册一个固定快捷键 ⇧⌘V → 触发回调。
final class HotkeyService {

    /// 注册成功后保留引用；释放即注销。
    private var hotKey: HotKey?

    /// 用户偏好关闭/重绑后，重新调用 register。
    func register(handler: @escaping () -> Void) {
        hotKey = HotKey(key: .v, modifiers: [.command, .shift])
        hotKey?.keyDownHandler = {
            AppLogger.hotkey.debug("global hotkey ⇧⌘V fired")
            handler()
        }
        AppLogger.hotkey.info("registered ⇧⌘V")
    }

    func unregister() {
        hotKey = nil
    }
}
```

- [ ] **Step 2: 编译验证**

```bash
xcodebuild -project NotchPaste.xcodeproj -scheme NotchPaste build
```
Expected: BUILD SUCCEEDED。

- [ ] **Step 3: 提交**

```bash
git add NotchPaste/Core/HotkeyService.swift
git commit -m "feat(core): add HotkeyService for ⇧⌘V global hotkey"
```

---

## Task 9: ScreenGeometry（刘海安全区计算）

**Files:**
- Create: `NotchPaste/Util/ScreenGeometry.swift`
- Test: `NotchPasteTests/ScreenGeometryTests.swift`

计算主屏刘海周围的"右侧 pill 起点位置"。`NSScreen.safeAreaInsets` 在 macOS 12+ 给出刘海的 top inset，结合屏幕几何可得到刘海中心和左右两端 x 坐标。

- [ ] **Step 1: 写失败测试**

`NotchPasteTests/ScreenGeometryTests.swift`：

```swift
import Testing
import AppKit
@testable import NotchPaste

@Suite("ScreenGeometry")
struct ScreenGeometryTests {

    /// 1512×982 大致是 14" MBP 的逻辑分辨率。刘海宽度约 200pt，居中在屏幕顶部。
    @Test("notchFrame returns nil for screens without notch (auxiliaryTopLeftArea zero)")
    func noNotchReturnsNil() {
        let frame = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let result = ScreenGeometry.notchFrame(
            screenFrame: frame,
            auxiliaryTopLeftArea: nil,
            auxiliaryTopRightArea: nil
        )
        #expect(result == nil)
    }

    @Test("notchFrame returns notch rect when auxiliary areas are present")
    func notchPresent() {
        let screen = NSRect(x: 0, y: 0, width: 1512, height: 982)
        // 在带刘海机型上，auxiliaryTopLeftArea 是刘海左侧菜单栏区域
        let leftAux = NSRect(x: 0, y: 950, width: 656, height: 32)
        let rightAux = NSRect(x: 856, y: 950, width: 656, height: 32)
        let notch = ScreenGeometry.notchFrame(
            screenFrame: screen,
            auxiliaryTopLeftArea: leftAux,
            auxiliaryTopRightArea: rightAux
        )
        #expect(notch != nil)
        #expect(notch?.minX == 656)
        #expect(notch?.maxX == 856)
        #expect(notch?.width == 200)
    }

    @Test("pillFrame on right side sits flush against notch right edge")
    func pillFrameRight() {
        let notch = NSRect(x: 656, y: 950, width: 200, height: 32)
        let pill = ScreenGeometry.pillFrame(
            side: .right,
            notch: notch,
            pillSize: NSSize(width: 60, height: 24)
        )
        #expect(pill.minX == notch.maxX)             // 紧贴刘海右缘
        #expect(pill.maxX == notch.maxX + 60)
        #expect(pill.height == 24)
        #expect(pill.maxY == notch.maxY)             // 顶端对齐刘海顶端
    }

    @Test("pillFrame on left side sits flush against notch left edge")
    func pillFrameLeft() {
        let notch = NSRect(x: 656, y: 950, width: 200, height: 32)
        let pill = ScreenGeometry.pillFrame(
            side: .left,
            notch: notch,
            pillSize: NSSize(width: 60, height: 24)
        )
        #expect(pill.maxX == notch.minX)
        #expect(pill.minX == notch.minX - 60)
        #expect(pill.maxY == notch.maxY)
    }
}
```

- [ ] **Step 2: 运行测试，确认失败**

```bash
xcodebuild -project NotchPaste.xcodeproj -scheme NotchPaste test -only-testing:NotchPasteTests/ScreenGeometryTests
```
Expected: 编译失败 — `cannot find 'ScreenGeometry' in scope`。

- [ ] **Step 3: 写 ScreenGeometry.swift**

`NotchPaste/Util/ScreenGeometry.swift`：

```swift
import Foundation
import AppKit

/// 刘海周围空间的几何计算。所有方法都是纯函数，便于单测。
enum ScreenGeometry {

    enum NotchSide {
        case left, right
    }

    /// 根据 NSScreen 的辅助区域推断刘海矩形。
    /// 在带刘海的 Mac 上，`auxiliaryTopLeftArea` / `auxiliaryTopRightArea` 是菜单栏被刘海切开的两段。
    /// 不带刘海时这两个属性返回 nil。
    static func notchFrame(
        screenFrame: NSRect,
        auxiliaryTopLeftArea: NSRect?,
        auxiliaryTopRightArea: NSRect?
    ) -> NSRect? {
        guard let left = auxiliaryTopLeftArea,
              let right = auxiliaryTopRightArea else {
            return nil
        }
        let x = left.maxX
        let width = right.minX - left.maxX
        guard width > 0 else { return nil }
        return NSRect(
            x: x,
            y: left.minY,
            width: width,
            height: left.height
        )
    }

    /// 给定刘海矩形和 pill 尺寸，计算 pill 应放置的 frame。
    /// pill 顶端对齐刘海顶端，紧贴刘海一侧。
    static func pillFrame(
        side: NotchSide,
        notch: NSRect,
        pillSize: NSSize
    ) -> NSRect {
        let y = notch.maxY - pillSize.height
        let x: CGFloat
        switch side {
        case .right: x = notch.maxX
        case .left:  x = notch.minX - pillSize.width
        }
        return NSRect(x: x, y: y, width: pillSize.width, height: pillSize.height)
    }

    /// 用主屏当前几何快速算出右侧 pill frame。
    /// 主屏无刘海时返回 nil（v0.1 不支持非刘海机型，调用方需要做菜单栏 fallback —— v0.3 才接入）。
    static func currentRightPillFrame(pillSize: NSSize) -> NSRect? {
        guard let screen = NSScreen.main else { return nil }
        guard let notch = notchFrame(
            screenFrame: screen.frame,
            auxiliaryTopLeftArea: screen.auxiliaryTopLeftArea,
            auxiliaryTopRightArea: screen.auxiliaryTopRightArea
        ) else { return nil }
        return pillFrame(side: .right, notch: notch, pillSize: pillSize)
    }
}
```

- [ ] **Step 4: 运行测试，确认通过**

```bash
xcodebuild -project NotchPaste.xcodeproj -scheme NotchPaste test -only-testing:NotchPasteTests/ScreenGeometryTests
```
Expected: 4 tests passed.

- [ ] **Step 5: 提交**

```bash
git add NotchPaste/Util/ScreenGeometry.swift NotchPasteTests/ScreenGeometryTests.swift
git commit -m "feat(util): add ScreenGeometry with notch-aware pill positioning"
```

---

## Task 10: PillView（SwiftUI 视图）

**Files:**
- Create: `NotchPaste/UI/Pill/PillView.swift`

- [ ] **Step 1: 写实现**

`NotchPaste/UI/Pill/PillView.swift`：

```swift
import SwiftUI

/// 常驻刘海右侧的 pill 视图。
/// 显示蓝色状态点 + 当前历史条数。复制事件触发时短暂膨胀并显示预览。
struct PillView: View {

    let itemCount: Int
    let copyHint: String?       // 非 nil 时显示预览文本（最近一次复制）；外部计时器控制清空
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.cyan)
                .frame(width: 6, height: 6)
            if let hint = copyHint {
                Text(hint)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 200, alignment: .leading)
                    .transition(.opacity)
            } else {
                Text("\(itemCount)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture { onTap() }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: copyHint)
    }
}

#Preview {
    PillView(itemCount: 42, copyHint: nil, onTap: {})
        .padding()
        .background(Color.gray)
}
```

- [ ] **Step 2: 编译验证**

```bash
xcodebuild -project NotchPaste.xcodeproj -scheme NotchPaste build
```
Expected: BUILD SUCCEEDED。

- [ ] **Step 3: 提交**

```bash
git add NotchPaste/UI/Pill/PillView.swift
git commit -m "feat(ui): add PillView with status dot and item count"
```

---

## Task 11: PillWindow（NSPanel 子类）

**Files:**
- Create: `NotchPaste/UI/Pill/PillWindow.swift`

- [ ] **Step 1: 写实现**

`NotchPaste/UI/Pill/PillWindow.swift`：

```swift
import AppKit
import SwiftUI

/// 承载 PillView 的 NSPanel：无边框、不抢焦、置顶、跨 Space 常驻。
final class PillWindow: NSPanel {

    init(contentSize: NSSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.isMovable = false
        self.hidesOnDeactivate = false
    }

    /// SwiftUI 内容容器。调用方传入闭包构造视图。
    func setContent<V: View>(_ view: V) {
        let host = NSHostingView(rootView: view)
        host.translatesAutoresizingMaskIntoConstraints = true
        host.frame = NSRect(origin: .zero, size: self.frame.size)
        host.autoresizingMask = [.width, .height]
        self.contentView = host
    }

    /// 不接受 keyWindow，避免抢焦点。
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
```

- [ ] **Step 2: 编译验证**

```bash
xcodebuild -project NotchPaste.xcodeproj -scheme NotchPaste build
```
Expected: BUILD SUCCEEDED。

- [ ] **Step 3: 提交**

```bash
git add NotchPaste/UI/Pill/PillWindow.swift
git commit -m "feat(ui): add PillWindow NSPanel subclass"
```

---

## Task 12: ItemRowView（列表单行）

**Files:**
- Create: `NotchPaste/UI/Panel/ItemRowView.swift`

- [ ] **Step 1: 写实现**

`NotchPaste/UI/Panel/ItemRowView.swift`：

```swift
import SwiftUI

struct ItemRowView: View {

    let item: ClipboardItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            iconView
                .frame(width: 16, alignment: .center)
                .foregroundStyle(.cyan)
            Text(item.preview)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(relativeTime(for: item.createdAt))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.white.opacity(0.12) : .clear)
        )
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var iconView: some View {
        switch item.type {
        case .text:
            Image(systemName: "doc.plaintext")
        }
    }

    private func relativeTime(for date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }
}
```

- [ ] **Step 2: 编译验证**

```bash
xcodebuild -project NotchPaste.xcodeproj -scheme NotchPaste build
```
Expected: BUILD SUCCEEDED。

- [ ] **Step 3: 提交**

```bash
git add NotchPaste/UI/Panel/ItemRowView.swift
git commit -m "feat(ui): add ItemRowView for clipboard list rows"
```

---

## Task 13: PanelView（展开面板顶层视图）

**Files:**
- Create: `NotchPaste/UI/Panel/PanelView.swift`

v0.1 简化为：搜索框 + 列表（不带侧栏）。侧栏 v0.2 类型过滤时再加。

- [ ] **Step 1: 写实现**

`NotchPaste/UI/Panel/PanelView.swift`：

```swift
import SwiftUI
import Combine

/// 展开面板的顶层视图。响应键盘 ↑↓ Enter Esc。
struct PanelView: View {

    @ObservedObject var viewModel: PanelViewModel

    var body: some View {
        VStack(spacing: 0) {
            searchBar
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 6)
            Divider().opacity(0.2)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(viewModel.filteredItems.enumerated()), id: \.element.id) { idx, item in
                            ItemRowView(item: item, isSelected: idx == viewModel.selectedIndex)
                                .id(item.id)
                                .onTapGesture {
                                    viewModel.selectedIndex = idx
                                    viewModel.commitSelection()
                                }
                        }
                    }
                    .padding(8)
                }
                .onChange(of: viewModel.selectedIndex) { _, new in
                    if let item = viewModel.filteredItems[safe: new] {
                        proxy.scrollTo(item.id, anchor: .center)
                    }
                }
            }
        }
        .frame(width: 360, height: 480)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.08))
        )
        .onAppear { viewModel.refresh() }
    }

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search", text: $viewModel.searchTerm)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.06)))
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
```

- [ ] **Step 2: 添加 PanelViewModel（在同一文件下方追加）**

继续在 `NotchPaste/UI/Panel/PanelView.swift` 文件底部添加：

```swift
import Combine

/// PanelView 的状态承载。把 store / paste 服务从 UI 解耦。
@MainActor
final class PanelViewModel: ObservableObject {

    @Published var items: [ClipboardItem] = []
    @Published var searchTerm: String = ""
    @Published var selectedIndex: Int = 0

    var filteredItems: [ClipboardItem] {
        let q = searchTerm.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return items }
        return items.filter {
            switch $0.type {
            case .text(let s): return s.lowercased().contains(q)
            }
        }
    }

    private let store: ClipboardStore
    private let paster: PasteService
    private let onCommit: () -> Void
    private var cancellables = Set<AnyCancellable>()

    init(store: ClipboardStore, paster: PasteService, onCommit: @escaping () -> Void) {
        self.store = store
        self.paster = paster
        self.onCommit = onCommit
        store.itemsPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] new in
                self?.items = new
                if (self?.selectedIndex ?? 0) >= new.count {
                    self?.selectedIndex = max(0, new.count - 1)
                }
            }
            .store(in: &cancellables)
    }

    func refresh() {
        items = (try? store.allItems()) ?? []
        selectedIndex = 0
    }

    func selectionUp() {
        guard !filteredItems.isEmpty else { return }
        selectedIndex = max(0, selectedIndex - 1)
    }

    func selectionDown() {
        guard !filteredItems.isEmpty else { return }
        selectedIndex = min(filteredItems.count - 1, selectedIndex + 1)
    }

    func commitSelection() {
        guard let item = filteredItems[safe: selectedIndex] else { return }
        paster.paste(item)
        onCommit()    // 关闭面板
    }
}
```

- [ ] **Step 3: 编译验证**

```bash
xcodebuild -project NotchPaste.xcodeproj -scheme NotchPaste build
```
Expected: BUILD SUCCEEDED。

- [ ] **Step 4: 提交**

```bash
git add NotchPaste/UI/Panel/PanelView.swift
git commit -m "feat(ui): add PanelView and PanelViewModel"
```

---

## Task 14: PanelWindow（NSPanel + 键盘事件）

**Files:**
- Create: `NotchPaste/UI/Panel/PanelWindow.swift`

- [ ] **Step 1: 写实现**

`NotchPaste/UI/Panel/PanelWindow.swift`：

```swift
import AppKit
import SwiftUI
import Carbon.HIToolbox

/// 展开后的剪贴板面板窗口。失焦自动关闭；处理键盘 ↑/↓/Enter/Esc。
final class PanelWindow: NSPanel {

    private weak var viewModel: PanelViewModel?

    init(contentSize: NSSize, viewModel: PanelViewModel) {
        super.init(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.viewModel = viewModel
        self.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true
        self.isMovable = false
        self.becomesKeyOnlyIfNeeded = false

        let host = NSHostingView(rootView: PanelView(viewModel: viewModel))
        host.frame = NSRect(origin: .zero, size: contentSize)
        host.autoresizingMask = [.width, .height]
        self.contentView = host
    }

    override var canBecomeKey: Bool { true }     // 接受按键事件
    override var canBecomeMain: Bool { false }

    override func resignKey() {
        super.resignKey()
        // 失焦自动关闭
        DispatchQueue.main.async { [weak self] in self?.close() }
    }

    override func keyDown(with event: NSEvent) {
        guard let vm = viewModel else { return super.keyDown(with: event) }
        switch Int(event.keyCode) {
        case kVK_UpArrow:
            vm.selectionUp()
        case kVK_DownArrow:
            vm.selectionDown()
        case kVK_Return:
            // 先关再粘贴：让焦点回到原 app，再注入 ⌘V
            self.orderOut(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                vm.commitSelection()
            }
        case kVK_Escape:
            self.orderOut(nil)
        default:
            super.keyDown(with: event)
        }
    }
}
```

- [ ] **Step 2: 编译验证**

```bash
xcodebuild -project NotchPaste.xcodeproj -scheme NotchPaste build
```
Expected: BUILD SUCCEEDED。

- [ ] **Step 3: 提交**

```bash
git add NotchPaste/UI/Panel/PanelWindow.swift
git commit -m "feat(ui): add PanelWindow with keyboard navigation"
```

---

## Task 15: AppDelegate 装配与启动

**Files:**
- Modify: `NotchPaste/App/NotchPasteApp.swift`

把所有服务串起来：监听剪贴板 → 写库 → 更新 pill；快捷键 / 点击 pill → 弹面板。

- [ ] **Step 1: 改写 NotchPasteApp.swift**

替换 Xcode 默认生成的 `NotchPaste/App/NotchPasteApp.swift` 为：

```swift
import SwiftUI
import AppKit
import Combine

@main
struct NotchPasteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // LSUIElement=YES 时无需主窗口；用 Settings scene 占位。
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var monitor: ClipboardMonitor!
    private var store: ClipboardStore!
    private var paster: PasteService!
    private var hotkey: HotkeyService!
    private var prefs: PreferencesStore!

    private var pillWindow: PillWindow!
    private var panelWindow: PanelWindow?
    private var panelVM: PanelViewModel!

    private var cancellables = Set<AnyCancellable>()
    private var copyHintTimer: Timer?

    @Published private var pillState = PillState(itemCount: 0, copyHint: nil)

    func applicationDidFinishLaunching(_ notification: Notification) {
        prefs = .shared
        do {
            store = try ClipboardStore(maxItems: prefs.maxItems)
        } catch {
            AppLogger.app.error("Failed to open ClipboardStore: \(error.localizedDescription, privacy: .public)")
            NSApp.terminate(nil)
            return
        }
        paster = PasteService(preferences: prefs)
        monitor = ClipboardMonitor()
        hotkey = HotkeyService()

        panelVM = PanelViewModel(store: store, paster: paster) { [weak self] in
            self?.panelWindow?.orderOut(nil)
        }

        setupPillWindow()
        wireMonitorToStore()
        wireStoreToPill()
        wireHotkey()

        monitor.start()
        AppLogger.app.info("NotchPaste launched")
    }

    // MARK: - Setup

    private struct PillState: Equatable {
        var itemCount: Int
        var copyHint: String?
    }

    private func setupPillWindow() {
        let pillSize = NSSize(width: 60, height: 24)
        pillWindow = PillWindow(contentSize: pillSize)
        let view = PillContainer(state: $pillState) { [weak self] in
            self?.togglePanel()
        }
        pillWindow.setContent(view)

        if let frame = ScreenGeometry.currentRightPillFrame(pillSize: pillSize) {
            pillWindow.setFrame(frame, display: true)
        } else {
            // v0.1 不支持非刘海机型 — 暂时放在右上角
            if let screen = NSScreen.main {
                let f = NSRect(x: screen.frame.maxX - pillSize.width - 8,
                               y: screen.frame.maxY - pillSize.height - 4,
                               width: pillSize.width, height: pillSize.height)
                pillWindow.setFrame(f, display: true)
            }
        }
        pillWindow.orderFrontRegardless()
    }

    private func wireMonitorToStore() {
        Task { [weak self] in
            guard let self else { return }
            for await item in self.monitor.stream {
                do {
                    try self.store.add(item)
                    self.flashCopyHint(item.preview)
                } catch {
                    AppLogger.store.error("add failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    private func wireStoreToPill() {
        store.itemsPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] items in
                self?.pillState.itemCount = items.count
            }
            .store(in: &cancellables)
    }

    private func wireHotkey() {
        hotkey.register { [weak self] in
            self?.togglePanel()
        }
    }

    // MARK: - Pill 复制提示

    private func flashCopyHint(_ text: String) {
        pillState.copyHint = text
        copyHintTimer?.invalidate()
        copyHintTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.pillState.copyHint = nil
            }
        }
    }

    // MARK: - 面板切换

    private func togglePanel() {
        if let win = panelWindow, win.isVisible {
            win.orderOut(nil)
            return
        }
        showPanel()
    }

    private func showPanel() {
        let size = NSSize(width: 360, height: 480)
        let win = panelWindow ?? PanelWindow(contentSize: size, viewModel: panelVM)
        panelWindow = win
        // 位置：刘海正下方，水平居中刘海
        if let screen = NSScreen.main {
            let notch = ScreenGeometry.notchFrame(
                screenFrame: screen.frame,
                auxiliaryTopLeftArea: screen.auxiliaryTopLeftArea,
                auxiliaryTopRightArea: screen.auxiliaryTopRightArea
            )
            let centerX: CGFloat = notch?.midX ?? (screen.frame.midX)
            let topY: CGFloat = (notch?.minY ?? screen.frame.maxY) - 4
            let frame = NSRect(
                x: centerX - size.width / 2,
                y: topY - size.height,
                width: size.width,
                height: size.height
            )
            win.setFrame(frame, display: true)
        }
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        panelVM.refresh()
    }
}

/// 把 @Published 状态桥接给 SwiftUI。
private struct PillContainer: View {
    @Binding var state: AppDelegate.PillState   // 注：编译时 PillState 需要从 AppDelegate 公开
    let onTap: () -> Void
    var body: some View {
        PillView(itemCount: state.itemCount, copyHint: state.copyHint, onTap: onTap)
    }
}
```

- [ ] **Step 2: 把 `PillState` 改成 `internal` 可见**

修改上一步代码中的 `private struct PillState` → `struct PillState`，确保 PillContainer 能引用。同时把 AppDelegate 中：

```swift
private var pillState = PillState(itemCount: 0, copyHint: nil)
```

改为：

```swift
@Published var pillState = PillState(itemCount: 0, copyHint: nil)
```

并把 `private struct PillState: Equatable` 改成 `struct PillState: Equatable`。

但 SwiftUI `@Binding` 不能直接绑到 `@Published` 字段。改用一个内部 ObservableObject 持有 pillState。最终把 NotchPasteApp.swift 调整为：

```swift
import SwiftUI
import AppKit
import Combine

@MainActor
final class PillModel: ObservableObject {
    struct State: Equatable {
        var itemCount: Int = 0
        var copyHint: String? = nil
    }
    @Published var state = State()
}

@main
struct NotchPasteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var monitor: ClipboardMonitor!
    private var store: ClipboardStore!
    private var paster: PasteService!
    private var hotkey: HotkeyService!
    private var prefs: PreferencesStore!

    private var pillWindow: PillWindow!
    private var panelWindow: PanelWindow?
    private var panelVM: PanelViewModel!
    private let pillModel = PillModel()

    private var cancellables = Set<AnyCancellable>()
    private var copyHintTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        prefs = .shared
        do {
            store = try ClipboardStore(maxItems: prefs.maxItems)
        } catch {
            AppLogger.app.error("Failed to open ClipboardStore: \(error.localizedDescription, privacy: .public)")
            NSApp.terminate(nil)
            return
        }
        paster = PasteService(preferences: prefs)
        monitor = ClipboardMonitor()
        hotkey = HotkeyService()

        panelVM = PanelViewModel(store: store, paster: paster) { [weak self] in
            self?.panelWindow?.orderOut(nil)
        }

        setupPillWindow()
        wireMonitorToStore()
        wireStoreToPill()
        wireHotkey()

        monitor.start()
        AppLogger.app.info("NotchPaste launched")
    }

    // MARK: - Setup

    private func setupPillWindow() {
        let pillSize = NSSize(width: 60, height: 24)
        pillWindow = PillWindow(contentSize: pillSize)
        pillWindow.setContent(PillContainer(model: pillModel) { [weak self] in
            self?.togglePanel()
        })

        if let frame = ScreenGeometry.currentRightPillFrame(pillSize: pillSize) {
            pillWindow.setFrame(frame, display: true)
        } else if let screen = NSScreen.main {
            let f = NSRect(x: screen.frame.maxX - pillSize.width - 8,
                           y: screen.frame.maxY - pillSize.height - 4,
                           width: pillSize.width, height: pillSize.height)
            pillWindow.setFrame(f, display: true)
        }
        pillWindow.orderFrontRegardless()
    }

    private func wireMonitorToStore() {
        Task { [weak self] in
            guard let self else { return }
            for await item in self.monitor.stream {
                do {
                    try self.store.add(item)
                    await MainActor.run { self.flashCopyHint(item.preview) }
                } catch {
                    AppLogger.store.error("add failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    private func wireStoreToPill() {
        store.itemsPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] items in
                self?.pillModel.state.itemCount = items.count
            }
            .store(in: &cancellables)
    }

    private func wireHotkey() {
        hotkey.register { [weak self] in
            self?.togglePanel()
        }
    }

    private func flashCopyHint(_ text: String) {
        pillModel.state.copyHint = text
        copyHintTimer?.invalidate()
        copyHintTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.pillModel.state.copyHint = nil
            }
        }
    }

    private func togglePanel() {
        if let win = panelWindow, win.isVisible {
            win.orderOut(nil)
            return
        }
        showPanel()
    }

    private func showPanel() {
        let size = NSSize(width: 360, height: 480)
        let win = panelWindow ?? PanelWindow(contentSize: size, viewModel: panelVM)
        panelWindow = win
        if let screen = NSScreen.main {
            let notch = ScreenGeometry.notchFrame(
                screenFrame: screen.frame,
                auxiliaryTopLeftArea: screen.auxiliaryTopLeftArea,
                auxiliaryTopRightArea: screen.auxiliaryTopRightArea
            )
            let centerX: CGFloat = notch?.midX ?? screen.frame.midX
            let topY: CGFloat = (notch?.minY ?? screen.frame.maxY) - 4
            let frame = NSRect(
                x: centerX - size.width / 2,
                y: topY - size.height,
                width: size.width,
                height: size.height
            )
            win.setFrame(frame, display: true)
        }
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        panelVM.refresh()
    }
}

private struct PillContainer: View {
    @ObservedObject var model: PillModel
    let onTap: () -> Void
    var body: some View {
        PillView(itemCount: model.state.itemCount, copyHint: model.state.copyHint, onTap: onTap)
    }
}
```

- [ ] **Step 3: 编译验证**

```bash
xcodebuild -project NotchPaste.xcodeproj -scheme NotchPaste build
```
Expected: BUILD SUCCEEDED。

- [ ] **Step 4: 提交**

```bash
git add NotchPaste/App/NotchPasteApp.swift
git commit -m "feat(app): wire AppDelegate to assemble core services and windows"
```

---

## Task 16: 端到端手动验证

**Files:** 无

- [ ] **Step 1: 在 Xcode 中 Run 应用**

Xcode → ▶︎（Run）。
Expected:
- 不出现 Dock 图标（因为 LSUIElement=YES）
- 屏幕顶部刘海右侧出现一个黑色 pill，显示蓝点 + 数字（初次启动 = 0）

- [ ] **Step 2: 复制文本 → 验证 pill 闪现预览**

任意 app 选中文本 → ⌘C。
Expected:
- pill 在 ~600ms 内显示该文本前 30~100 字符的预览
- 600ms 后回到数字状态，数字 +1

- [ ] **Step 3: 点击 pill → 验证面板弹出**

鼠标点 pill。
Expected:
- 从刘海下方弹出面板（360×480pt），毛玻璃背景
- 列表顶部就是刚才复制的文本
- 顶部搜索框

- [ ] **Step 4: 键盘导航 → 验证 ↑↓ Enter Esc**

复制几条不同文本，再按 ⇧⌘V 打开面板。
- 按 ↓ → 选中行下移
- 按 ↑ → 选中行上移
- 按 Esc → 面板关闭
- 再开 → 在某 app（如 Notes）输入框聚焦后，按 ⇧⌘V 选项 → 按 Enter

第一次按 Enter 时系统会提示授予"辅助功能"权限：
- 系统设置 → 隐私与安全 → 辅助功能 → 把 NotchPaste 加上并打开

授权后再试一次：
Expected:
- Enter 后面板关闭，~50ms 后焦点 app 中粘贴上选中的内容

- [ ] **Step 5: 搜索 → 验证过滤**

复制 "hello", "world", "hello world"，打开面板，在搜索框输入 "hello"。
Expected: 仅显示包含 "hello" 的两条。

- [ ] **Step 6: 提交手动测试结果（无代码改动则跳过）**

如有需要修复的 bug，按 TDD 修完再提交：

```bash
git add -A
git commit -m "fix(app): <bug description>"
```

如全部通过：

```bash
git tag v0.1.0-mvp
```

---

## Self-Review

### 1. Spec 覆盖检查

- ✅ 文本剪贴板捕获 + 持久化 → Task 5 (ClipboardStore) + Task 6 (ClipboardMonitor)
- ✅ pill 显示在右侧（不避让） → Task 10/11 + Task 15 (使用 ScreenGeometry.currentRightPillFrame)
- ✅ 展开面板（仅文本列表 + 搜索） → Task 13 (PanelView) + Task 14 (PanelWindow)
- ✅ 全局快捷键 → Task 8 (HotkeyService) + Task 15 (AppDelegate.wireHotkey)
- ✅ 自动粘贴 → Task 7 (PasteService) + Task 13 (PanelViewModel.commitSelection)
- ✅ 偏好基础（无 GUI） → Task 4 (PreferencesStore)
- ✅ NSPanel 跨 Space / borderless → Task 11 + Task 14
- ✅ 单元测试覆盖核心逻辑 → ClipboardItem / ClipboardStore / ClipboardMonitor / ScreenGeometry
- ✅ 端到端手动验证 → Task 16

**v0.1 范围明确不覆盖（spec 也未要求 v0.1 包含）**：
- 图片/文件类型 → v0.2
- ConcealedType 跳过 → v0.2
- 类型过滤、收藏置顶 → v0.2
- Settings UI → v0.2
- 避让其他刘海 app → v0.3
- 公证签名 + Release CI → v1.0

### 2. Placeholder 扫描

无 "TBD" / "TODO" / "implement later"。所有代码块都给出了完整可编译/可运行的实现。

### 3. Type / API 一致性

- `ClipboardItem.text(_:sourceAppBundleID:)` 在 Task 2 定义，Task 6 使用 ✅
- `ClipboardStore.add/delete/togglePin/allItems/query/itemsPublisher` 在 Task 5 定义，Task 13/15 使用 ✅
- `ScreenGeometry.notchFrame/pillFrame/currentRightPillFrame` 在 Task 9 定义，Task 15 使用 ✅
- `PasteService.paste(_:)` 在 Task 7 定义，Task 13 使用 ✅
- `HotkeyService.register(handler:)` 在 Task 8 定义，Task 15 使用 ✅
- `PreferencesStore.shared / .maxItems / .autoPasteEnabled` 在 Task 4 定义，Task 7/15 使用 ✅
- `PillView(itemCount:copyHint:onTap:)` 在 Task 10 定义，Task 15 PillContainer 使用 ✅
- `PanelView(viewModel:)` + `PanelViewModel(store:paster:onCommit:)` 在 Task 13 定义，Task 14 + 15 使用 ✅

无签名漂移。

---

**Plan 结束。** 共 16 个任务，覆盖 v0.1 MVP 全部功能。
