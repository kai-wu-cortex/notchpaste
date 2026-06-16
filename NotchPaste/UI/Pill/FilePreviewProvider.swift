import SwiftUI
import AppKit
import QuickLookThumbnailing

/// 多文件 QuickLook 缩略图加载器。
/// 每个文件独立异步加载；初始用 system icon 占位，之后被 thumbnail 替换。
@MainActor
final class FilePreviewProvider: ObservableObject {

    /// 单个文件的预览状态。
    struct Entry: Identifiable, Equatable {
        let url: URL
        var image: NSImage
        /// 是否已替换成真实 thumbnail（vs 占位 system icon）
        var hasRealThumbnail: Bool

        var id: String { url.path }

        static func == (l: Entry, r: Entry) -> Bool {
            l.url == r.url && l.hasRealThumbnail == r.hasRealThumbnail
        }
    }

    @Published var entries: [Entry] = []

    /// 多于该数量时仅展示前 N 个 + "+ M more" 标签。
    let maxVisible = 4

    private var loadingPaths: Set<String> = []

    func load(urls: [URL], targetSize: CGSize, scale: CGFloat) {
        // 路径相同且数量相同 → 已加载，跳过
        let newPaths = urls.map(\.path)
        let oldPaths = entries.map(\.url.path)
        guard newPaths != oldPaths else { return }

        // 重置：先用 system icon 占位
        entries = urls.prefix(maxVisible).map { url in
            Entry(
                url: url,
                image: NSWorkspace.shared.icon(forFile: url.path),
                hasRealThumbnail: false
            )
        }
        loadingPaths.removeAll()

        // 异步请求每个文件的真实缩略图
        for url in urls.prefix(maxVisible) {
            requestThumbnail(for: url, size: targetSize, scale: scale)
        }
    }

    private func requestThumbnail(for url: URL, size: CGSize, scale: CGFloat) {
        let path = url.path
        guard !loadingPaths.contains(path) else { return }
        loadingPaths.insert(path)

        let req = QLThumbnailGenerator.Request(
            fileAt: url,
            size: size,
            scale: scale,
            representationTypes: .all
        )

        QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { [weak self] rep, _ in
            guard let rep else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.loadingPaths.remove(path)
                if let idx = self.entries.firstIndex(where: { $0.url.path == path }) {
                    self.entries[idx].image = rep.nsImage
                    self.entries[idx].hasRealThumbnail = true
                }
            }
        }
    }
}
