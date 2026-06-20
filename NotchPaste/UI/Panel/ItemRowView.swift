import SwiftUI
import AppKit
import QuickLookThumbnailing

/// 列表单行：图标 + 预览 + 相对时间。
/// 文件 / 图片：右侧带 chevron，点击展开。
/// 多文件：展开后以网格排列每个文件的 QuickLook 缩略图。
struct ItemRowView: View {

    let item: ClipboardItem
    let isSelected: Bool
    let onActivate: () -> Void
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
            rowContent
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

    @ViewBuilder
    private var rowContent: some View {
        let content = HStack(spacing: 10) {
            leadingIconView
            previewText
            Text(relativeTime(for: item.createdAt))
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.4))
        }
        .contentShape(Rectangle())

        switch item.type {
        case .file(let urls):
            content
                .overlay {
                    FileDragSourceView(urls: urls, onClick: onActivate)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
        case .image(let data):
            content
                .overlay {
                    ImageDragSourceView(data: data, onClick: onActivate)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
        case .text, .url:
            content
                .onTapGesture(perform: onActivate)
        }
    }

    @ViewBuilder
    private var previewText: some View {
        Text(item.preview)
            .font(.system(size: 12))
            .foregroundStyle(.white)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
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
        .overlay {
            FileDragSourceView(urls: [url])
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .overlay {
            ImageDragSourceView(data: data)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Icon

    @ViewBuilder
    private var leadingIconView: some View {
        switch item.type {
        case .file:
            iconView
                .frame(width: 18, height: 18, alignment: .center)
                .frame(width: 28, height: 24)
        case .text, .url, .image:
            iconView
                .frame(width: 18, height: 18, alignment: .center)
        }
    }

    @ViewBuilder
    private var iconView: some View {
        switch item.type {
        case .text:
            Image(systemName: "doc.plaintext")
                .foregroundStyle(.cyan)
        case .url:
            Image(systemName: "link")
                .foregroundStyle(.cyan)
        case .file:
            Image(systemName: "doc")
                .foregroundStyle(.cyan)
        case .image:
            Image(systemName: "photo")
                .foregroundStyle(.cyan)
        }
    }

    // MARK: - Helpers

    private func relativeTime(for date: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds < 60 { return "刚刚" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)分钟前" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)小时前" }
        let days = hours / 24
        return "\(days)天前"
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

enum FileDragPasteboardFactory {
    static func makePasteboardItems(for urls: [URL]) -> [NSPasteboardItem] {
        urls.map { makePasteboardItem(for: $0) }
    }

    static func makePasteboardItem(for url: URL) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        item.setString(url.absoluteString, forType: .fileURL)
        item.setString(url.absoluteString, forType: .URL)
        item.setString(url.path, forType: .string)
        return item
    }

    static func makeDraggingItem(for url: URL, frame: NSRect) -> NSDraggingItem {
        let item = NSDraggingItem(pasteboardWriter: makePasteboardItem(for: url))
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        item.setDraggingFrame(frame, contents: icon)
        return item
    }
}

enum ImageDragPasteboardFactory {
    static func makePasteboardItem(for data: Data, fileURL: URL? = nil) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        item.setData(data, forType: .png)

        if let image = NSImage(data: data), let tiff = image.tiffRepresentation {
            item.setData(tiff, forType: .tiff)
        }

        if let fileURL {
            try? FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? data.write(to: fileURL, options: .atomic)
            item.setString(fileURL.absoluteString, forType: .fileURL)
            item.setString(fileURL.path, forType: .string)
        }

        return item
    }

    static func makeDraggingItem(for data: Data, frame: NSRect) -> NSDraggingItem {
        let item = NSDraggingItem(
            pasteboardWriter: makePasteboardItem(for: data, fileURL: makeTemporaryPNGURL())
        )
        item.setDraggingFrame(frame, contents: dragPreviewImage(for: data))
        return item
    }

    private static func makeTemporaryPNGURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("NotchPasteDragImages", isDirectory: true)
            .appendingPathComponent("notchpaste-image-\(UUID().uuidString).png")
    }

    private static func dragPreviewImage(for data: Data) -> NSImage {
        if let image = NSImage(data: data) {
            return image
        }
        return NSImage(systemSymbolName: "photo", accessibilityDescription: nil) ?? NSImage(size: NSSize(width: 32, height: 32))
    }
}

enum FileDragGesturePolicy {
    static let movementThreshold: CGFloat = 4

    static func shouldStartDrag(from start: CGPoint, to current: CGPoint) -> Bool {
        hypot(current.x - start.x, current.y - start.y) >= movementThreshold
    }
}

private struct FileDragSourceView: NSViewRepresentable {
    let urls: [URL]
    var onClick: (() -> Void)? = nil

    func makeNSView(context: Context) -> FileDragSourceNSView {
        FileDragSourceNSView(urls: urls, onClick: onClick)
    }

    func updateNSView(_ nsView: FileDragSourceNSView, context: Context) {
        nsView.urls = urls
        nsView.onClick = onClick
    }
}

private final class FileDragSourceNSView: NSView, NSDraggingSource {
    var urls: [URL]
    var onClick: (() -> Void)?
    private var mouseDownEvent: NSEvent?
    private var hasStartedDrag = false

    init(urls: [URL], onClick: (() -> Void)?) {
        self.urls = urls
        self.onClick = onClick
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
        hasStartedDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !hasStartedDrag, !urls.isEmpty else { return }
        if let mouseDownEvent {
            let start = mouseDownEvent.locationInWindow
            let current = event.locationInWindow
            guard FileDragGesturePolicy.shouldStartDrag(from: start, to: current) else { return }
        }
        hasStartedDrag = true

        let iconSize = NSSize(width: 32, height: 32)
        let dragFrame = NSRect(
            x: bounds.midX - iconSize.width / 2,
            y: bounds.midY - iconSize.height / 2,
            width: iconSize.width,
            height: iconSize.height
        )
        let items = urls.map { FileDragPasteboardFactory.makeDraggingItem(for: $0, frame: dragFrame) }
        beginDraggingSession(with: items, event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            mouseDownEvent = nil
            hasStartedDrag = false
        }
        guard !hasStartedDrag else { return }
        onClick?()
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
        true
    }
}

private struct ImageDragSourceView: NSViewRepresentable {
    let data: Data
    var onClick: (() -> Void)? = nil

    func makeNSView(context: Context) -> ImageDragSourceNSView {
        ImageDragSourceNSView(data: data, onClick: onClick)
    }

    func updateNSView(_ nsView: ImageDragSourceNSView, context: Context) {
        nsView.data = data
        nsView.onClick = onClick
    }
}

private final class ImageDragSourceNSView: NSView, NSDraggingSource {
    var data: Data
    var onClick: (() -> Void)?
    private var mouseDownEvent: NSEvent?
    private var hasStartedDrag = false

    init(data: Data, onClick: (() -> Void)?) {
        self.data = data
        self.onClick = onClick
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
        hasStartedDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !hasStartedDrag, !data.isEmpty else { return }
        if let mouseDownEvent {
            let start = mouseDownEvent.locationInWindow
            let current = event.locationInWindow
            guard FileDragGesturePolicy.shouldStartDrag(from: start, to: current) else { return }
        }
        hasStartedDrag = true

        let previewSize = previewDragSize(for: data)
        let dragFrame = NSRect(
            x: bounds.midX - previewSize.width / 2,
            y: bounds.midY - previewSize.height / 2,
            width: previewSize.width,
            height: previewSize.height
        )
        let item = ImageDragPasteboardFactory.makeDraggingItem(for: data, frame: dragFrame)
        beginDraggingSession(with: [item], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            mouseDownEvent = nil
            hasStartedDrag = false
        }
        guard !hasStartedDrag else { return }
        onClick?()
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
        true
    }

    private func previewDragSize(for data: Data) -> NSSize {
        guard let image = NSImage(data: data), image.size.width > 0, image.size.height > 0 else {
            return NSSize(width: 42, height: 42)
        }
        let maxSide: CGFloat = 92
        let scale = min(maxSide / image.size.width, maxSide / image.size.height, 1)
        return NSSize(width: max(28, image.size.width * scale), height: max(28, image.size.height * scale))
    }
}
