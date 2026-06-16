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
