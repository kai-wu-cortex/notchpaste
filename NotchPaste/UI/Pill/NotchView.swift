import SwiftUI
import Combine

/// vibe-notch 风格刘海视图。复刻 farouqaldori/vibe-notch (Apache 2.0) 的视觉/动效结构，
/// 内容替换为 NotchPaste 的剪贴板列表。
///
/// 视觉精髓：
/// - `clipShape(NotchShape)`：黑色 ZStack 被 NotchShape 裁剪 —— 内容正常布局，
///   形状由 clip 决定，过渡时形状自然变形。
/// - 顶部 1px black overlay：补偿 clip 在顶端因抗锯齿留下的细缝。
/// - openAnim 与 closeAnim 用不同 spring 配置（vibe-notch 原配置）。
struct NotchView: View {

    @ObservedObject var viewModel: NotchViewModel
    @ObservedObject var panelVM: PanelViewModel
    let onRequestPermission: () -> Void
    let onQuit: () -> Void
    @StateObject private var filePreview = FilePreviewProvider()

    /// closed 态尺寸：由 ScreenSelector 提供的物理刘海几何驱动。
    private var closedNotchSize: CGSize {
        CGSize(
            width: viewModel.deviceNotchRect.width,
            height: viewModel.deviceNotchRect.height
        )
    }

    /// 是否处于"复制提示"膨胀态：closed 但有 copyHint。
    private var isCopyHintExpanded: Bool {
        viewModel.status == .closed && viewModel.copyHint != nil
    }

    /// 媒体预览膨胀态：file 或 image，需要更大空间放缩略图。
    private var isMediaPreviewExpanded: Bool {
        if viewModel.status != .closed { return false }
        switch viewModel.copyHint {
        case .file, .image: return true
        default: return false
        }
    }

    /// 当前 file copyHint 中的文件数量（不到 file 类型则为 0）。
    private var fileHintCount: Int {
        if case .file(let urls) = viewModel.copyHint { return urls.count }
        return 0
    }

    /// 当前渲染尺寸。
    private var notchSize: CGSize {
        switch viewModel.status {
        case .closed:
            if isMediaPreviewExpanded {
                // 多文件每个缩略图 ~70pt + spacing；最多 maxVisible(=4) + 文字区
                let visibleFiles = min(fileHintCount, 4)
                let multiFileExtraWidth: CGFloat = visibleFiles > 1
                    ? CGFloat(visibleFiles - 1) * 76
                    : 0
                return CGSize(
                    width: closedNotchSize.width + 280 + multiFileExtraWidth,
                    height: closedNotchSize.height + 80
                )
            }
            if isCopyHintExpanded {
                return CGSize(
                    width: closedNotchSize.width + closedNotchSize.width,
                    height: closedNotchSize.height + 6
                )
            }
            return closedNotchSize
        case .opened: return viewModel.openedSize
        }
    }

    /// vibe-notch 的角半径常量。
    private struct CornerRadii {
        static let closed: (top: CGFloat, bottom: CGFloat) = (6, 14)
        static let closedExpanded: (top: CGFloat, bottom: CGFloat) = (8, 18)
        static let opened: (top: CGFloat, bottom: CGFloat) = (19, 24)
    }

    private var topCornerRadius: CGFloat {
        if viewModel.status == .opened { return CornerRadii.opened.top }
        return isCopyHintExpanded ? CornerRadii.closedExpanded.top : CornerRadii.closed.top
    }

    private var bottomCornerRadius: CGFloat {
        if viewModel.status == .opened { return CornerRadii.opened.bottom }
        return isCopyHintExpanded ? CornerRadii.closedExpanded.bottom : CornerRadii.closed.bottom
    }

