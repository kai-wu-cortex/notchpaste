import Foundation

/// 剪贴板内容类型。v0.2 支持 .text / .file / .image / .url。
/// .url 与 .text 共存：监听器把识别为 URL 的文本归到 .url，原始字符串保留供搜索。
enum ItemType: Equatable {
    case text(String)
    case file([URL])
    /// 位图剪贴板（截图、app 内 copy image 等）。data 是 PNG 编码后的字节。
    case image(Data)
    /// 链接：显式分类的网页 URL。`raw` 是原始文本（如 "https://x.com/foo"），
    /// `url` 是解析后的 URL，便于 UI 直接渲染 + 复制。
    case url(raw: String, url: URL)
}

/// 剪贴板历史中的一项。`pinned` / `sourceAppBundleID` / 使用统计字段可变；
/// `id` / `type` / `createdAt` 一旦创建即固定。
struct ClipboardItem: Identifiable, Equatable {
    let id: UUID
    let type: ItemType
    let createdAt: Date
    var pinned: Bool
    var sourceAppBundleID: String?  // 可变：dedup 时由 store 用最新一次复制的来源覆盖

    /// 使用次数：每次被用户从历史里复制到剪贴板就 +1（用于"常用"排序）。
    var usageCount: Int = 0
    /// 最近一次被使用的时间。nil 表示未被使用过。
    var lastUsedAt: Date? = nil

    /// 最多 100 字符的预览文本。
    var preview: String {
        switch type {
        case .text(let s):
            return String(s.prefix(100))
        case .file(let urls):
            if urls.count == 1 {
                return urls[0].lastPathComponent
            }
            let first = urls.first?.lastPathComponent ?? ""
            return "\(first) 等 \(urls.count) 项"
        case .image(let data):
            let bytes = data.count
            if bytes < 1024 { return "图片 · \(bytes) B" }
            if bytes < 1024 * 1024 { return "图片 · \(bytes / 1024) KB" }
            return String(format: "图片 · %.1f MB", Double(bytes) / 1024.0 / 1024.0)
        case .url(let raw, _):
            return String(raw.prefix(100))
        }
    }

    static func text(_ s: String, sourceAppBundleID: String? = nil) -> ClipboardItem {
        ClipboardItem(
            id: UUID(),
            type: .text(s),
            createdAt: Date(),
            pinned: false,
            sourceAppBundleID: sourceAppBundleID
        )
    }

    static func file(_ urls: [URL], sourceAppBundleID: String? = nil) -> ClipboardItem {
        ClipboardItem(
            id: UUID(),
            type: .file(urls),
            createdAt: Date(),
            pinned: false,
            sourceAppBundleID: sourceAppBundleID
        )
    }

    static func image(_ data: Data, sourceAppBundleID: String? = nil) -> ClipboardItem {
        ClipboardItem(
            id: UUID(),
            type: .image(data),
            createdAt: Date(),
            pinned: false,
            sourceAppBundleID: sourceAppBundleID
        )
    }

    static func url(raw: String, url: URL, sourceAppBundleID: String? = nil) -> ClipboardItem {
        ClipboardItem(
            id: UUID(),
            type: .url(raw: raw, url: url),
            createdAt: Date(),
            pinned: false,
            sourceAppBundleID: sourceAppBundleID
        )
    }
}

// MARK: - URL detection

extension ClipboardItem {
    /// 把文本字符串尝试解析为有效的 web URL。返回 nil 表示不是链接。
    /// 规则：trim 后必须以 http:// 或 https:// 开头，单行，URLComponents 可解析且 host 非空。
    static func parseURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // 单行
        guard !trimmed.contains(where: \.isNewline) else { return nil }
        // 必须有 scheme
        let lower = trimmed.lowercased()
        guard lower.hasPrefix("http://") || lower.hasPrefix("https://") else { return nil }
        guard let url = URL(string: trimmed),
              let host = url.host, !host.isEmpty else { return nil }
        return url
    }
}
