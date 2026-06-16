import Foundation
import AppKit
import CryptoKit
import os

protocol ClipboardChangeIgnoring: AnyObject {
    func ignoreNextChange(matching item: ClipboardItem)
}

/// 周期性轮询系统剪贴板（NSPasteboard.general），检测新内容并通过 AsyncStream 发布。
///
/// 设计说明：
/// - macOS 没有 pasteboard change notification，必须轮询 changeCount。
/// - `ignoreNextChange()` 用于自动粘贴场景：调用方先把内容写回剪贴板，紧接着
///   PasteService 模拟 ⌘V，会触发 changeCount 增加；如果不忽略，刚写入的内容会
///   被当成"新复制"再记一遍，造成历史重复 / 死循环。
/// - 隐私模式：`isMonitoringEnabled = false` 时跳过捕获，但 changeCount 仍然推进，
///   避免恢复时把暂停期间累积的内容一次性灌进来。
final class ClipboardMonitor: ClipboardChangeIgnoring {

    private let pasteboard: NSPasteboard
    private let interval: TimeInterval
    private var timer: Timer?
    private var lastChangeCount: Int

    /// 待忽略的内容签名：只跳过我们自己刚写入剪贴板的那份内容。
    private var ignoredContentSignatures = Set<String>()

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
            _ = self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        AppLogger.clipboard.info("ClipboardMonitor started, interval=\(self.interval, privacy: .public)s")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        ignoredContentSignatures.removeAll()
        continuation?.finish()
    }

    /// 标记一份由本 app 写入的内容。下一次轮询时，只有剪贴板当前内容仍然匹配它才会跳过；
    /// 如果用户已经复制了别的内容，就正常捕获，避免吞掉右键复制/按钮复制。
    func ignoreNextChange(matching item: ClipboardItem) {
        ignoredContentSignatures.insert(Self.contentSignature(for: item.type))
    }

    @discardableResult
    func tick() -> ClipboardItem? {
        let current = pasteboard.changeCount
        guard current != lastChangeCount else { return nil }
        lastChangeCount = current

        // 隐私模式：跟踪 changeCount 但不发出 item
        guard isMonitoringEnabled else { return nil }

        let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard let item = Self.extractItem(from: pasteboard, sourceAppBundleID: bundleID) else { return nil }
        if ignoredContentSignatures.remove(Self.contentSignature(for: item.type)) != nil {
            AppLogger.clipboard.debug("ignored self-written clipboard item at changeCount=\(current, privacy: .public)")
            return nil
        }

        AppLogger.clipboard.debug("New clipboard item captured: \(item.preview, privacy: .private)")
        continuation?.yield(item)
        return item
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
        // 2. 图片原始数据：不少右键复制只写 public.png/public.jpeg/public.tiff 等类型。
        if let item = imageItemFromRawData(pasteboard, sourceAppBundleID: sourceAppBundleID) {
            return item
        }
        // 3. 图片对象：app 内 copy image / 截图（NSImage 能读出 → 转 PNG 存）
        if let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let nsImage = images.first,
           let png = pngData(from: nsImage) {
            return ClipboardItem.image(png, sourceAppBundleID: sourceAppBundleID)
        }
        // 4. 文本（先试链接识别，再 fallback 到普通文本）
        if let s = pasteboard.string(forType: .string), !s.isEmpty {
            return textItem(from: s, sourceAppBundleID: sourceAppBundleID)
        }
        if let s = richTextString(from: pasteboard) {
            return textItem(from: s, sourceAppBundleID: sourceAppBundleID)
        }
        return nil
    }

    private static func imageItemFromRawData(
        _ pasteboard: NSPasteboard,
        sourceAppBundleID: String?
    ) -> ClipboardItem? {
        let imageTypes: [NSPasteboard.PasteboardType] = [
            .png,
            .tiff,
            NSPasteboard.PasteboardType("public.jpeg"),
            NSPasteboard.PasteboardType("public.jpg"),
            NSPasteboard.PasteboardType("public.heic"),
            NSPasteboard.PasteboardType("public.heif"),
            NSPasteboard.PasteboardType("org.webmproject.webp"),
            NSPasteboard.PasteboardType("public.webp")
        ]

        for type in imageTypes {
            guard let data = pasteboard.data(forType: type) else { continue }
            if type == .png, NSImage(data: data) != nil {
                return ClipboardItem.image(data, sourceAppBundleID: sourceAppBundleID)
            }
            if let image = NSImage(data: data), let png = pngData(from: image) {
                return ClipboardItem.image(png, sourceAppBundleID: sourceAppBundleID)
            }
        }
        return nil
    }

    private static func richTextString(from pasteboard: NSPasteboard) -> String? {
        if let html = pasteboard.string(forType: .html),
           let text = attributedString(from: Data(html.utf8), documentType: .html)?.string {
            return normalizedRichText(text)
        }
        if let htmlData = pasteboard.data(forType: .html),
           let text = attributedString(from: htmlData, documentType: .html)?.string {
            return normalizedRichText(text)
        }
        if let rtfData = pasteboard.data(forType: .rtf),
           let text = attributedString(from: rtfData, documentType: .rtf)?.string {
            return normalizedRichText(text)
        }
        return nil
    }

    private static func attributedString(
        from data: Data,
        documentType: NSAttributedString.DocumentType
    ) -> NSAttributedString? {
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: documentType,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        return try? NSAttributedString(data: data, options: options, documentAttributes: nil)
    }

    private static func normalizedRichText(_ text: String) -> String? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private static func textItem(from text: String, sourceAppBundleID: String?) -> ClipboardItem {
        if let link = ClipboardItem.parseURL(from: text) {
            return ClipboardItem.url(raw: text, url: link, sourceAppBundleID: sourceAppBundleID)
        }
        return ClipboardItem.text(text, sourceAppBundleID: sourceAppBundleID)
    }

    /// 把 NSImage 转成 PNG Data。失败返回 nil。
    private static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else {
            return nil
        }
        return rep.representation(using: .png, properties: [:])
    }

    private static func contentSignature(for type: ItemType) -> String {
        let raw: Data
        switch type {
        case .text(let s):
            raw = Data(("text:" + s).utf8)
        case .url(_, let url):
            raw = Data(("url:" + url.absoluteString).utf8)
        case .file(let urls):
            raw = Data(("file:" + urls.map(\.path).joined(separator: "|")).utf8)
        case .image(let data):
            var prefixed = Data("image:".utf8)
            prefixed.append(data)
            raw = prefixed
        }
        let digest = SHA256.hash(data: raw)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
