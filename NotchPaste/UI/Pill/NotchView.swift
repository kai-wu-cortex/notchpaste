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

struct NotchOpenPerformancePolicy {
    static let deferredWorkDelay: TimeInterval = NotchAnimationTiming.openResponse + 0.08
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

struct AgentClosedStatusStripPolicy {
    static func title(for activity: VibeNotchActivity) -> String {
        title(for: activity, mode: .detailed)
    }

    static func title(for activity: VibeNotchActivity, mode: AgentActivityNotchDisplayMode) -> String {
        guard mode == .detailed else { return "" }
        switch activity {
        case .idle:
            return ""
        case .running:
            return "Working..."
        case .needsInteraction:
            return "Needs input"
        }
    }

    static func sessionsText(count: Int) -> String {
        sessionsText(count: count, mode: .detailed)
    }

    static func sessionsText(count: Int, mode: AgentActivityNotchDisplayMode) -> String {
        guard mode == .detailed else { return "" }
        return "\(count) \(count == 1 ? "session" : "sessions")"
    }

    static func extraWidth(for activity: VibeNotchActivity) -> CGFloat {
        extraWidth(for: activity, mode: .detailed)
    }

    static func extraWidth(for activity: VibeNotchActivity, mode: AgentActivityNotchDisplayMode) -> CGFloat {
        switch activity {
        case .idle:
            return 0
        case .running:
            return mode == .detailed ? 600 : 160
        case .needsInteraction:
            return mode == .detailed ? 560 : 120
        }
    }
}

struct AgentRunningNotchInnerPolicy {
    static let extraWidth: CGFloat = 120
    static let offsetX: CGFloat = -86
}

struct AgentActivityNotchSizePolicy {
    static func size(
        base: CGSize,
        activity: VibeNotchActivity,
        mode: AgentActivityNotchDisplayMode,
        widthAdjustment: Double,
        heightAdjustment: Double
    ) -> CGSize {
        CGSize(
            width: max(
                base.width,
                base.width
                    + AgentClosedStatusStripPolicy.extraWidth(for: activity, mode: mode)
                    + CGFloat(widthAdjustment * 2)
            ),
            height: max(base.height, base.height + 6 + CGFloat(heightAdjustment))
        )
    }
}

struct NotchWidthAdjustmentPreviewMetrics: Equatable {
    let width: CGFloat
    let height: CGFloat
    let leadingMarkerX: CGFloat
    let trailingMarkerX: CGFloat
    let markerColorName: String
}

struct NotchWidthAdjustmentPreviewPolicy {
    static func metrics(screenWidth: CGFloat, notchSize: CGSize) -> NotchWidthAdjustmentPreviewMetrics {
        let previewWidth = min(max(0, notchSize.width), max(0, screenWidth))
        let previewHeight = max(0, notchSize.height)
        let leadingMarkerX = (screenWidth - previewWidth) / 2
        return NotchWidthAdjustmentPreviewMetrics(
            width: previewWidth,
            height: previewHeight,
            leadingMarkerX: leadingMarkerX,
            trailingMarkerX: leadingMarkerX + previewWidth,
            markerColorName: "yellow"
        )
    }
}

struct AgentNotchSizeAdjustmentTarget: Equatable {
    let isAttention: Bool
    let mode: AgentActivityNotchDisplayMode

    static let runningDetailed = AgentNotchSizeAdjustmentTarget(isAttention: false, mode: .detailed)
}

private struct AgentActivitySnapshot: Equatable {
    let activity: VibeNotchActivity
    let sessionCount: Int

