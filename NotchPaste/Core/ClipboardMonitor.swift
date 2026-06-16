import Foundation
import AppKit
import os

/// 周期性轮询系统剪贴板（NSPasteboard.general），检测新内容并通过 AsyncStream 发布。
///
/// 设计说明：
/// - macOS 没有 pasteboard change notification，必须轮询 changeCount。
/// - `ignoreNextChange()` 用于自动粘贴场景：调用方先把内容写回剪贴板，紧接着
///   PasteService 模拟 ⌘V，会触发 changeCount 增加；如果不忽略，刚写入的内容会
///   被当成"新复制"再记一遍，造成历史重复 / 死循环。
/// - 隐私模式：`isMonitoringEnabled = false` 时跳过捕获，但 changeCount 仍然推进，
///   避免恢复时把暂停期间累积的内容一次性灌进来。
final class ClipboardMonitor {

    private let pasteboard: NSPasteboard
    private let interval: TimeInterval
    private var timer: Timer?
    private var lastChangeCount: Int

    /// 待忽略的 changeCount 集合：写入剪贴板后下一次（或几次）变化不做记录。
    private var ignoredChangeCounts = Set<Int>()

    /// 隐私模式开关。false 时不捕获新内容，但仍跟踪 changeCount。
    var isMonitoringEnabled: Bool = true

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
        ignoredChangeCounts.removeAll()
        continuation?.finish()
    }

    /// 标记接下来一次 changeCount 增长不做记录（典型场景：自动粘贴）。
    /// 多次调用会累计 —— 写入文件 + 模拟 ⌘V 可能产生 2 次 change，调用方按需调用多次。
    func ignoreNextChange() {
        // 当前 changeCount 之后的下一次（任意大小）变化都跳过。
        // 用 +1 + +2 双保险（NSPasteboard 在写多个 representation 时可能 ++2 次）。
        let current = pasteboard.changeCount
        ignoredChangeCounts.insert(current + 1)
        ignoredChangeCounts.insert(current + 2)
    }

    private func tick() {
        let current = pasteboard.changeCount
        guard current != lastChangeCount else { return }
        lastChangeCount = current

        // 隐私模式：跟踪 changeCount 但不发出 item
        guard isMonitoringEnabled else { return }

        // 自动粘贴回流过滤
        if ignoredChangeCounts.remove(current) != nil {
            AppLogger.clipboard.debug("ignored auto-paste echo at changeCount=\(current, privacy: .public)")
            return
        }

        let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard let item = Self.extractItem(from: pasteboard, sourceAppBundleID: bundleID) else { return }
        AppLogger.clipboard.debug("New clipboard item captured: \(item.preview, privacy: .private)")
        continuation?.yield(item)
    }

    /// 从给定 pasteboard 提取一个 ClipboardItem。
    /// 优先级：file URL > image > url（识别为链接的纯文本）> text。
    /// 返回 nil 表示无支持类型。
    static func extractItem(from pasteboard: NSPasteboard, sourceAppBundleID: String?) -> ClipboardItem? {
        // 1. 文件 URL（Finder / 文件管理器复制）
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            return ClipboardItem.file(urls, sourceAppBundleID: sourceAppBundleID)
        }
        // 2. 图片：app 内 copy image / 截图（NSImage 能读出 → 转 PNG 存）
        if let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let nsImage = images.first,
           let png = pngData(from: nsImage) {
            return ClipboardItem.image(png, sourceAppBundleID: sourceAppBundleID)
        }
        // 3. 文本（先试链接识别，再 fallback 到普通文本）
        if let s = pasteboard.string(forType: .string), !s.isEmpty {
            if let link = ClipboardItem.parseURL(from: s) {
                return ClipboardItem.url(raw: s, url: link, sourceAppBundleID: sourceAppBundleID)
            }
            return ClipboardItem.text(s, sourceAppBundleID: sourceAppBundleID)
        }
        return nil
    }

    /// 把 NSImage 转成 PNG Data。失败返回 nil。
    private static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else {
            return nil
        }
        return rep.representation(using: .png, properties: [:])
    }
}
