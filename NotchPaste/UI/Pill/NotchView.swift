import SwiftUI
import Combine

struct NotchOpenedChromePolicy {
    static let contentRevealDelay: TimeInterval = NotchAnimationTiming.openResponse + 0.04
    static let controlsRevealDelay: TimeInterval = contentRevealDelay + 0.10
    static let contentFadeDuration: TimeInterval = 0.12
    static let clipboardListContentRevealDelay: TimeInterval = 0
    static let controlsFadeDuration: TimeInterval = 0.12
    static let openedBottomInset: CGFloat = 12

    static func contentSlotHeight(notchHeight: CGFloat, headerHeight: CGFloat, bottomInset: CGFloat) -> CGFloat {
        max(0, notchHeight - headerHeight - bottomInset)
    }

    static func contentRevealDelay(for contentType: NotchViewModel.ContentType) -> TimeInterval {
        contentType == .list ? clipboardListContentRevealDelay : contentRevealDelay
    }
}

struct NotchClosedExpansionAnimationPolicy {
    static let response = 0.32
    static let dampingFraction = 0.78

    static var animation: Animation {
        .spring(response: response, dampingFraction: dampingFraction)
    }
}

struct NotchAgentActivityTransitionPolicy {
    static func shouldAnimateClosedExpansion(
        from oldActivity: VibeNotchActivity,
        to newActivity: VibeNotchActivity,
        status: NotchViewModel.NotchStatus
    ) -> Bool {
        status == .closed
            && oldActivity != newActivity
            && newActivity != .needsInteraction
    }
}

/// vibe-notch 风格刘海视图。复刻 farouqaldori/vibe-notch (Apache 2.0) 的视觉/动效结构，
/// 内容替换为 NotchPaste 的剪贴板列表。
///
/// 视觉精髓：
/// - `clipShape(NotchShape)`：黑色 ZStack 被 NotchShape 裁剪 —— 内容正常布局，
///   形状由 clip 决定，过渡时形状自然变形。
/// - 顶部 1px black overlay：补偿 clip 在顶端因抗锯齿留下的细缝。
/// - openAnim 与 closeAnim 用不同 spring 配置（vibe-notch 原配置）。
struct NotchView: View {
    private static let agentIconCache = NSCache<NSString, NSImage>()

    @ObservedObject var viewModel: NotchViewModel
    @ObservedObject var panelVM: PanelViewModel
    let onRequestPermission: () -> Void
    let onQuit: () -> Void
    @StateObject private var filePreview = FilePreviewProvider()
    @ObservedObject private var prefs = PreferencesStore.shared
    @State private var showOpenedContent = false
    @State private var showOpenedChrome = false
    @State private var openedRevealGeneration = 0
    @State private var agentActivity: VibeNotchActivity = .idle
    @State private var agentActivitySubscription: AnyCancellable?

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

    private var isAgentActivityExpanded: Bool {
        viewModel.status == .closed
            && viewModel.copyHint == nil
            && agentActivity != .idle
    }

    private var needsAgentInteraction: Bool {
        agentActivity == .needsInteraction
    }

    private var openedContentSlotHeight: CGFloat {
        NotchOpenedChromePolicy.contentSlotHeight(
            notchHeight: notchSize.height,
            headerHeight: closedNotchSize.height,
            bottomInset: NotchOpenedChromePolicy.openedBottomInset
        )
    }