    init(dashboard: VibeIslandDashboard) {
        activity = dashboard.notchActivity
        sessionCount = dashboard.sessions.count
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
    private static let agentActivityQueue = DispatchQueue(label: "com.notchpaste.vibe.activity-reduce", qos: .userInteractive)

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
    @State private var agentSessionCount = 0
    @State private var agentActivitySubscription: AnyCancellable?
    @State private var adjustingNotchPreviewTarget: AgentNotchSizeAdjustmentTarget?

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

    private var shouldOffsetRunningNotchInner: Bool {
        isAgentActivityExpanded && agentActivity == .running
    }

    private var notchInnerLayoutWidth: CGFloat {
        max(1, notchSize.width + (shouldOffsetRunningNotchInner ? AgentRunningNotchInnerPolicy.extraWidth : 0))
    }

    private var notchInnerLayoutOffsetX: CGFloat {
        shouldOffsetRunningNotchInner ? AgentRunningNotchInnerPolicy.offsetX : 0
    }

    private var closedHeaderLayoutWidth: CGFloat {
        max(1, notchSize.width - 20 + (shouldOffsetRunningNotchInner ? AgentRunningNotchInnerPolicy.extraWidth : 0))
    }

    private var detailedAgentTextLeadingPadding: CGFloat {
        18 + max(0, -notchInnerLayoutOffsetX) + CGFloat(prefs.agentWorkingTextOffset)
    }

    private var detailedAgentTextTrailingPadding: CGFloat {
        let basePadding: CGFloat
        if shouldOffsetRunningNotchInner {
            basePadding = 18 + max(0, AgentRunningNotchInnerPolicy.extraWidth + notchInnerLayoutOffsetX)
        } else {
            basePadding = 18
        }
        return basePadding - CGFloat(prefs.agentSessionsTextOffset)
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

    private var contentHighlightColor: Color {
        switch viewModel.contentType {
        case .list: return .cyan.opacity(0.92)
        case .vibe: return .purple.opacity(0.92)
        case .settings: return .orange.opacity(0.92)
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
            if isAgentActivityExpanded {
                let adjustment = prefs.agentNotchSizeAdjustment(
                    isAttention: needsAgentInteraction,
                    mode: prefs.agentActivityNotchDisplayMode
                )
                return AgentActivityNotchSizePolicy.size(
                    base: closedNotchSize,
                    activity: agentActivity,
                    mode: prefs.agentActivityNotchDisplayMode,
                    widthAdjustment: adjustment.widthAdjustment,
                    heightAdjustment: adjustment.heightAdjustment
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

            if shouldShowNotchWidthAdjustmentPreview {
                notchWidthAdjustmentTopPreview
                    .transition(.opacity)
                    .notchHierarchyHighlight(
                        ["width-adjustment-preview"],
                        selectedID: viewModel.highlightedHierarchyNodeID,
            adjustments: viewModel.hierarchyDebugAdjustments,
                        color: .yellow,
                        cornerRadius: 14
                    )
                    .zIndex(20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .notchHierarchyHighlight(
            ["appkit-window", "root-notch-view"],
            selectedID: viewModel.highlightedHierarchyNodeID,
            adjustments: viewModel.hierarchyDebugAdjustments,
            color: .white.opacity(0.88),
            cornerRadius: 18
        )
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

    private var shouldShowNotchWidthAdjustmentPreview: Bool {
        viewModel.status == .opened
            && viewModel.contentType == .settings
            && adjustingNotchPreviewTarget != nil
    }

    private var notchWidthAdjustmentPreviewSize: CGSize {
        let target = adjustingNotchPreviewTarget ?? .runningDetailed
        let adjustment = prefs.agentNotchSizeAdjustment(
            isAttention: target.isAttention,
            mode: target.mode
        )
        return AgentActivityNotchSizePolicy.size(
            base: closedNotchSize,
            activity: target.isAttention ? .needsInteraction : .running,
            mode: target.mode,
            widthAdjustment: adjustment.widthAdjustment,
            heightAdjustment: adjustment.heightAdjustment
        )
    }

    private var notchWidthAdjustmentTopPreview: some View {
        NotchWidthAdjustmentTopPreview(
            screenWidth: viewModel.screenRect.width,
            notchSize: notchWidthAdjustmentPreviewSize
        )
        .allowsHitTesting(false)
        .transaction { transaction in
            transaction.animation = nil
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
        applyAgentSnapshot(
            activity: store.dashboard.notchActivity,
            sessionCount: store.dashboard.sessions.count,
            animated: false
        )
        agentActivitySubscription = store.$dashboard
            .receive(on: Self.agentActivityQueue)
            .map(AgentActivitySnapshot.init)
            .dropFirst()
            .removeDuplicates()
            .throttle(for: .milliseconds(80), scheduler: Self.agentActivityQueue, latest: true)
            .receive(on: DispatchQueue.main)
            .sink { snapshot in
                agentSessionCount = snapshot.sessionCount
                guard viewModel.status == .closed else { return }
                applyAgentActivity(snapshot.activity, animated: true)
            }
    }

    private func applyAgentSnapshot(activity: VibeNotchActivity, sessionCount: Int, animated: Bool) {
        agentSessionCount = sessionCount
        applyAgentActivity(activity, animated: animated)
    }

    private func applyAgentActivity(_ activity: VibeNotchActivity, animated: Bool) {
        guard activity != agentActivity else { return }

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
                width: notchInnerLayoutWidth,
                alignment: .topLeading
            )
            .offset(x: notchInnerLayoutOffsetX)
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
                    .notchHierarchyHighlight(
                        ["top-seam-overlay"],
                        selectedID: viewModel.highlightedHierarchyNodeID,
            adjustments: viewModel.hierarchyDebugAdjustments,
                        color: .white,
                        cornerRadius: 1
                    )
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
            .notchHierarchyHighlight(
                ["notch-container", "notch-shape"],
                selectedID: viewModel.highlightedHierarchyNodeID,
            adjustments: viewModel.hierarchyDebugAdjustments,
                color: .cyan,
                cornerRadius: bottomCornerRadius
            )
            .contentShape(Rectangle())
    }

    // MARK: - Inner content（header + opened content）

    @ViewBuilder
    private var notchInner: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
                // headerRow 始终是 closed 刘海高度（或膨胀态高度）；opened 态另起 contentView
                .frame(height: viewModel.status == .opened ? closedNotchSize.height : notchSize.height)
                .notchHierarchyHighlight(
                    ["header-row"],
                    selectedID: viewModel.highlightedHierarchyNodeID,
            adjustments: viewModel.hierarchyDebugAdjustments,
                    color: .white.opacity(0.9),
                    cornerRadius: 10
                )

            if viewModel.status == .opened {
                if showOpenedContent {
                    contentView
                        .frame(width: notchSize.width - 24, height: openedContentSlotHeight, alignment: .top)
                        .clipped()
                        .notchHierarchyHighlight(
                            ["opened-content"],
                            selectedID: viewModel.highlightedHierarchyNodeID,
            adjustments: viewModel.hierarchyDebugAdjustments,
                            color: contentHighlightColor,
                            cornerRadius: 14
                        )
                        .transition(.opacity)
                } else {
                    Color.clear
                        .frame(width: notchSize.width - 24, height: openedContentSlotHeight)
                }
            }
        }
        .notchHierarchyHighlight(
            ["notch-inner"],
            selectedID: viewModel.highlightedHierarchyNodeID,
            adjustments: viewModel.hierarchyDebugAdjustments,
            color: .white.opacity(0.78),
            cornerRadius: 12
        )
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
            width: closedHeaderLayoutWidth,
            height: notchSize.height,
            alignment: .leading
        )
        .notchHierarchyHighlight(
            ["closed-header", "copy-text-hint", "copy-file-hint", "copy-image-hint", "closed-empty"],
            selectedID: viewModel.highlightedHierarchyNodeID,
            adjustments: viewModel.hierarchyDebugAdjustments,
            color: .cyan.opacity(0.92),
            cornerRadius: 12
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
            if prefs.agentActivityNotchDisplayMode == .simple {
                simpleAgentActivityHint
            } else {
                detailedAgentActivityHint
            }
        }
        .notchHierarchyHighlight(
            ["agent-activity-hint"],
            selectedID: viewModel.highlightedHierarchyNodeID,
            adjustments: viewModel.hierarchyDebugAdjustments,
            color: agentActivity == .needsInteraction ? .orange : .cyan,
            cornerRadius: 12
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var detailedAgentActivityHint: some View {
        ZStack(alignment: .leading) {
            if shouldShowAgentFlameWave {
                AgentFlameWaveView(
                    capCenterX: detailedAgentFlameWaveAnchorX,
                    capCenterYOffset: agentActivityIconOffset.height
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .notchHierarchyHighlight(
                        ["agent-flame-wave"],
                        selectedID: viewModel.highlightedHierarchyNodeID,
            adjustments: viewModel.hierarchyDebugAdjustments,
                        color: .purple,
                        cornerRadius: 12
                    )
                    .allowsHitTesting(false)
            }

            Text(AgentClosedStatusStripPolicy.title(for: agentActivity, mode: .detailed))
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.86))
                .lineLimit(1)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(.leading, detailedAgentTextLeadingPadding)

            Text(AgentClosedStatusStripPolicy.sessionsText(count: agentSessionCount, mode: .detailed))
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.86))
                .lineLimit(1)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .padding(.trailing, detailedAgentTextTrailingPadding)
                .notchHierarchyHighlight(
                    ["agent-session-text"],
                    selectedID: viewModel.highlightedHierarchyNodeID,
            adjustments: viewModel.hierarchyDebugAdjustments,
                    color: currentAgentActivityIconColor,
                    cornerRadius: 8
                )

            Group {
                if shouldRenderAgentActivityIcon && !shouldShowAgentFlameWave {
                    agentActivityIcon
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        .padding(.leading, detailedAgentTextLeadingPadding)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .notchHierarchyHighlight(
                ["agent-icon-text"],
                selectedID: viewModel.highlightedHierarchyNodeID,
            adjustments: viewModel.hierarchyDebugAdjustments,
                color: currentAgentActivityIconColor,
                cornerRadius: 10
            )
        }
        .transition(.opacity.combined(with: .scale(scale: 0.94)))
    }

    private var simpleAgentActivityHint: some View {
        ZStack(alignment: .leading) {
            if shouldShowAgentFlameWave {
                AgentFlameWaveView(
                    capCenterX: simpleAgentFlameWaveAnchorX,
                    capCenterYOffset: agentActivityIconOffset.height
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .notchHierarchyHighlight(
                        ["agent-flame-wave"],
                        selectedID: viewModel.highlightedHierarchyNodeID,
            adjustments: viewModel.hierarchyDebugAdjustments,
                        color: .purple,
                        cornerRadius: 12
                    )
                    .allowsHitTesting(false)
            }

            HStack(spacing: 0) {
                if shouldRenderAgentActivityIcon {
                    switch prefs.agentActivityIconPosition {
                    case .leading:
                        agentActivityIcon
                            .padding(.leading, agentActivityLeadingPadding)
                        Spacer(minLength: 0)
                    case .center:
                        Spacer(minLength: 0)
                        agentActivityIcon
                        Spacer(minLength: 0)
                    case .trailing:
                        Spacer(minLength: 0)
                        agentActivityIcon
                            .padding(.trailing, max(12, agentActivityLeadingPadding))
                    }
                } else {
                    Spacer(minLength: 0)
                }
            }
            .notchHierarchyHighlight(
                ["agent-icon-text"],
                selectedID: viewModel.highlightedHierarchyNodeID,
            adjustments: viewModel.hierarchyDebugAdjustments,
                color: currentAgentActivityIconColor,
                cornerRadius: 10
            )
        }
        .transition(.opacity.combined(with: .scale(scale: 0.94)))
    }

    private var shouldShowAgentFlameWave: Bool {
        agentActivity == .running && prefs.agentActivityIconEffect == .flameWave
    }

    private var detailedAgentFlameWaveAnchorX: CGFloat {
        guard shouldRenderAgentActivityIcon else { return 0 }
        return 30 + agentActivityIconOffset.width + agentActivityIconSize * 0.5
    }

    private var simpleAgentFlameWaveAnchorX: CGFloat {
        guard shouldRenderAgentActivityIcon else { return 0 }
        switch prefs.agentActivityIconPosition {
        case .leading:
            return agentActivityLeadingPadding + agentActivityIconOffset.width + agentActivityIconSize * 0.5
        case .center:
            return notchSize.width * 0.5 + agentActivityIconOffset.width
        case .trailing:
            return max(0, notchSize.width - max(12, agentActivityLeadingPadding) + agentActivityIconOffset.width - agentActivityIconSize * 0.5)
        }
    }

    private var agentActivityLeadingPadding: CGFloat {
        let leftExpansionWidth = max(0, (notchSize.width - closedNotchSize.width) / 2)
        return max(12, leftExpansionWidth - 34)
    }

    private var currentAgentActivityIconStyle: AgentActivityIconStyle {
        needsAgentInteraction ? prefs.agentAttentionIconStyle : prefs.agentRunningIconStyle
    }

    private var shouldRenderAgentActivityIcon: Bool {
        currentAgentActivityIconStyle != .none
    }

    private var currentAgentActivityIconColor: Color {
        if needsAgentInteraction {
            return Color(
                red: prefs.agentAttentionIconRed,
                green: prefs.agentAttentionIconGreen,
                blue: prefs.agentAttentionIconBlue
            )
        }
        return Color(
            red: prefs.agentRunningIconRed,
            green: prefs.agentRunningIconGreen,
            blue: prefs.agentRunningIconBlue
        )
    }

    private var currentAgentCustomIconPath: String? {
        needsAgentInteraction ? prefs.agentAttentionCustomIconPath : prefs.agentRunningCustomIconPath
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
        if currentAgentActivityIconStyle == .none {
            EmptyView()
        } else if let path = currentAgentCustomIconPath, let image = cachedAgentIcon(at: path) {
            effectAgentActivityIcon {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: agentActivityIconSize, height: agentActivityIconSize)
                    .clipShape(RoundedRectangle(cornerRadius: max(3, agentActivityIconSize * 0.22), style: .continuous))
            }
            .offset(agentActivityIconOffset)
        } else if currentAgentActivityIconStyle == .lifeGrid {
            AgentLifeGridIcon(color: currentAgentActivityIconColor, effect: prefs.agentActivityIconEffect)
                .frame(width: agentActivityIconSize, height: agentActivityIconSize)
                .offset(agentActivityIconOffset)
        } else {
            effectAgentActivityIcon {
                Group {
                    switch currentAgentActivityIconStyle {
                    case .none:
                        EmptyView()
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
                    case .asciiPrompt, .asciiScan, .asciiPulse:
                        AgentASCIIActivityIcon(style: currentAgentActivityIconStyle, color: currentAgentActivityIconColor)
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
        case .none, .flameWave:
            content()
                .frame(width: agentActivityIconSize, height: agentActivityIconSize)
        default:
            TimelineView(AgentAnimationFrameRatePolicy.decorativeTimelineSchedule) { timeline in
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
        TimelineView(AgentAnimationFrameRatePolicy.decorativeTimelineSchedule) { timeline in
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
        .notchHierarchyHighlight(
            ["opened-header", "opened-title", "opened-tabs", "opened-settings", "opened-close"],
            selectedID: viewModel.highlightedHierarchyNodeID,
            adjustments: viewModel.hierarchyDebugAdjustments,
            color: .white.opacity(0.9),
            cornerRadius: 10
        )
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
                    .notchHierarchyHighlight(
                        ["clipboard-list"],
                        selectedID: viewModel.highlightedHierarchyNodeID,
            adjustments: viewModel.hierarchyDebugAdjustments,
                        color: .cyan,
                        cornerRadius: 12
                    )
            case .vibe:
                LazyVibeContentView {
                    viewModel.notchClose()
                }
                .notchHierarchyHighlight(
                    ["lazy-vibe", "latest-diff", "vibe-tabs", "agent-session-list"],
                    selectedID: viewModel.highlightedHierarchyNodeID,
            adjustments: viewModel.hierarchyDebugAdjustments,
                    color: .purple,
                    cornerRadius: 12
                )
            case .settings:
                NotchSettingsView(
                    viewModel: viewModel,
                    adjustingNotchPreviewTarget: $adjustingNotchPreviewTarget,
                    onRequestPermission: onRequestPermission,
                    onQuit: onQuit
                )
                .notchHierarchyHighlight(
                    ["settings-view"],
                    selectedID: viewModel.highlightedHierarchyNodeID,
            adjustments: viewModel.hierarchyDebugAdjustments,
                    color: .orange,
                    cornerRadius: 12
                )
            }
        }
        .frame(width: notchSize.width - 24)
    }
}

private struct NotchHierarchyHighlightModifier: ViewModifier {
    let isActive: Bool
    let adjustment: NotchHierarchyDebugAdjustment
    let color: Color
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, isActive ? CGFloat(adjustment.widthDelta) / 2 : 0)
            .padding(.vertical, isActive ? CGFloat(adjustment.heightDelta) / 2 : 0)
            .overlay {
                if isActive {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(color.opacity(0.95), lineWidth: 2)
                        .shadow(color: color.opacity(0.75), radius: 7)
                        .allowsHitTesting(false)
                }
            }
            .offset(
                x: isActive ? CGFloat(adjustment.offsetX) : 0,
                y: isActive ? CGFloat(adjustment.offsetY) : 0
            )
            .animation(.easeOut(duration: 0.12), value: isActive)
            .animation(.easeOut(duration: 0.08), value: adjustment)
    }
}

private extension View {
    func notchHierarchyHighlight(
        _ nodeIDs: [String],
        selectedID: String?,
        adjustments: [String: NotchHierarchyDebugAdjustment] = [:],
        color: Color,
        cornerRadius: CGFloat
    ) -> some View {
        let activeID = selectedID.flatMap { selected in
            nodeIDs.contains(selected) ? selected : nil
        }
        return modifier(
            NotchHierarchyHighlightModifier(
                isActive: activeID != nil,
                adjustment: activeID.flatMap { adjustments[$0] } ?? .zero,
                color: color,
                cornerRadius: cornerRadius
            )
        )
    }
}

private struct NotchWidthAdjustmentTopPreview: View {
    let screenWidth: CGFloat
    let notchSize: CGSize

    var body: some View {
        let metrics = NotchWidthAdjustmentPreviewPolicy.metrics(
            screenWidth: screenWidth,
            notchSize: notchSize
        )
        let markerHeight = max(metrics.height + 16, 32)
        let previewRadius = max(7, min(18, metrics.height * 0.38))

        ZStack(alignment: .topLeading) {
            NotchShape(topCornerRadius: 7, bottomCornerRadius: previewRadius)
                .fill(Color.black.opacity(0.96))
                .overlay(
                    NotchShape(topCornerRadius: 7, bottomCornerRadius: previewRadius)
                        .stroke(Color.cyan.opacity(0.68), lineWidth: 1.5)
                )
                .shadow(color: Color.cyan.opacity(0.26), radius: 12)
                .frame(width: metrics.width, height: metrics.height)
                .position(x: screenWidth / 2, y: metrics.height / 2 + 3)

            edgeMarker
                .frame(height: markerHeight)
                .position(x: metrics.leadingMarkerX, y: markerHeight / 2)

            edgeMarker
                .frame(height: markerHeight)
                .position(x: metrics.trailingMarkerX, y: markerHeight / 2)
        }
        .frame(width: screenWidth, height: markerHeight + 6, alignment: .top)
    }

    private var edgeMarker: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(Color.yellow)
            .frame(width: 4)
            .shadow(color: Color.yellow.opacity(0.74), radius: 7)
    }
}

private struct LazyVibeContentView: View {
    @ObservedObject private var vibeStore = VibeAgentStore.shared
    @State private var latestDiffExpanded = NotchLatestDiffTabPolicy.defaultIsExpanded
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
        let isLatestDiffCard = session.action == .monitor && !compactDiff.isEmpty
        let visibleDiff = isLatestDiffCard
            ? NotchLatestDiffTabPolicy.visibleLines(from: compactDiff, isExpanded: latestDiffExpanded)
            : Array(compactDiff.prefix(7))

        return VStack(alignment: .leading, spacing: 7) {
            agentCardHeader(for: session, isLatestDiffCard: isLatestDiffCard)

            if !compactDiff.isEmpty {
                if !isLatestDiffCard || latestDiffExpanded {
                    Text(session.detail)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(session.action == .approval ? agentAttentionColor : session.tint)
                        .lineLimit(1)
                }

                if !visibleDiff.isEmpty {
                    notchCodeDiffBlock(visibleDiff)
                }
            } else {
                Text(session.detail.isEmpty ? session.state : session.detail)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(2)
            }

            if session.action == .approval {
                HStack(spacing: 7) {
                    ForEach(session.approvalActions, id: \.self) { action in
                        Button(action.title) {
                            if action.isDeny {
                                vibeStore.deny(sessionID: session.id)
                            } else {
                                vibeStore.allow(sessionID: session.id)
                            }
                        }
                        .buttonStyle(NotchApprovalActionButtonStyle(action: action))
                    }
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

    @ViewBuilder
    private func agentCardHeader(for session: VibeSession, isLatestDiffCard: Bool) -> some View {
        if isLatestDiffCard {
            Button {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
                    latestDiffExpanded.toggle()
                }
            } label: {
                agentCardHeaderContent(for: session, showsChevron: true)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .accessibilityLabel(latestDiffExpanded ? "收起 Latest Diff" : "展开 Latest Diff")
        } else {
            agentCardHeaderContent(for: session, showsChevron: false)
        }
    }

    private func agentCardHeaderContent(for session: VibeSession, showsChevron: Bool) -> some View {
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

            if showsChevron {
                Image(systemName: latestDiffExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(session.tint.opacity(0.85))
                    .frame(width: 14, height: 14)
            }
        }
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

struct NotchLatestDiffTabPolicy {
    static let defaultIsExpanded = false

    static func visibleLines(from lines: [VibeCodeDiffLine], isExpanded: Bool) -> [VibeCodeDiffLine] {
        isExpanded ? lines : []
    }
}

struct AgentAnimationFrameRatePolicy {
    static let minimumFramesPerSecond = 60
    static let maximumFramesPerSecond = 120
    static let decorativeFramesPerSecond = 30

    static var preferredFramesPerSecond: Int {
        targetFramesPerSecond(forDisplayRefreshRate: mainDisplayRefreshRate)
    }

    static var decorativeTimelineSchedule: PeriodicTimelineSchedule {
        .periodic(
            from: .now,
            by: 1.0 / Double(decorativeFramesPerSecond)
        )
    }

    static func targetFramesPerSecond(forDisplayRefreshRate refreshRate: Double?) -> Int {
        guard let refreshRate, refreshRate > 0 else { return maximumFramesPerSecond }
        return refreshRate >= 90 ? maximumFramesPerSecond : minimumFramesPerSecond
    }

    private static var mainDisplayRefreshRate: Double? {
        guard
            let screenNumber = NSScreen.main?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
            let mode = CGDisplayCopyDisplayMode(screenNumber)
        else {
            return nil
        }
        return mode.refreshRate > 0 ? mode.refreshRate : nil
    }
}

enum AgentFlameWaveColorRole: Equatable {
    case purple
    case white
}

struct AgentFlameWaveCellFrame: Equatable {
    let centerX: CGFloat
    let centerY: CGFloat
    let opacity: Double
    let scale: CGFloat
    let colorRole: AgentFlameWaveColorRole
}

struct AgentFlameWaveSparkColor: Equatable {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat

    static let `default` = AgentFlameWaveSparkColor(red: 1, green: 1, blue: 1)
    static let defaultPurple = AgentFlameWaveSparkColor(red: 0.78, green: 0.28, blue: 1.0)

    init(red: CGFloat, green: CGFloat, blue: CGFloat) {
        self.red = min(max(red, 0), 1)
        self.green = min(max(green, 0), 1)
        self.blue = min(max(blue, 0), 1)
    }
}

struct AgentFlameWaveFrame: Equatable {
    static let columns = 104
    static let rows = 7
    static let cellCount = columns * rows
    static let columnPitch: CGFloat = 5.8
    static let seed: UInt64 = 0xB179_A8E5_47DA_31C9

    let cells: [AgentFlameWaveCellFrame]
    let growthProgress: CGFloat
    let columnCount: Int

    static func make(
        elapsed time: TimeInterval,
        seed: UInt64 = seed,
        tuning: AgentFlameWaveTuning = AgentFlameWaveTuning(),
        renderWidth: CGFloat? = nil
    ) -> AgentFlameWaveFrame {
        let safeTime = max(0, time)
        let animatedTime = CGFloat(safeTime)
        let growthTime = animatedTime * tuning.expansionSpeed
        let growthProgress = 0.10 + smoothstep(edge0: 0, edge1: 1.65, x: growthTime) * 0.90
        let columnCount = renderWidth.map { Self.columnCount(forRenderWidth: $0, columnPitch: tuning.columnPitch) } ?? columns
        let cellCount = columnCount * rows
        var cells: [AgentFlameWaveCellFrame] = []
        cells.reserveCapacity(cellCount)

        for index in 0..<cellCount {
            let column = index % columnCount
            let row = index / columnCount
            let x = CGFloat(column) / CGFloat(max(1, columnCount - 1))
            let lane = CGFloat(row) / CGFloat(max(1, rows - 1))
            let jitter = CGFloat(unitNoise(seed &+ UInt64(index) &* 0x9E37_79B9_7F4A_7C15))
            let phaseNoise = CGFloat(unitNoise(seed &+ UInt64(index) &* 0xA24B_AED4_963E_E407))
            let verticalNoise = CGFloat(unitNoise(seed &+ UInt64(index) &* 0xC6BC_2796_92B5_C323))
            let sparkTime = CGFloat(safeTime) * tuning.sparkSpeed
            let sparkStep = UInt64(Int(safeTime * 9 * Double(tuning.sparkSpeed)))
            let tailSparkNoise = CGFloat(unitNoise(
                seed
                    &+ UInt64(index) &* 0xD1B5_4A32_D192_ED03
                    &+ sparkStep &* 0x94D0_49BB_1331_11EB
            ))
            let secondarySparkNoise = CGFloat(unitNoise(
                seed
                    &+ UInt64(index) &* 0x94D0_49BB_1331_11EB
                    &+ sparkStep &* 0xD1B5_4A32_D192_ED03
            ))
            let waveNoise = tuning.waveNoise
            let noisyPhase = sin(
                CGFloat(safeTime) * (2.1 + phaseNoise * 4.3)
                    + x * (8.0 + phaseNoise * 17.0)
                    + lane * (3.0 + jitter * 8.0)
            ) * waveNoise * 2.0
            let wave = 0.5 + 0.5 * sin((x * 16.5 - CGFloat(safeTime) * 7.2) + lane * 2.1 + jitter * 4.2 + noisyPhase)
            let microPhase = sin(
                CGFloat(safeTime) * (5.2 + jitter * 9.5)
                    + x * (18.0 + verticalNoise * 27.0)
                    + lane * (8.0 + phaseNoise * 12.0)
            ) * waveNoise * 1.35
            let microWave = 0.5 + 0.5 * sin((x * 39.0 + lane * 11.0) - CGFloat(safeTime) * 18.0 + jitter * 6.0 + microPhase)
            let ramp = smoothstep(edge0: 0.14, edge1: 0.56, x: x)
            let rightBloom = smoothstep(edge0: 0.54, edge1: 0.94, x: x)
            let safeSparkHorizontalSpread = max(tuning.sparkHorizontalSpread, 0.001)
            let sparkDistance = abs(x - tuning.sparkHorizontalCenter) / safeSparkHorizontalSpread
            let horizontalSparkFocus = smoothstep(edge0: 1.0, edge1: 0.0, x: min(1, sparkDistance))
            let sparkNoise = clamp(
                tailSparkNoise * (1.15 - tuning.sparkNoise * 0.18)
                    + secondarySparkNoise * tuning.sparkNoise * 0.35,
                min: 0,
                max: 1
            )
            let distributedSparkNoise = CGFloat(pow(
                Double(clamp(sparkNoise, min: 0.001, max: 1)),
                Double(tuning.sparkDistribution)
            ))
            let flickerPhase = sparkTime * (11.0 + phaseNoise * 9.0)
                + x * 19.0
                + lane * 7.0
                + jitter * 5.0
            let flickerWave = 0.5 + 0.5 * sin(flickerPhase)
            let tailSpark = horizontalSparkFocus
                * distributedSparkNoise
                * (0.24 + microWave * 0.24 + flickerWave * 0.24)
                * (0.74 + tuning.sparkNoise * 0.30)
            let leftParticle = max(0, 1 - abs((x - 0.34) / 0.22))
            let verticalFalloff = 1 - abs(lane - 0.5) * 0.34
            let primaryLiftPhase = CGFloat(safeTime) * (3.0 + jitter * 6.5)
                + x * 12.0
                + phaseNoise * 7.0
            let secondaryLiftPhase = CGFloat(safeTime) * (7.5 + verticalNoise * 5.0)
                + lane * 16.0
                + x * 9.0
            let irregularLiftBase = sin(primaryLiftPhase) * 0.045
                + (verticalNoise - 0.5) * 0.055
                + sin(secondaryLiftPhase) * 0.018
            let irregularLift = irregularLiftBase * waveNoise
            let centerY = clamp(
                0.5
                    + (lane - 0.5) * 0.70
                    + sin(CGFloat(safeTime) * 5.4 + x * 14 + jitter * 3 + noisyPhase * 0.45) * 0.020 * waveNoise
                    + irregularLift,
                min: 0.12,
                max: 0.88
            )
            let horizontalDriftPhase = animatedTime
                * (1.8 + phaseNoise * 3.7 + verticalNoise * 1.4)
                * tuning.horizontalDriftSpeed
                + x * (10.0 + jitter * 16.0)
                + lane * (7.0 + phaseNoise * 11.0)
            let horizontalDrift = sin(horizontalDriftPhase)
                * tuning.horizontalDrift
                * (0.25 + ramp * 0.75)
            let renderedX = clamp(x + horizontalDrift, min: CGFloat(0), max: CGFloat(1))
            let fadePhase = animatedTime
                * (2.7 + verticalNoise * 5.3 + phaseNoise * 1.8)
                * tuning.fadeSpeed
                + x * (16.0 + jitter * 20.0)
                + lane * (9.0 + phaseNoise * 12.0)
            let fadeWave = 0.5 + 0.5 * sin(fadePhase + microPhase * 0.25)
            let fadeDepth = pow(fadeWave, 1.32) * tuning.fadeDepth
            let fadeMask = clamp(1 - fadeDepth, min: 0.05, max: 1)
            let baseOpacity = 0.035
                + ramp * (0.22 + wave * 0.18)
                + rightBloom * (0.18 + microWave * 0.34)
                + tailSpark
                + leftParticle * wave * 0.20
            let opacity = Double(clamp(baseOpacity * verticalFalloff * fadeMask, min: 0.006, max: 0.98))
            let scale = CGFloat(0.58 + wave * 0.22 + microWave * 0.16 + rightBloom * (0.08 + tailSparkNoise * 0.10))
                * (1 - fadeDepth * 0.16)
            let sparkGate = horizontalSparkFocus * distributedSparkNoise * (0.58 + microWave * 0.24 + flickerWave * 0.18)
            let isWhite = (horizontalSparkFocus > 0.36 && sparkGate > 0.22)
                || (horizontalSparkFocus > 0.58 && wave > 0.68 && sparkGate > 0.15)
                || (horizontalSparkFocus > 0.28 && distributedSparkNoise > 0.82)
                || ((column + row * 5 + Int(sparkStep % 17)) % 67 == 0 && horizontalSparkFocus > 0.25 && sparkNoise > 0.55)

            cells.append(AgentFlameWaveCellFrame(
                centerX: renderedX,
                centerY: centerY,
                opacity: opacity,
                scale: scale,
                colorRole: isWhite ? .white : .purple
            ))
        }

        return AgentFlameWaveFrame(
            cells: cells,
            growthProgress: growthProgress,
            columnCount: columnCount
        )
    }

    static func columnCount(forRenderWidth width: CGFloat, columnPitch: CGFloat = columnPitch) -> Int {
        let safePitch = min(max(columnPitch, 3.2), 12.0)
        return max(2, Int(floor(max(1, width) / safePitch)) + 1)
    }

    private static func unitNoise(_ value: UInt64) -> Double {
        let mixed = mix(value)
        return Double(mixed & 0xFFFF) / Double(0xFFFF)
    }

    private static func mix(_ value: UInt64) -> UInt64 {
        var x = value
        x = (x ^ (x >> 30)) &* 0xBF58_476D_1CE4_E5B9
        x = (x ^ (x >> 27)) &* 0x94D0_49BB_1331_11EB
        return x ^ (x >> 31)
    }

    private static func clamp(_ value: CGFloat, min lowerBound: CGFloat, max upperBound: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, lowerBound), upperBound)
    }

    private static func smoothstep(edge0: CGFloat, edge1: CGFloat, x: CGFloat) -> CGFloat {
        let normalized = clamp((x - edge0) / (edge1 - edge0), min: 0, max: 1)
        return normalized * normalized * (3 - 2 * normalized)
    }
}

struct AgentFlameWaveDrawingPolicy {
    static let cellScaleMultiplier: CGFloat = 1.0

    static func cellSide(tuning: AgentFlameWaveTuning) -> CGFloat {
        min(max(1.4, tuning.cellSize), 5.2)
    }

    static func cellBrightness(displayProgress: CGFloat, opacity: Double, tuning: AgentFlameWaveTuning) -> CGFloat {
        let progress = min(max(displayProgress, 0), 1)
        let capHeat = CGFloat(pow(Double(1 - progress), Double(tuning.brightnessPower)))
        return min(max(0.12 + capHeat * 0.78 + CGFloat(opacity) * 0.12, 0), 1)
    }

    static func capSize(for size: CGSize) -> CGSize {
        CGSize(
            width: min(max(24, size.height * 0.96), 42),
            height: max(20, size.height * 0.92)
        )
    }
}

struct AgentFlameWaveTuning: Equatable {
    let cellSize: CGFloat
    let glowScale: CGFloat
    let glowOpacity: Double
    let leadingBlur: CGFloat
    let brightnessPower: CGFloat
    let bloomStrength: CGFloat
    let purpleColor: AgentFlameWaveSparkColor
    let sparkColor: AgentFlameWaveSparkColor
    let columnPitch: CGFloat
    let horizontalOffset: CGFloat
    let waveNoise: CGFloat
    let sparkNoise: CGFloat
    let sparkDistribution: CGFloat
    let sparkHorizontalCenter: CGFloat
    let sparkHorizontalSpread: CGFloat
    let sparkSpeed: CGFloat
    let expansionSpeed: CGFloat
    let widthScale: CGFloat
    let horizontalDrift: CGFloat
    let horizontalDriftSpeed: CGFloat
    let fadeDepth: CGFloat
    let fadeSpeed: CGFloat

    init(
        cellSize: CGFloat = 2.6,
        glowScale: CGFloat = 2.45,
        glowOpacity: Double = 1.0,
        leadingBlur: CGFloat = 1.0,
        brightnessPower: CGFloat = 1.35,
        bloomStrength: CGFloat = 1.0,
        purpleColor: AgentFlameWaveSparkColor = .defaultPurple,
        sparkColor: AgentFlameWaveSparkColor = .default,
        columnPitch: CGFloat = 5.8,
        horizontalOffset: CGFloat = 0,
        waveNoise: CGFloat = 1.0,
        sparkNoise: CGFloat = 1.0,
        sparkDistribution: CGFloat = 1.65,
        sparkHorizontalCenter: CGFloat = 0.78,
        sparkHorizontalSpread: CGFloat = 0.30,
        sparkSpeed: CGFloat = 1.0,
        expansionSpeed: CGFloat = 1.0,
        widthScale: CGFloat = 1.0,
        horizontalDrift: CGFloat = 0.012,
        horizontalDriftSpeed: CGFloat = 1.0,
        fadeDepth: CGFloat = 0.10,
        fadeSpeed: CGFloat = 1.0
    ) {
        self.cellSize = min(max(cellSize, 0.0), 5.2)
        self.glowScale = min(max(glowScale, 0.0), 8.0)
        self.glowOpacity = min(max(glowOpacity, 0.0), 3.0)
        self.leadingBlur = min(max(leadingBlur, 0.0), 4.0)
        self.brightnessPower = min(max(brightnessPower, 0.0), 4.0)
        self.bloomStrength = min(max(bloomStrength, 0.0), 3.0)
        self.purpleColor = purpleColor
        self.sparkColor = sparkColor
        self.columnPitch = min(max(columnPitch, 0.0), 12.0)
        self.horizontalOffset = min(max(horizontalOffset, -240.0), 240.0)
        self.waveNoise = min(max(waveNoise, 0.0), 3.0)
        self.sparkNoise = min(max(sparkNoise, 0.0), 3.0)
        self.sparkDistribution = min(max(sparkDistribution, 0.0), 4.0)
        self.sparkHorizontalCenter = min(max(sparkHorizontalCenter, 0.0), 1.0)
        self.sparkHorizontalSpread = min(max(sparkHorizontalSpread, 0.0), 1.0)
        self.sparkSpeed = min(max(sparkSpeed, 0.0), 4.0)
        self.expansionSpeed = min(max(expansionSpeed, 0.0), 4.0)
        self.widthScale = min(max(widthScale, 0.0), 4.0)
        self.horizontalDrift = min(max(horizontalDrift, 0.0), 0.08)
        self.horizontalDriftSpeed = min(max(horizontalDriftSpeed, 0.0), 4.0)
        self.fadeDepth = min(max(fadeDepth, 0.0), 0.95)
        self.fadeSpeed = min(max(fadeSpeed, 0.0), 4.0)
    }

    init(preferences: PreferencesStore) {
        self.init(
            cellSize: CGFloat(preferences.agentFlameWaveCellSize),
            glowScale: CGFloat(preferences.agentFlameWaveGlowScale),
            glowOpacity: preferences.agentFlameWaveGlowOpacity,
            leadingBlur: CGFloat(preferences.agentFlameWaveLeadingBlur),
            brightnessPower: CGFloat(preferences.agentFlameWaveBrightnessPower),
            bloomStrength: CGFloat(preferences.agentFlameWaveBloomStrength),
            purpleColor: AgentFlameWaveSparkColor(
                red: CGFloat(preferences.agentFlameWavePurpleRed),
                green: CGFloat(preferences.agentFlameWavePurpleGreen),
                blue: CGFloat(preferences.agentFlameWavePurpleBlue)
            ),
            sparkColor: AgentFlameWaveSparkColor(
                red: CGFloat(preferences.agentFlameWaveSparkRed),
                green: CGFloat(preferences.agentFlameWaveSparkGreen),
                blue: CGFloat(preferences.agentFlameWaveSparkBlue)
            ),
            columnPitch: CGFloat(preferences.agentFlameWaveColumnPitch),
            horizontalOffset: CGFloat(preferences.agentFlameWaveHorizontalOffset),
            waveNoise: CGFloat(preferences.agentFlameWaveWaveNoise),
            sparkNoise: CGFloat(preferences.agentFlameWaveSparkNoise),
            sparkDistribution: CGFloat(preferences.agentFlameWaveSparkDistribution),
            sparkHorizontalCenter: CGFloat(preferences.agentFlameWaveSparkHorizontalCenter),
            sparkHorizontalSpread: CGFloat(preferences.agentFlameWaveSparkHorizontalSpread),
            sparkSpeed: CGFloat(preferences.agentFlameWaveSparkSpeed),
            expansionSpeed: CGFloat(preferences.agentFlameWaveExpansionSpeed),
            widthScale: CGFloat(preferences.agentFlameWaveWidthScale),
            horizontalDrift: CGFloat(preferences.agentFlameWaveHorizontalDrift),
            horizontalDriftSpeed: CGFloat(preferences.agentFlameWaveHorizontalDriftSpeed),
            fadeDepth: CGFloat(preferences.agentFlameWaveFadeDepth),
            fadeSpeed: CGFloat(preferences.agentFlameWaveFadeSpeed)
        )
    }
}

final class AgentFlameWaveFrameClock: ObservableObject {
    static let shared = AgentFlameWaveFrameClock()

    @Published private(set) var elapsed: TimeInterval = 0

    private let queue = DispatchQueue(label: "com.notchpaste.agent-flame-wave.animation", qos: .userInteractive)
    private var timer: DispatchSourceTimer?
    private var observerCount = 0
    private var generation = 0

    private init() {}

    func retain() {
        observerCount += 1
        guard timer == nil else { return }
        startTimer()
    }

    func release() {
        observerCount = max(0, observerCount - 1)
        guard observerCount == 0 else { return }

        generation += 1
        timer?.setEventHandler {}
        timer?.cancel()
        timer = nil
    }

    func update(tuning _: AgentFlameWaveTuning) {}

    private func startTimer() {
        generation += 1
        let timerGeneration = generation
        let framesPerSecond = AgentAnimationFrameRatePolicy.preferredFramesPerSecond
        let nanosecondsPerFrame = max(1, 1_000_000_000 / framesPerSecond)
        let startedAt = CACurrentMediaTime()
        elapsed = 0

        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(
            deadline: .now(),
            repeating: .nanoseconds(nanosecondsPerFrame),
            leeway: framesPerSecond >= AgentAnimationFrameRatePolicy.maximumFramesPerSecond ? .nanoseconds(0) : .milliseconds(1)
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let elapsed = CACurrentMediaTime() - startedAt
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == timerGeneration, self.timer != nil else { return }
                self.elapsed = elapsed
            }
        }
        timer = source
        source.resume()
    }

    deinit {
        timer?.setEventHandler {}
        timer?.cancel()
    }
}

struct AgentFlameWaveView: View {
    let capCenterX: CGFloat
    let capCenterYOffset: CGFloat

    @ObservedObject private var frameClock = AgentFlameWaveFrameClock.shared
    @ObservedObject private var prefs = PreferencesStore.shared

    var body: some View {
        let tuning = AgentFlameWaveTuning(preferences: prefs)

        GeometryReader { _ in
            Canvas(opaque: false, colorMode: .linear, rendersAsynchronously: true) { context, size in
                let resolvedCapCenterX = resolvedCapCenterX(for: size)
                let renderWidth = flameWaveRenderWidth(for: size, tuning: tuning)
                let frame = AgentFlameWaveFrame.make(
                    elapsed: frameClock.elapsed,
                    tuning: tuning,
                    renderWidth: renderWidth
                )
                drawBandBackground(
                    context: &context,
                    size: size,
                    capCenterX: resolvedCapCenterX,
                    tuning: tuning
                )
                drawGlow(
                    frame: frame,
                    context: &context,
                    size: size,
                    capCenterX: resolvedCapCenterX,
                    tuning: tuning
                )
                drawCells(
                    frame: frame,
                    context: &context,
                    size: size,
                    capCenterX: resolvedCapCenterX,
                    tuning: tuning
                )
            }
            .clipped()
        }
        .onAppear {
            frameClock.update(tuning: tuning)
            frameClock.retain()
        }
        .onChange(of: tuning) { _, newTuning in
            frameClock.update(tuning: newTuning)
        }
        .onDisappear { frameClock.release() }
    }

    private func drawBandBackground(
        context: inout GraphicsContext,
        size: CGSize,
        capCenterX: CGFloat,
        tuning: AgentFlameWaveTuning
    ) {
        let bandRect = CGRect(
            x: -size.height * 0.34,
            y: -2,
            width: size.width + size.height * 0.34 + 4,
            height: size.height + 4
        )
        let purple = tuning.purpleColor
        let deepPurple = Color(
            red: purple.red * 0.34,
            green: purple.green * 0.24,
            blue: purple.blue * 0.58
        )
        let mainPurple = Color(red: purple.red, green: purple.green, blue: purple.blue)
        context.fill(
            Path(roundedRect: bandRect, cornerRadius: size.height * 0.48),
            with: .linearGradient(
                Gradient(colors: [
                    Color.white.opacity(0.12 * Double(tuning.bloomStrength)),
                    mainPurple.opacity(0.34),
                    mainPurple.opacity(0.26),
                    deepPurple.opacity(0.22),
                    Color.black.opacity(0.02)
                ]),
                startPoint: CGPoint(x: bandRect.minX + tuning.horizontalOffset, y: bandRect.midY),
                endPoint: CGPoint(x: bandRect.maxX, y: bandRect.midY)
            )
        )
    }

    private func drawGlow(
        frame: AgentFlameWaveFrame,
        context: inout GraphicsContext,
        size: CGSize,
        capCenterX: CGFloat,
        tuning: AgentFlameWaveTuning
    ) {
        for cell in frame.cells {
            guard let layout = cellLayout(
                cell,
                frame: frame,
                size: size,
                capCenterX: capCenterX,
                scaleMultiplier: tuning.glowScale,
                tuning: tuning
            ) else { continue }
            context.fill(
                Path(roundedRect: layout.rect, cornerRadius: max(1, layout.rect.width * 0.30)),
                with: .color(
                    color(for: cell.colorRole, opacity: cell.opacity, brightness: layout.brightness, tuning: tuning)
                        .opacity(cell.opacity * (0.16 + Double(layout.brightness) * 0.18) * layout.reveal * tuning.glowOpacity * (1 + Double(tuning.bloomStrength) * 0.18))
                )
            )
        }
    }

    private func drawCells(
        frame: AgentFlameWaveFrame,
        context: inout GraphicsContext,
        size: CGSize,
        capCenterX: CGFloat,
        tuning: AgentFlameWaveTuning
    ) {
        drawCells(
            frame: frame,
            context: &context,
            size: size,
            capCenterX: capCenterX,
            tuning: tuning,
            blurRange: nil
        )

        let blurBuckets: [(ClosedRange<CGFloat>, CGFloat)] = [
            (0.30...1.10, 0.7),
            (1.10...2.20, 1.5),
            (2.20...4.10, 2.8)
        ]
        for bucket in blurBuckets {
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: bucket.1))
                drawCells(
                    frame: frame,
                    context: &layer,
                    size: size,
                    capCenterX: capCenterX,
                    tuning: tuning,
                    blurRange: bucket.0
                )
            }
        }
    }

    private func drawCells(
        frame: AgentFlameWaveFrame,
        context: inout GraphicsContext,
        size: CGSize,
        capCenterX: CGFloat,
        tuning: AgentFlameWaveTuning,
        blurRange: ClosedRange<CGFloat>?
    ) {
        for cell in frame.cells {
            guard let layout = cellLayout(
                cell,
                frame: frame,
                size: size,
                capCenterX: capCenterX,
                scaleMultiplier: AgentFlameWaveDrawingPolicy.cellScaleMultiplier,
                tuning: tuning
            ) else { continue }
            if let blurRange {
                guard blurRange.contains(layout.blurRadius) else { continue }
            } else {
                guard layout.blurRadius < 0.30 else { continue }
            }
            context.fill(
                Path(roundedRect: layout.rect, cornerRadius: max(0.8, layout.rect.width * 0.14)),
                with: .color(
                    color(for: cell.colorRole, opacity: cell.opacity, brightness: layout.brightness, tuning: tuning)
                        .opacity(cell.opacity * layout.reveal)
                )
            )
        }
    }

    private func cellLayout(
        _ cell: AgentFlameWaveCellFrame,
        frame: AgentFlameWaveFrame,
        size: CGSize,
        capCenterX: CGFloat,
        scaleMultiplier: CGFloat,
        tuning: AgentFlameWaveTuning
    ) -> (rect: CGRect, reveal: Double, brightness: CGFloat, blurRadius: CGFloat)? {
        let mirroredX = 1 - cell.centerX
        let reveal = frame.growthProgress >= 0.995
            ? 1
            : 1 - smoothstep(
                edge0: frame.growthProgress - 0.055,
                edge1: frame.growthProgress + 0.045,
                x: mirroredX
            )
        guard reveal > 0.01 else { return nil }

        let bandHeight = max(1, size.height * 1.08)
        let baseSide = AgentFlameWaveDrawingPolicy.cellSide(tuning: tuning)
        let leadingOverscan = flameWaveLeadingOverscan(tuning: tuning, baseSide: baseSide)
        let waveWidth = flameWaveRenderWidth(for: size, tuning: tuning)
        let side = baseSide * cell.scale * scaleMultiplier
        let yInset = (size.height - bandHeight) / 2
        let center = CGPoint(
            x: mirroredX * waveWidth - leadingOverscan + tuning.horizontalOffset,
            y: yInset + cell.centerY * bandHeight
        )
        let rect = CGRect(
            x: center.x - side / 2,
            y: center.y - side / 2,
            width: side,
            height: side
        )
        return (
            rect: rect,
            reveal: Double(reveal),
            brightness: AgentFlameWaveDrawingPolicy.cellBrightness(
                displayProgress: mirroredX,
                opacity: cell.opacity,
                tuning: tuning
            ),
            blurRadius: tuning.leadingBlur * pow(max(0, 1 - mirroredX), 1.45)
        )
    }

    private func capSize(for size: CGSize) -> CGSize {
        AgentFlameWaveDrawingPolicy.capSize(for: size)
    }

    private func resolvedCapCenterX(for size: CGSize) -> CGFloat {
        let capHalfWidth = capSize(for: size).width * 0.5
        return clamp(capCenterX, min: capHalfWidth, max: max(capHalfWidth, size.width - capHalfWidth))
    }

    private func resolvedCapCenterY(for size: CGSize) -> CGFloat {
        let capHalfHeight = capSize(for: size).height * 0.5
        return clamp(size.height * 0.5 + capCenterYOffset, min: capHalfHeight, max: max(capHalfHeight, size.height - capHalfHeight))
    }

    private func flameWaveRenderWidth(for size: CGSize, tuning: AgentFlameWaveTuning) -> CGFloat {
        let baseSide = AgentFlameWaveDrawingPolicy.cellSide(tuning: tuning)
        return max(1, (size.width + flameWaveLeadingOverscan(tuning: tuning, baseSide: baseSide)) * tuning.widthScale)
    }

    private func flameWaveLeadingOverscan(tuning: AgentFlameWaveTuning, baseSide: CGFloat) -> CGFloat {
        let safePitch = min(max(tuning.columnPitch, 3.2), 12.0)
        return max(safePitch * 3.4, baseSide * 6.0)
    }

    private func clamp(_ value: CGFloat, min lowerBound: CGFloat, max upperBound: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, lowerBound), upperBound)
    }

    private func smoothstep(edge0: CGFloat, edge1: CGFloat, x: CGFloat) -> CGFloat {
        let normalized = clamp((x - edge0) / (edge1 - edge0), min: 0, max: 1)
        return normalized * normalized * (3 - 2 * normalized)
    }

    private func color(
        for role: AgentFlameWaveColorRole,
        opacity: Double,
        brightness: CGFloat,
        tuning: AgentFlameWaveTuning
    ) -> Color {
        switch role {
        case .purple:
            let hot = min(1, max(0, brightness + CGFloat(opacity) * 0.10))
            let base = tuning.purpleColor
            let darkRed = base.red * 0.15
            let darkGreen = base.green * 0.14
            let darkBlue = base.blue * 0.30
            let hotRed = min(1, base.red * 0.95 + 0.16 * hot)
            let hotGreen = min(1, base.green * 0.95 + 0.16 * hot)
            let hotBlue = min(1, base.blue * 0.95 + 0.16 * hot)
            return Color(
                red: darkRed + (hotRed - darkRed) * hot,
                green: darkGreen + (hotGreen - darkGreen) * hot,
                blue: darkBlue + (hotBlue - darkBlue) * hot
            )
        case .white:
            let warmth = min(1, max(0, brightness))
            let base = tuning.sparkColor
            return Color(
                red: min(1, base.red * (0.70 + 0.30 * warmth) + 0.16 * warmth),
                green: min(1, base.green * (0.70 + 0.30 * warmth) + 0.16 * warmth),
                blue: min(1, base.blue * (0.70 + 0.30 * warmth) + 0.16 * warmth)
            )
        }
    }
}

struct AgentLifeGridCellFrame: Equatable {
    let alive: Bool
    let opacity: Double
    let scale: CGFloat
    let liftRatio: CGFloat
}

struct AgentLifeGridFrame: Equatable {
    static let dimension = 6
    static let cellCount = dimension * dimension
    static let generationDuration: TimeInterval = 0.16
    static let seed: UInt64 = 0xA6E3_D72C_5B91_4F0B

    let cells: [AgentLifeGridCellFrame]
    let pulse: CGFloat
    let bounce: CGFloat
    let rotationDegrees: Double

    static func make(elapsed time: TimeInterval, seed: UInt64 = seed) -> AgentLifeGridFrame {
        let safeTime = max(0, time)
        let step = Int(safeTime / generationDuration)
        let progress = CGFloat(safeTime.truncatingRemainder(dividingBy: generationDuration) / generationDuration)
        let aliveCells = cells(for: step, seed: seed)
        let renderedCells = aliveCells.enumerated().map { index, alive in
            let row = index / dimension
            let column = index % dimension
            let phase = progress + CGFloat((row + column) % 3) * 0.18
            let liftRatio = alive ? -abs(sin(phase * .pi)) * 0.20 : 0

            return AgentLifeGridCellFrame(
                alive: alive,
                opacity: alive ? 0.96 : 0.12,
                scale: alive ? 1 : 0.58,
                liftRatio: liftRatio
            )
        }

        return AgentLifeGridFrame(
            cells: renderedCells,
            pulse: 0.5 + 0.5 * sin(CGFloat(safeTime) * 4.4),
            bounce: abs(sin(CGFloat(safeTime) * 5.8)),
            rotationDegrees: (safeTime * 120).truncatingRemainder(dividingBy: 360)
        )
    }

    static func cells(for step: Int, seed: UInt64 = seed) -> [Bool] {
        let safeStep = max(0, step)
        let cycle = safeStep / 8
        let generation = safeStep % 8
        let cycleSeed = seed &+ UInt64(cycle) &* 0x9E37_79B9_7F4A_7C15
        var grid = initialGrid(seed: cycleSeed)

        guard generation > 0 else { return grid }
        for generationIndex in 0..<generation {
            let evolved = nextGeneration(grid)
            grid = evolved.contains(true)
                ? evolved
                : initialGrid(seed: cycleSeed &+ UInt64(generationIndex + 1) &* 0xD1B5_4A32_D192_ED03)
        }

        return grid
    }

    private static func initialGrid(seed: UInt64) -> [Bool] {
        (0..<cellCount).map { index in
            let value = mixed(seed &+ UInt64(index) &* 0xBF58_476D_1CE4_E5B9)
            return (value & 0xFF) < 98
        }
    }

    private static func nextGeneration(_ grid: [Bool]) -> [Bool] {
        var next = Array(repeating: false, count: cellCount)

        for row in 0..<dimension {
            for column in 0..<dimension {
                let index = row * dimension + column
                let neighbors = aliveNeighborCount(in: grid, row: row, column: column)
                next[index] = grid[index] ? (neighbors == 2 || neighbors == 3) : (neighbors == 3)
            }
        }

        return next
    }

    private static func aliveNeighborCount(in grid: [Bool], row: Int, column: Int) -> Int {
        var count = 0

        for rowDelta in -1...1 {
            for columnDelta in -1...1 where rowDelta != 0 || columnDelta != 0 {
                let wrappedRow = (row + rowDelta + dimension) % dimension
                let wrappedColumn = (column + columnDelta + dimension) % dimension
                if grid[wrappedRow * dimension + wrappedColumn] {
                    count += 1
                }
            }
        }

        return count
    }

    private static func mixed(_ value: UInt64) -> UInt64 {
        var x = value
        x = (x ^ (x >> 30)) &* 0xBF58_476D_1CE4_E5B9
        x = (x ^ (x >> 27)) &* 0x94D0_49BB_1331_11EB
        return x ^ (x >> 31)
    }
}

final class AgentLifeGridFrameClock: ObservableObject {
    static let shared = AgentLifeGridFrameClock()

    @Published private(set) var frame = AgentLifeGridFrame.make(elapsed: 0)

    private let queue = DispatchQueue(label: "com.notchpaste.agent-life-grid.animation", qos: .userInteractive)
    private var timer: DispatchSourceTimer?
    private var observerCount = 0
    private var generation = 0

    private init() {}

    func retain() {
        observerCount += 1
        guard timer == nil else { return }
        startTimer()
    }

    func release() {
        observerCount = max(0, observerCount - 1)
        guard observerCount == 0 else { return }

        generation += 1
        timer?.setEventHandler {}
        timer?.cancel()
        timer = nil
    }

    private func startTimer() {
        generation += 1
        let timerGeneration = generation
        let framesPerSecond = AgentAnimationFrameRatePolicy.preferredFramesPerSecond
        let nanosecondsPerFrame = max(1, 1_000_000_000 / framesPerSecond)
        let startedAt = CACurrentMediaTime()
        frame = AgentLifeGridFrame.make(elapsed: 0)

        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(
            deadline: .now(),
            repeating: .nanoseconds(nanosecondsPerFrame),
            leeway: framesPerSecond >= AgentAnimationFrameRatePolicy.maximumFramesPerSecond ? .nanoseconds(0) : .milliseconds(1)
        )
        source.setEventHandler { [weak self] in
            let frame = AgentLifeGridFrame.make(elapsed: CACurrentMediaTime() - startedAt)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == timerGeneration, self.timer != nil else { return }
                self.frame = frame
            }
        }
        timer = source
        source.resume()
    }

    deinit {
        timer?.setEventHandler {}
        timer?.cancel()
    }
}

struct AgentLifeGridIcon: View {
    static let dimension = AgentLifeGridFrame.dimension
    static let cellCount = AgentLifeGridFrame.cellCount

    let color: Color
    let effect: AgentActivityIconEffect

    @ObservedObject private var frameClock = AgentLifeGridFrameClock.shared

    init(color: Color, effect: AgentActivityIconEffect = .none) {
        self.color = color
        self.effect = effect
    }

    var body: some View {
        let frame = frameClock.frame

        Canvas(opaque: false, colorMode: .linear, rendersAsynchronously: true) { context, size in
            if effect == .edgeBloom {
                drawCells(frame: frame, in: &context, size: size, opacityMultiplier: 0.28, scaleMultiplier: 1.28)
                drawCells(frame: frame, in: &context, size: size, opacityMultiplier: 0.24, scaleMultiplier: 1.12)
            }
            drawCells(frame: frame, in: &context, size: size)
        }
        .aspectRatio(1, contentMode: .fit)
        .scaleEffect(effect == .breathe ? 0.9 + frame.pulse * 0.18 : 1)
        .rotationEffect(.degrees(effect == .spin ? frame.rotationDegrees : 0))
        .offset(y: effect == .bounce ? -frame.bounce * 4 : 0)
        .opacity(effect == .breathe ? 0.68 + frame.pulse * 0.32 : 1)
        .shadow(
            color: color.opacity(effect == .glow ? 0.28 + frame.pulse * 0.45 : 0),
            radius: effect == .glow ? 3 + frame.pulse * 5 : 0,
            x: 0,
            y: 0
        )
        .overlay {
            if effect == .glow {
                GeometryReader { proxy in
                    let side = min(proxy.size.width, proxy.size.height)
                    Circle()
                        .stroke(color.opacity(0.10 + frame.pulse * 0.24), lineWidth: 1)
                        .frame(width: side + 4 + frame.pulse * 5, height: side + 4 + frame.pulse * 5)
                        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                        .allowsHitTesting(false)
                }
            }
        }
        .onAppear { frameClock.retain() }
        .onDisappear { frameClock.release() }
    }

    static func cells(for step: Int, seed: UInt64 = AgentLifeGridFrame.seed) -> [Bool] {
        AgentLifeGridFrame.cells(for: step, seed: seed)
    }

    private func drawCells(
        frame: AgentLifeGridFrame,
        in context: inout GraphicsContext,
        size: CGSize,
        opacityMultiplier: Double = 1,
        scaleMultiplier: CGFloat = 1
    ) {
        let side = min(size.width, size.height)
        let gap = max(1, side * 0.055)
        let cellSide = max(1, (side - gap * CGFloat(Self.dimension - 1)) / CGFloat(Self.dimension))
        let xInset = (size.width - side) / 2
        let yInset = (size.height - side) / 2

        for index in frame.cells.indices {
            let cell = frame.cells[index]
            let row = index / Self.dimension
            let column = index % Self.dimension
            let scaledSide = cellSide * cell.scale * scaleMultiplier
            let baseX = xInset + CGFloat(column) * (cellSide + gap)
            let baseY = yInset + CGFloat(row) * (cellSide + gap) + cell.liftRatio * cellSide
            let rect = CGRect(
                x: baseX + (cellSide - scaledSide) / 2,
                y: baseY + (cellSide - scaledSide) / 2,
                width: scaledSide,
                height: scaledSide
            )

            context.fill(
                Path(rect),
                with: .color(color.opacity(cell.opacity * opacityMultiplier))
            )
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

struct AgentASCIIActivityIcon: View {
    let style: AgentActivityIconStyle
    let color: Color

    var body: some View {
        TimelineView(AgentAnimationFrameRatePolicy.decorativeTimelineSchedule) { timeline in
            let frames = style.asciiFrames.isEmpty ? [">_"] : style.asciiFrames
            let time = timeline.date.timeIntervalSinceReferenceDate
            let index = Int(time * 8.0) % frames.count
            let pulse = 0.5 + 0.5 * sin(CGFloat(time) * 9.5)

            Text(frames[index])
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundStyle(color.opacity(0.72 + pulse * 0.28))
                .minimumScaleFactor(0.48)
                .lineLimit(1)
                .shadow(color: color.opacity(0.24 + pulse * 0.34), radius: 2 + pulse * 3)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityLabel(Text(style.title))
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

private struct NotchApprovalActionButtonStyle: ButtonStyle {
    let action: VibeApprovalAction

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(action.foregroundColor)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(configuration.isPressed ? action.pressedBackgroundColor : action.backgroundColor)
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
