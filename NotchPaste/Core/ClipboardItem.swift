import Foundation

/// 剪贴板内容类型。v0.1 仅 .text；image/file 在 v0.2 加入。
enum ItemType: Equatable {
    case text(String)
    // case image(Data)        — v0.2
    // case file([URL])        — v0.2
}

/// 剪贴板历史中的一项。`pinned` 和 `sourceAppBundleID` 可变以便存储层
/// 直接更新；`id` / `type` / `createdAt` 一旦创建即固定。
struct ClipboardItem: Identifiable, Equatable {
    let id: UUID
    let type: ItemType
    let createdAt: Date
    var pinned: Bool
    var sourceAppBundleID: String?  // 可变：dedup 时由 store 用最新一次复制的来源覆盖

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
