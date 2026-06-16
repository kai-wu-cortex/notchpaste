import SwiftUI
import AppKit
import QuickLookThumbnailing

/// 列表单行：图标 + 预览 + 相对时间。
/// 文件 / 图片：右侧带 chevron，点击展开。
/// 多文件：展开后以网格排列每个文件的 QuickLook 缩略图。
struct ItemRowView: View {

    let item: ClipboardItem
    let isSelected: Bool
    /// 切换星标。AppDelegate 路径里通过 PanelViewModel 委托给 ClipboardStore.togglePin。
    let onToggleStar: () -> Void

    @State private var isExpanded = false
    /// 多文件场景：path → thumbnail 图像。
    @State private var fileThumbnails: [String: NSImage] = [:]

    private let columns = [
        GridItem(.adaptive(minimum: 96, maximum: 120), spacing: 8, alignment: .top)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            mainRow
            if isExpanded {
                switch item.type {
                case .file(let urls):
                    expandedFilePreview(urls: urls)
                        .transition(expandTransition)
                case .image(let data):
                    expandedImagePreview(data: data)
                        .transition(expandTransition)
                case .text, .url:
                    EmptyView()
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.white.opacity(0.12) : .clear)
        )
        .contentShape(Rectangle())
    }

    private var expandTransition: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.95, anchor: .top)
                .combined(with: .opacity)
                .animation(.smooth(duration: 0.25)),
            removal: .opacity.animation(.easeOut(duration: 0.12))
        )
    }

    // MARK: - Main row

    private var mainRow: some View {
        HStack(spacing: 10) {
            iconView
                .frame(width: 18, height: 18, alignment: .center)
            Text(item.preview)
                .font(.system(size: 12))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(relativeTime(for: item.createdAt))
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.4))
            if hasExpandablePreview {
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        isExpanded.toggle()
                    }
                    if isExpanded, case .file(let urls) = item.type {
                        loadAllThumbnails(for: urls)
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: isExpanded)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            // 星标按钮：加星后归到"常用"分类
            Button(action: onToggleStar) {
                Image(systemName: item.pinned ? "star.fill" : "star")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(item.pinned ? Color.yellow : .white.opacity(0.4))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(item.pinned ? "取消收藏" : "加入常用")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    private var hasExpandablePreview: Bool {
        switch item.type {
        case .file, .image: return true
        case .text, .url: return false
        }
    }

    // MARK: - Expanded file preview (grid for multiple, large for single)

    @ViewBuilder
    private func expandedFilePreview(urls: [URL]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if urls.count == 1, let only = urls.first {
                singleFileTile(url: only, large: true)
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                    ForEach(urls, id: \.path) { url in
                        singleFileTile(url: url, large: false)
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
    }

    /// 单个文件的网格瓦片：缩略图 + 文件名（多文件时）。
    @ViewBuilder
    private func singleFileTile(url: URL, large: Bool) -> some View {
        let height: CGFloat = large ? 180 : 88
        VStack(alignment: .leading, spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.04))
                if let img = fileThumbnails[url.path] {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: height)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white.opacity(0.5))
                }
            }
            .frame(height: height)

            if !large {
                Text(url.lastPathComponent)
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text(url.path)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    @ViewBuilder
    private func expandedImagePreview(data: Data) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.04))
                if let img = NSImage(data: data) {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .frame(height: 200)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
    }

    // MARK: - Icon

    @ViewBuilder
    private var iconView: some View {
        switch item.type {
        case .text:
            Image(systemName: "doc.plaintext")
                .foregroundStyle(.cyan)
        case .url:
            Image(systemName: "link")
                .foregroundStyle(.cyan)
        case .file(let urls):
            if let first = urls.first {
                Image(nsImage: NSWorkspace.shared.icon(forFile: first.path))
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "doc")
                    .foregroundStyle(.cyan)
            }
        case .image(let data):
            if let img = NSImage(data: data) {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 18, height: 18)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.cyan)
            }
        }
    }

    // MARK: - Helpers

    private func relativeTime(for date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        f.locale = Locale(identifier: "zh-Hans")
        return f.localizedString(for: date, relativeTo: Date())
    }

    /// 并发加载每个文件的 QuickLook 缩略图（已加载过的跳过）。
    private func loadAllThumbnails(for urls: [URL]) {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let large = urls.count == 1
        let size: CGSize = large
            ? CGSize(width: 360, height: 220)
            : CGSize(width: 180, height: 120)

        for url in urls where fileThumbnails[url.path] == nil {
            let req = QLThumbnailGenerator.Request(
                fileAt: url,
                size: size,
                scale: scale,
                representationTypes: .all
            )
            QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { rep, _ in
                guard let rep else { return }
                Task { @MainActor in
                    self.fileThumbnails[url.path] = rep.nsImage
                }
            }
        }
    }
}