    private var agentAttentionColor: Color {
        Color(red: 1.0, green: 0.55, blue: 0.16)
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
            if isAgentActivityExpanded {
                return CGSize(
                    width: closedNotchSize.width
                        + (needsAgentInteraction ? 160 : 110)
                        + agentActivityNotchWidthAdjustment,
                    height: closedNotchSize.height + 6 + agentActivityNotchHeightAdjustment
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
        return (isCopyHintExpanded || isAgentActivityExpanded) ? CornerRadii.closedExpanded.top : CornerRadii.closed.top
    }

    private var bottomCornerRadius: CGFloat {
        if viewModel.status == .opened { return CornerRadii.opened.bottom }
        return (isCopyHintExpanded || isAgentActivityExpanded) ? CornerRadii.closedExpanded.bottom : CornerRadii.closed.bottom
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
        .onAppear {
            updateAgentActivitySubscription()
            updateOpenedContentVisibility(for: viewModel.status)
        }
        .onChange(of: viewModel.status) { _, status in
            updateAgentActivitySubscription()
            updateOpenedContentVisibility(for: status)
        }
        .onChange(of: viewModel.contentType) { _, _ in
            updateAgentActivitySubscription()
        }
    }

    private func updateAgentActivitySubscription() {
        guard viewModel.status == .closed else {
            agentActivitySubscription?.cancel()
            agentActivitySubscription = nil
            return
        }

        guard agentActivitySubscription == nil else { return }

        let store = VibeAgentStore.shared
        applyAgentActivity(store.dashboard.notchActivity, animated: false)
        agentActivitySubscription = store.$dashboard
            .map(\.notchActivity)
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { activity in
                applyAgentActivity(activity, animated: true)
            }
    }

    private func applyAgentActivity(_ activity: VibeNotchActivity, animated: Bool) {
        guard activity != agentActivity else {
            if viewModel.status == .closed {
                viewModel.presentAgentAttention(activity)
            }
            return
        }

        let updateActivity = {
            agentActivity = activity
        }

        if animated && NotchAgentActivityTransitionPolicy.shouldAnimateClosedExpansion(
            from: agentActivity,
            to: activity,
            status: viewModel.status
        ) {
            withAnimation(NotchClosedExpansionAnimationPolicy.animation) {
                updateActivity()
            }
        } else {
            updateActivity()
        }

        if viewModel.status == .closed {
            viewModel.presentAgentAttention(activity)
        }
    }

    private func updateOpenedContentVisibility(for status: NotchViewModel.NotchStatus) {
        openedRevealGeneration += 1
        let generation = openedRevealGeneration

        guard status == .opened else {
            showOpenedContent = false
            showOpenedChrome = false
            return
        }

        showOpenedContent = false
        showOpenedChrome = false

        DispatchQueue.main.asyncAfter(deadline: .now() + NotchOpenedChromePolicy.contentRevealDelay(for: viewModel.contentType)) {
            guard viewModel.status == .opened, generation == openedRevealGeneration else { return }
            withAnimation(.easeOut(duration: NotchOpenedChromePolicy.contentFadeDuration)) {
                showOpenedContent = true
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + NotchOpenedChromePolicy.controlsRevealDelay) {
            guard viewModel.status == .opened, generation == openedRevealGeneration else { return }
            withAnimation(.easeOut(duration: NotchOpenedChromePolicy.controlsFadeDuration)) {
                showOpenedChrome = true
            }
        }
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
            .padding([.horizontal, .bottom], viewModel.status == .opened ? NotchOpenedChromePolicy.openedBottomInset : 0)
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
                NotchClosedExpansionAnimationPolicy.animation,
                value: isCopyHintExpanded
            )
            .animation(
                NotchClosedExpansionAnimationPolicy.animation,
                value: isAgentActivityExpanded
            )
            .animation(
                NotchClosedExpansionAnimationPolicy.animation,
                value: needsAgentInteraction
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
                if showOpenedContent {
                    contentView
                        .frame(width: notchSize.width - 24, height: openedContentSlotHeight, alignment: .top)
                        .clipped()
                        .transition(.opacity)
                } else {
                    Color.clear
                        .frame(width: notchSize.width - 24, height: openedContentSlotHeight)
                }
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
                if isAgentActivityExpanded {
                    agentActivityHint
                } else {
                    Color.clear
                }
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

    private var agentActivityHint: some View {
        Group {
            switch prefs.agentActivityIconPosition {
            case .leading:
                HStack(spacing: 0) {
                    agentActivityIcon
                    Spacer(minLength: 0)
                }
                .padding(.leading, agentActivityLeadingPadding)
                .padding(.trailing, 12)
            case .center:
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    agentActivityIcon
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
            case .trailing:
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    agentActivityIcon
                }
                .padding(.leading, 12)
                .padding(.trailing, agentActivityLeadingPadding)
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.94)))
    }

    private var agentActivityLeadingPadding: CGFloat {
        let leftExpansionWidth = max(0, (notchSize.width - closedNotchSize.width) / 2)
        return max(12, leftExpansionWidth - 34)
    }

    private var currentAgentActivityIconStyle: AgentActivityIconStyle {
        needsAgentInteraction ? prefs.agentAttentionIconStyle : prefs.agentRunningIconStyle
    }

    private var currentAgentActivityIconColor: Color {
        needsAgentInteraction ? agentAttentionColor : .cyan
    }

    private var currentAgentCustomIconPath: String? {
        needsAgentInteraction ? prefs.agentAttentionCustomIconPath : prefs.agentRunningCustomIconPath
    }

    private var agentActivityNotchWidthAdjustment: CGFloat {
        CGFloat(prefs.agentRunningNotchWidthAdjustment)
    }

    private var agentActivityNotchHeightAdjustment: CGFloat {
        CGFloat(needsAgentInteraction ? prefs.agentAttentionNotchHeightAdjustment : prefs.agentRunningNotchHeightAdjustment)
    }

    private var agentActivityIconSize: CGFloat {
        CGFloat(max(8, min(40, prefs.agentActivityIconSize)))
    }

    private var agentActivityIconOffset: CGSize {
        CGSize(
            width: CGFloat(max(-80, min(80, prefs.agentActivityIconOffsetX))),
            height: CGFloat(max(-32, min(32, prefs.agentActivityIconOffsetY)))
        )
    }

    @ViewBuilder
    private var agentActivityIcon: some View {
        if let path = currentAgentCustomIconPath, let image = cachedAgentIcon(at: path) {
            effectAgentActivityIcon {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: agentActivityIconSize, height: agentActivityIconSize)
                    .clipShape(RoundedRectangle(cornerRadius: max(3, agentActivityIconSize * 0.22), style: .continuous))
            }
            .offset(agentActivityIconOffset)
        } else {
            effectAgentActivityIcon {
                Group {
                    switch currentAgentActivityIconStyle {
                    case .spinner:
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(agentActivityIconSize / 37.5)
                            .tint(currentAgentActivityIconColor)
                            .frame(width: agentActivityIconSize, height: agentActivityIconSize)
                    case .pulse:
                        animatedPulseActivityIcon
                    case .symbol, .cascadeSymbol:
                        AgentActivitySymbolIcon(style: currentAgentActivityIconStyle, color: currentAgentActivityIconColor)
                            .frame(width: agentActivityIconSize, height: agentActivityIconSize)
                    default:
                        systemActivityIcon(currentAgentActivityIconStyle)
                    }
                }
            }
            .offset(agentActivityIconOffset)
        }
    }

    private func cachedAgentIcon(at path: String) -> NSImage? {
        let key = path as NSString
        if let image = Self.agentIconCache.object(forKey: key) {
            return image
        }
        guard let image = NSImage(contentsOfFile: path) else { return nil }
        Self.agentIconCache.setObject(image, forKey: key)
        return image
    }

    @ViewBuilder
    private func effectAgentActivityIcon<Content: View>(
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        switch prefs.agentActivityIconEffect {
        case .none:
            content()
                .frame(width: agentActivityIconSize, height: agentActivityIconSize)
        default:
            TimelineView(.animation) { timeline in
                let phase = CGFloat(timeline.date.timeIntervalSinceReferenceDate)
                let pulse = 0.5 + 0.5 * sin(phase * 4.4)
                let bounce = abs(sin(phase * 5.8))

                ZStack {
                    if prefs.agentActivityIconEffect == .edgeBloom {
                        content()
                            .foregroundStyle(currentAgentActivityIconColor)
                            .blur(radius: 4 + pulse * 3)
                            .opacity(0.42 + pulse * 0.36)
                        content()
                            .foregroundStyle(currentAgentActivityIconColor)
                            .blur(radius: 1.2 + pulse * 1.4)
                            .opacity(0.34 + pulse * 0.28)
                    }

                    content()
                        .scaleEffect(prefs.agentActivityIconEffect == .breathe ? 0.9 + pulse * 0.18 : 1)
                        .rotationEffect(.degrees(prefs.agentActivityIconEffect == .spin ? Double(phase * 120).truncatingRemainder(dividingBy: 360) : 0))
                        .offset(y: prefs.agentActivityIconEffect == .bounce ? -bounce * 4 : 0)
                        .opacity(prefs.agentActivityIconEffect == .breathe ? 0.68 + pulse * 0.32 : 1)
                        .shadow(
                            color: currentAgentActivityIconColor.opacity(prefs.agentActivityIconEffect == .glow ? 0.28 + pulse * 0.45 : 0),
                            radius: prefs.agentActivityIconEffect == .glow ? 3 + pulse * 5 : 0,
                            x: 0,
                            y: 0
                        )
                        .overlay {
                            if prefs.agentActivityIconEffect == .glow {
                                Circle()
                                    .stroke(currentAgentActivityIconColor.opacity(0.10 + pulse * 0.24), lineWidth: 1)
                                    .frame(
                                        width: agentActivityIconSize + 4 + pulse * 5,
                                        height: agentActivityIconSize + 4 + pulse * 5
                                    )
                                    .allowsHitTesting(false)
                            }
                        }
                }
            }
            .frame(width: agentActivityIconSize, height: agentActivityIconSize)
        }
    }

    private func systemActivityIcon(_ style: AgentActivityIconStyle) -> some View {
        Image(systemName: style.systemImageName)
            .font(.system(size: max(7, agentActivityIconSize * 0.5), weight: .bold))
            .foregroundStyle(currentAgentActivityIconColor)
            .frame(width: agentActivityIconSize, height: agentActivityIconSize)
    }

    private var animatedPulseActivityIcon: some View {
        TimelineView(.animation) { timeline in
            let phase = CGFloat(timeline.date.timeIntervalSinceReferenceDate)
            let pulse = 0.5 + 0.5 * sin(phase * 5.2)
            ZStack {
                Circle()
                    .stroke(currentAgentActivityIconColor.opacity(0.16 + pulse * 0.26), lineWidth: 1)
                    .frame(
                        width: agentActivityIconSize * 0.5 + pulse * agentActivityIconSize * 0.39,
                        height: agentActivityIconSize * 0.5 + pulse * agentActivityIconSize * 0.39
                    )
                Circle()
                    .fill(currentAgentActivityIconColor)
                    .frame(width: agentActivityIconSize * 0.31, height: agentActivityIconSize * 0.31)
            }
            .frame(width: agentActivityIconSize, height: agentActivityIconSize)
        }
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

            if showOpenedChrome {
                openedHeaderControls
                    .transition(.opacity)
            } else {
                openedHeaderControlsPlaceholder
            }
        }
        .frame(height: closedNotchSize.height)
    }