    private var currentNotchShape: NotchShape {
        NotchShape(topCornerRadius: topCornerRadius, bottomCornerRadius: bottomCornerRadius)
    }

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                notchContainer
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .preferredColorScheme(.dark)
    }

    // MARK: - Notch container（vibe-notch 的核心 layout）

    @ViewBuilder
    private var notchContainer: some View {
        notchInner
            .frame(
                maxWidth: notchSize.width,
                alignment: .top
            )
            .padding(
                .horizontal,
                viewModel.status == .opened ? CornerRadii.opened.top : CornerRadii.closed.bottom
            )
            .padding([.horizontal, .bottom], viewModel.status == .opened ? 12 : 0)
            .background(.black)
            .clipShape(currentNotchShape)
            .overlay(alignment: .top) {
                // 顶端 1px black 横条修补 clip 抗锯齿留下的细缝
                Rectangle()
                    .fill(.black)
                    .frame(height: 1)
                    .padding(.horizontal, topCornerRadius)
            }
            .shadow(
                color: viewModel.status == .opened ? .black.opacity(0.7) : .clear,
                radius: 6
            )
            .frame(
                width: notchSize.width,
                height: notchSize.height,
                alignment: .top
            )
            .animation(
                viewModel.status == .opened ? NotchViewModel.openAnim : NotchViewModel.closeAnim,
                value: viewModel.status
            )
            .animation(
                .spring(response: 0.32, dampingFraction: 0.78),
                value: isCopyHintExpanded
            )
            .animation(.smooth, value: viewModel.copyHint)
            .contentShape(Rectangle())
    }

    // MARK: - Inner content（header + opened content）

    @ViewBuilder
    private var notchInner: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
                // headerRow 始终是 closed 刘海高度（或膨胀态高度）；opened 态另起 contentView
                .frame(height: viewModel.status == .opened ? closedNotchSize.height : notchSize.height)

            if viewModel.status == .opened {
                contentView
                    .frame(width: notchSize.width - 24)
                    .transition(
                        .asymmetric(
                            insertion: .scale(scale: 0.8, anchor: .top)
                                .combined(with: .opacity)
                                .animation(.smooth(duration: 0.35)),
                            removal: .opacity.animation(.easeOut(duration: 0.15))
                        )
                    )
            }
        }
    }

    // MARK: - Header row

    @ViewBuilder
    private var headerRow: some View {
        if viewModel.status == .opened {
            openedHeader
        } else {
            closedHeader
        }
    }

    /// closed 态 header：宽度严格 = 物理刘海宽（避免黑色背景铺满整窗口）。
    /// 复制时（isCopyHintExpanded）膨胀宽度，左侧显示图标、右侧显示文本预览。
    /// 文件复制时（isFilePreviewExpanded）显示 QuickLook 缩略图 + 文件名。
    @ViewBuilder
    private var closedHeader: some View {
        HStack(spacing: 0) {
            switch viewModel.copyHint {
            case .text(let s):
                textHint(s)
            case .file(let urls):
                fileHint(urls: urls)
                    .onAppear {
                        filePreview.load(
                            urls: urls,
                            targetSize: CGSize(width: 80, height: 80),
                            scale: NSScreen.main?.backingScaleFactor ?? 2
                        )
                    }
            case .image(let data):
                imageHint(data: data)
            case .none:
                Color.clear
            }
        }
        .frame(
            width: notchSize.width - 20,
            height: notchSize.height
        )
    }

    /// 文本预览：左侧 cyan 剪贴板图标，右侧文本。
    @ViewBuilder
    private func textHint(_ s: String) -> some View {
        Image(systemName: "doc.on.clipboard.fill")
            .font(.system(size: 12))
            .foregroundStyle(.cyan)
            .padding(.leading, 8)
            .transition(.opacity)

        Spacer(minLength: 8)

        Text(s)
            .font(.system(size: 11))
            .foregroundStyle(.white)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.trailing, 10)
            .transition(.opacity)
    }

    /// 文件预览：左侧多个 QuickLook 缩略图横向排列，右侧文件名 + 数量信息。
    @ViewBuilder
    private func fileHint(urls: [URL]) -> some View {
        // 多文件时缩略图小一点，单文件时大一点
        let single = urls.count == 1
        let thumbSize: CGFloat = single ? 80 : 64

        HStack(spacing: 6) {
            if filePreview.entries.isEmpty {
                // 加载中占位
                Image(systemName: "doc")
                    .font(.system(size: 36))
                    .foregroundStyle(.cyan)
                    .frame(width: thumbSize, height: thumbSize)
            } else {
                ForEach(filePreview.entries) { entry in
                    Image(nsImage: entry.image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: thumbSize, height: thumbSize)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                        )
                }
                // 文件多于 maxVisible：用 "+ N" 标签代替
                if urls.count > filePreview.maxVisible {
                    Text("+\(urls.count - filePreview.maxVisible)")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: thumbSize, height: thumbSize)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white.opacity(0.08))
                        )
                }
            }
        }
        .padding(.leading, 10)
        .padding(.vertical, 4)
        .transition(.opacity)

        Spacer(minLength: 12)

        VStack(alignment: .trailing, spacing: 3) {
            Text(single ? (urls.first?.lastPathComponent ?? "") : "\(urls.count) 个文件")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.middle)
            if let first = urls.first {
                Text(first.deletingLastPathComponent().lastPathComponent)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.trailing, 14)
        .frame(maxWidth: 220, alignment: .trailing)
        .transition(.opacity)
    }

    /// 图片预览：左侧大缩略图，右侧尺寸/字节信息。
    @ViewBuilder
    private func imageHint(data: Data) -> some View {
        Group {
            if let img = NSImage(data: data) {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                    )
                    .padding(.leading, 10)
                    .padding(.vertical, 4)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 36))
                    .foregroundStyle(.cyan)
                    .frame(width: 80, height: 80)
                    .padding(.leading, 10)
            }
        }
        .transition(.opacity)

        Spacer(minLength: 12)

        VStack(alignment: .trailing, spacing: 3) {
            Text("已复制图片")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)
            Text(byteSizeString(data.count))
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(.trailing, 14)
        .frame(maxWidth: 220, alignment: .trailing)
        .transition(.opacity)
    }

    private func byteSizeString(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return "\(bytes / 1024) KB" }
        return String(format: "%.1f MB", Double(bytes) / 1024.0 / 1024.0)
    }

    /// opened 态 header：标题 + 设置切换按钮 + 关闭按钮，宽度由父容器（openedSize）控制。
    @ViewBuilder
    private var openedHeader: some View {
        HStack(spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: viewModel.contentType.headerIconName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                Text(viewModel.contentType.headerTitle(itemCount: viewModel.itemCount))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(.leading, 6)

            Spacer(minLength: 0)

            HStack(spacing: 2) {
                ForEach(NotchViewModel.ContentType.panelTabs, id: \.self) { tab in
                    Button {
                        viewModel.contentType = tab
                    } label: {
                        Image(systemName: tab.headerIconName)
                            .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(viewModel.contentType == tab ? .black : .white.opacity(0.62))
                        .frame(width: 28, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(viewModel.contentType == tab ? Color.white.opacity(0.88) : Color.white.opacity(0.06))
                        )
                    }
                    .buttonStyle(.plain)
                    .help(tab.helpTitle)
                    .accessibilityLabel(Text(tab.helpTitle))
                }
            }
            .padding(.trailing, 8)

            // 设置切换按钮（齿轮 ↔ 列表）
            Button {
                viewModel.contentType = viewModel.contentType == .settings ? .list : .settings
            } label: {
                Image(systemName: viewModel.contentType == .settings ? "list.bullet" : "gearshape")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(viewModel.contentType == .settings ? "返回列表" : "设置")

            // 关闭按钮
            Button {
                viewModel.notchClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.4))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(height: closedNotchSize.height)
    }

    // MARK: - Content (opened)

    @ViewBuilder
    private var contentView: some View {
        Group {
            switch viewModel.contentType {
            case .list:
                ClipboardListView(viewModel: panelVM)
            case .vibe:
                VibeIslandReplicaView()
            case .settings:
                NotchSettingsView(
                    viewModel: viewModel,
                    onRequestPermission: onRequestPermission,
                    onQuit: onQuit
                )
            }
        }
        .frame(width: notchSize.width - 24)
    }
}

extension NotchViewModel.ContentType {
    var headerIconName: String {
        switch self {
        case .list: return "doc.on.clipboard"
        case .vibe: return "sparkles"
        case .settings: return "gearshape.fill"
        }
    }

    var tabTitle: String {
        switch self {
        case .list: return "剪贴板"
        case .vibe: return "Vibe"
        case .settings: return "设置"
        }
    }

    var helpTitle: String {
        switch self {
        case .list: return "剪贴板"
        case .vibe: return "Vibe"
        case .settings: return "设置"
        }
    }

    func headerTitle(itemCount: Int) -> String {
        switch self {
        case .list: return "剪贴板 · \(itemCount)"
        case .vibe: return "Vibe"
        case .settings: return "设置"
        }
    }
}