    private var openedHeaderControls: some View {
        HStack(spacing: 0) {
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

            settingsToggleButton
            closeButton
        }
    }

    private var openedHeaderControlsPlaceholder: some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: CGFloat(NotchViewModel.ContentType.panelTabs.count * 28 + max(0, NotchViewModel.ContentType.panelTabs.count - 1) * 2))
                .padding(.trailing, 8)
            Color.clear.frame(width: 22, height: 22)
            Color.clear.frame(width: 22, height: 22)
        }
    }

    private var settingsToggleButton: some View {
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
    }

    private var closeButton: some View {
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

    // MARK: - Content (opened)

    @ViewBuilder
    private var contentView: some View {
        Group {
            switch viewModel.contentType {
            case .list:
                ClipboardListView(viewModel: panelVM)
            case .vibe:
                LazyVibeContentView {
                    viewModel.notchClose()
                }
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

private struct LazyVibeContentView: View {
    @ObservedObject private var vibeStore = VibeAgentStore.shared
    let onJump: () -> Void

    private var pendingAgentSession: VibeSession? {
        vibeStore.dashboard.sessions.first { $0.action == .approval }
            ?? vibeStore.dashboard.sessions.first { $0.action == .question }
            ?? vibeStore.dashboard.sessions.first { $0.needsJumpAttention }
    }

    private var latestCodeDiffSession: VibeSession? {
        vibeStore.dashboard.sessions.first { !$0.codeDiff.isEmpty }
    }

    private var notchAgentCardSession: VibeSession? {
        pendingAgentSession ?? latestCodeDiffSession
    }

    private var agentAttentionColor: Color {
        Color(red: 1.0, green: 0.55, blue: 0.16)
    }

    private var diffAddedColor: Color {
        Color(red: 0.20, green: 0.88, blue: 0.45)
    }

    private var diffRemovedColor: Color {
        Color(red: 1.0, green: 0.55, blue: 0.50)
    }

    var body: some View {
        VStack(spacing: 6) {
            if let session = notchAgentCardSession {
                agentInteractionCard(session)
                    .padding(.horizontal, 8)
            }

            VibeIslandReplicaView(onJump: onJump)
        }
    }

    private func agentInteractionCard(_ session: VibeSession) -> some View {
        let compactDiff = vibeStore.dashboard.notchCodeDiff(preferredSessionID: session.id)

        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Circle()
                    .fill(session.tint)
                    .frame(width: 5, height: 5)

                Text(agentCardTitle(for: session))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(session.action == .approval ? agentAttentionColor : session.tint)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Text(session.agent)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.42))
                    .lineLimit(1)
            }

            if !compactDiff.isEmpty {
                Text(session.detail)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(session.action == .approval ? agentAttentionColor : session.tint)
                    .lineLimit(1)

                notchCodeDiffBlock(Array(compactDiff.prefix(7)))
            } else {
                Text(session.detail.isEmpty ? session.state : session.detail)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(2)
            }

            if session.action == .approval {
                HStack(spacing: 7) {
                    Button("Deny") {
                        vibeStore.deny(sessionID: session.id)
                    }
                    .buttonStyle(NotchAgentActionButtonStyle(filled: false, tint: agentAttentionColor))

                    Button("Allow") {
                        vibeStore.allow(sessionID: session.id)
                    }
                    .buttonStyle(NotchAgentActionButtonStyle(filled: true, tint: .white))
                }
            } else if session.action == .question, !session.questionOptions.isEmpty {
                HStack(spacing: 6) {
                    ForEach(Array(session.questionOptions.prefix(3)), id: \.self) { option in
                        Button(option) {
                            let delivered = VibeTerminalReplySender.send(to: session, value: option)
                            vibeStore.answerQuestion(
                                sessionID: session.id,
                                option: option,
                                deliveredToTerminal: delivered
                            )
                        }
                        .buttonStyle(NotchAgentActionButtonStyle(filled: false, tint: session.tint))
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(session.tint.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(session.tint.opacity(session.action == .approval ? 0.45 : 0.28), lineWidth: 1)
        )
    }

    private func agentCardTitle(for session: VibeSession) -> String {
        switch session.action {
        case .approval:
            return "Permission Request"
        case .question:
            return "AskUserQuestion"
        case .jump:
            return "需要跳回"
        case .monitor:
            return "Latest Diff"
        }
    }

    private func notchCodeDiffBlock(_ lines: [VibeCodeDiffLine]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line.text)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(notchDiffForeground(for: line.style))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 1)
                    .background(notchDiffBackground(for: line.style))
            }
        }
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private func notchDiffForeground(for style: VibeCodeDiffLine.Style) -> Color {
        switch style {
        case .context:
            return .white.opacity(0.34)
        case .removed:
            return diffRemovedColor
        case .added:
            return diffAddedColor
        }
    }

    private func notchDiffBackground(for style: VibeCodeDiffLine.Style) -> Color {
        switch style {
        case .context:
            return Color.white.opacity(0.015)
        case .removed:
            return Color.red.opacity(0.18)
        case .added:
            return diffAddedColor.opacity(0.13)
        }
    }
}

struct AgentActivitySymbolIcon: View {
    let style: AgentActivityIconStyle
    let color: Color

    private static let primaryRects: [CGRect] = [
        CGRect(x: 2, y: 2, width: 2, height: 12),
        CGRect(x: 4, y: 2, width: 8, height: 2),
        CGRect(x: 12, y: 2, width: 2, height: 6),
        CGRect(x: 4, y: 8, width: 8, height: 2),
        CGRect(x: 4, y: 10, width: 2, height: 2),
        CGRect(x: 4, y: 12, width: 8, height: 2),
        CGRect(x: 12, y: 10, width: 2, height: 4)
    ]

    private static let cascadeRects: [CGRect] = [
        CGRect(x: 3, y: 2, width: 2, height: 2),
        CGRect(x: 5, y: 4, width: 2, height: 2),
        CGRect(x: 7, y: 6, width: 2, height: 2),
        CGRect(x: 9, y: 4, width: 2, height: 2),
        CGRect(x: 11, y: 2, width: 2, height: 2),
        CGRect(x: 3, y: 8, width: 10, height: 2),
        CGRect(x: 5, y: 10, width: 6, height: 2),
        CGRect(x: 7, y: 12, width: 2, height: 2)
    ]

    private var rects: [CGRect] {
        style == .cascadeSymbol ? Self.cascadeRects : Self.primaryRects
    }

    var body: some View {
        GeometryReader { proxy in
            let scale = min(proxy.size.width, proxy.size.height) / 16
            let xInset = (proxy.size.width - 16 * scale) / 2
            let yInset = (proxy.size.height - 16 * scale) / 2

            ZStack(alignment: .topLeading) {
                ForEach(Array(rects.enumerated()), id: \.offset) { _, rect in
                    Rectangle()
                        .fill(color)
                        .frame(width: rect.width * scale, height: rect.height * scale)
                        .offset(x: xInset + rect.minX * scale, y: yInset + rect.minY * scale)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

private struct NotchAgentActionButtonStyle: ButtonStyle {
    let filled: Bool
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(filled ? .black : .white.opacity(0.78))
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(filled ? tint.opacity(configuration.isPressed ? 0.76 : 0.9) : Color.white.opacity(configuration.isPressed ? 0.12 : 0.07))
            )
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
