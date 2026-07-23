import SwiftUI
import AppKit
import ServiceManagement
import UniformTypeIdentifiers

/// 设置面板视图。风格参考 farouqaldori/vibe-notch (Apache 2.0)：
/// 黑色背景上的 row 列表，hover 高亮，每行 icon + 中文标签 + 状态/按钮。
struct NotchSettingsView: View {
    @ObservedObject var viewModel: NotchViewModel
    @ObservedObject private var prefs = PreferencesStore.shared
    @Binding var adjustingNotchPreviewTarget: AgentNotchSizeAdjustmentTarget?
    let onRequestPermission: () -> Void
    let onQuit: () -> Void

    @State private var launchAtLogin: Bool = false
    @State private var accessibilityEnabled: Bool = false
    @State private var refreshTick = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 4) {
                NotchMenuRow(icon: "chevron.left", label: "返回") {
                    viewModel.contentType = .list
                }

                divider

                // 行为设置
                NotchMenuToggleRow(
                    icon: "hand.point.up.left",
                    label: "鼠标悬停展开",
                    isOn: prefs.hoverToExpand
                ) {
                    prefs.hoverToExpand.toggle()
                }

                NotchMenuToggleRow(
                    icon: "rectangle.portrait.and.arrow.right",
                    label: "复制后关闭面板",
                    isOn: prefs.closeAfterCopy
                ) {
                    prefs.closeAfterCopy.toggle()
                }

                NotchMenuToggleRow(
                    icon: "command",
                    label: "复制后自动粘贴",
                    isOn: prefs.autoPasteEnabled
                ) {
                    prefs.autoPasteEnabled.toggle()
                }

                NotchMenuToggleRow(
                    icon: "eye.slash",
                    label: "隐私模式（暂停剪贴板监听）",
                    isOn: !prefs.monitoringEnabled
                ) {
                    prefs.monitoringEnabled.toggle()
                }

                divider

                AgentActivityIconSettingsRow(
                    prefs: prefs,
                    adjustingNotchPreviewTarget: $adjustingNotchPreviewTarget
                )

                divider

                // 快捷键
                ShortcutPickerRow(prefs: prefs)

                divider

                // 系统集成
                NotchMenuToggleRow(
                    icon: "menubar.rectangle",
                    label: "显示菜单栏图标",
                    isOn: prefs.showMenuBarIcon
                ) {
                    prefs.showMenuBarIcon.toggle()
                }

                NotchMenuToggleRow(
                    icon: "power",
                    label: "登录时启动",
                    isOn: launchAtLogin
                ) {
                    toggleLaunchAtLogin()
                }

                NotchAccessibilityRow(
                    isEnabled: accessibilityEnabled,
                    refreshTick: refreshTick,
                    onEnable: onRequestPermission
                )

                divider

                // 关于
                NotchVersionDebugTriggerRow(version: appVersionString) {
                    NotchDebugToolsWindowController.shared.show(viewModel: viewModel)
                }

                NotchMenuRow(icon: "star", label: "在 GitHub 标星") {
                    if let url = URL(string: "https://github.com/anthropics/notchpaste") {
                        NSWorkspace.shared.open(url)
                    }
                }

                divider

                NotchMenuRow(icon: "xmark.circle", label: "退出 NotchPaste", isDestructive: true) {
                    onQuit()
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
        .scrollDisabled(adjustingNotchPreviewTarget != nil)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { refreshState() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshState()
        }
    }

    // MARK: - Helpers

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(height: 1)
            .padding(.vertical, 4)
    }

    private var appVersionString: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "v\(v) (\(b))"
    }

    private func refreshState() {
        accessibilityEnabled = AXIsProcessTrusted()
        launchAtLogin = SMAppService.mainApp.status == .enabled
        refreshTick.toggle()
    }

    private func toggleLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
            refreshState()
        } catch {
            AppLogger.app.error("Failed to toggle launch at login: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - Reusable rows（保持原签名兼容旧调用）

struct NotchMenuRow: View {
    let icon: String
    let label: String
    var trailing: String? = nil
    var isDestructive: Bool = false
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(textColor)
                    .frame(width: 16)
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(textColor)
                Spacer()
                if let trailing {
                    Text(trailing)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(hovered ? Color.white.opacity(0.08) : .clear)
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
    }

    private var textColor: Color {
        if isDestructive { return Color(red: 1.0, green: 0.4, blue: 0.4) }
        return .white.opacity(hovered ? 1.0 : 0.75)
    }
}

private struct NotchVersionDebugTriggerRow: View {
    let version: String
    let onUnlock: () -> Void

    @State private var hovered = false
    @State private var tapCounter = DebugUnlockTapCounter(resetInterval: 3)

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle")
                .font(.system(size: 12))
                .foregroundColor(textColor)
                .frame(width: 16)
            Text("版本信息")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(textColor)
            Spacer()
            Text(version)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.4))
                .padding(.vertical, 5)
                .padding(.leading, 14)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(hovered ? Color.white.opacity(0.08) : .clear)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: registerTap)
        .onHover { hovered = $0 }
    }

    private var textColor: Color {
        .white.opacity(hovered ? 1.0 : 0.75)
    }

    private func registerTap() {
        if tapCounter.registerTap(at: Date().timeIntervalSinceReferenceDate) {
            onUnlock()
        }
    }
}

struct DebugUnlockTapCounter: Equatable {
    static let requiredTapCount = 5

    let resetInterval: TimeInterval
    private(set) var tapCount = 0
    private var lastTapTime: TimeInterval?

    init(resetInterval: TimeInterval) {
        self.resetInterval = resetInterval
    }

    mutating func registerTap(at timestamp: TimeInterval) -> Bool {
        if let lastTapTime, timestamp - lastTapTime > resetInterval {
            tapCount = 0
        }

        lastTapTime = timestamp
        tapCount += 1

        guard tapCount >= Self.requiredTapCount else { return false }
        tapCount = 0
        return true
    }
}

struct NotchMenuToggleRow: View {
    let icon: String
    let label: String
    let isOn: Bool
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(textColor)
                    .frame(width: 16)
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(textColor)
                Spacer()
                Circle()
                    .fill(isOn ? Color(red: 0.4, green: 0.85, blue: 0.5) : Color.white.opacity(0.3))
                    .frame(width: 6, height: 6)
                Text(isOn ? "已开启" : "已关闭")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
                    .frame(minWidth: 36, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(hovered ? Color.white.opacity(0.08) : .clear)
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
    }

    private var textColor: Color {
        .white.opacity(hovered ? 1.0 : 0.75)
    }
}

struct AgentActivityIconSettingsRow: View {
    @ObservedObject var prefs: PreferencesStore
    @Binding var adjustingNotchPreviewTarget: AgentNotchSizeAdjustmentTarget?

    @State private var isExpanded = false
    @State private var hovered = false

    private let columns = [
        GridItem(.adaptive(minimum: 72), spacing: 6)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                toggleExpanded()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12))
                        .foregroundColor(textColor)
                        .frame(width: 16)
                    Text("Agent 状态图标")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(textColor)
                    Spacer()
                    Text("\(prefs.agentActivityNotchDisplayMode.title) · \(prefs.agentRunningIconStyle.title)")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.42))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.white.opacity(0.4))
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(hovered ? Color.white.opacity(0.08) : .clear)
                )
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .onHover { hovered = $0 }

            if isExpanded {
                expandedContent
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            AgentSettingsDeferredPlaceholder {
                openIconSettingsWindow()
            }
        }
        .padding(.leading, 30)
        .padding(.trailing, 12)
        .padding(.bottom, 8)
    }

    private var heavyExpandedContent: some View {
        AgentActivityIconControlsView(
            prefs: prefs,
            adjustingNotchPreviewTarget: $adjustingNotchPreviewTarget
        )
    }

    private func toggleExpanded() {
        if isExpanded {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                isExpanded = false
            }
            return
        }

        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
            isExpanded = true
        }

    }

    private func openIconSettingsWindow() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 80_000_000)
            AgentIconSettingsWindowController.shared.show()
        }
    }

    private func optionGroup<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.36))
            content()
        }
    }

    private func notchSizeStateGroup(
        title: String,
        systemImageName: String,
        isAttention: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: systemImageName)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(isAttention ? .orange.opacity(0.9) : .cyan.opacity(0.9))
                    .frame(width: 12)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.62))
            }

            notchSizeModeRows(
                title: "详细",
                target: AgentNotchSizeAdjustmentTarget(isAttention: isAttention, mode: .detailed),
                width: isAttention ? $prefs.agentAttentionNotchWidthAdjustment : $prefs.agentRunningNotchWidthAdjustment,
                height: isAttention ? $prefs.agentAttentionNotchHeightAdjustment : $prefs.agentRunningNotchHeightAdjustment
            )

            notchSizeModeRows(
                title: "简约",
                target: AgentNotchSizeAdjustmentTarget(isAttention: isAttention, mode: .simple),
                width: isAttention ? $prefs.agentAttentionSimpleNotchWidthAdjustment : $prefs.agentRunningSimpleNotchWidthAdjustment,
                height: isAttention ? $prefs.agentAttentionSimpleNotchHeightAdjustment : $prefs.agentRunningSimpleNotchHeightAdjustment
            )
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(0.035))
        )
    }

    private func notchSizeModeRows(
        title: String,
        target: AgentNotchSizeAdjustmentTarget,
        width: Binding<Double>,
        height: Binding<Double>
    ) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.44))
                    .frame(width: 36, alignment: .leading)

                Rectangle()
                    .fill(Color.white.opacity(0.09))
                    .frame(height: 1)
            }

            PixelAdjustmentRow(
                title: "左右宽",
                value: width,
                range: -180...360,
                unit: "pt",
                onEditingChanged: { updatePreviewTarget(target, isEditing: $0) }
            )
            PixelAdjustmentRow(
                title: "高度",
                value: height,
                range: -6...32,
                unit: "pt",
                onEditingChanged: { updatePreviewTarget(target, isEditing: $0) }
            )
        }
    }

    private func updatePreviewTarget(_ target: AgentNotchSizeAdjustmentTarget, isEditing: Bool) {
        adjustingNotchPreviewTarget = isEditing ? target : nil
    }

    private var textColor: Color {
        .white.opacity(hovered ? 1.0 : 0.75)
    }
}

private final class AgentIconSettingsWindowController {
    static let shared = AgentIconSettingsWindowController()

    private var window: NSWindow?
    private var closeObserver: NSObjectProtocol?

    private init() {}

    func show() {
        if Thread.isMainThread {
            showOnMainThread()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.showOnMainThread()
            }
        }
    }

    private func showOnMainThread() {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let hostingController = NSHostingController(rootView: AgentIconSettingsPanelView())
        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = "Agent 图标设置"
        newWindow.contentMinSize = NSSize(width: 680, height: 520)
        newWindow.isReleasedWhenClosed = false
        newWindow.contentViewController = hostingController
        newWindow.center()

        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: newWindow,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            if let closeObserver = self.closeObserver {
                NotificationCenter.default.removeObserver(closeObserver)
            }
            self.closeObserver = nil
            self.window = nil
        }

        window = newWindow
        NSApp.activate(ignoringOtherApps: true)
        newWindow.makeKeyAndOrderFront(nil)
    }
}

private struct AgentIconSettingsPanelView: View {
    @ObservedObject private var prefs = PreferencesStore.shared
    @State private var adjustingNotchPreviewTarget: AgentNotchSizeAdjustmentTarget?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.cyan)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Agent 图标设置")
                        .font(.system(size: 16, weight: .semibold))
                    Text("完整控件放在独立窗口，避免 notch 设置面板卡顿")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.42))
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()
                .overlay(Color.white.opacity(0.08))

            ScrollView(.vertical) {
                AgentActivityIconControlsView(
                    prefs: prefs,
                    adjustingNotchPreviewTarget: $adjustingNotchPreviewTarget
                )
                .padding(22)
            }
        }
        .foregroundColor(.white)
        .background(Color.black.opacity(0.94))
        .frame(minWidth: 680, minHeight: 520)
    }
}

private struct AgentActivityIconControlsView: View {
    @ObservedObject var prefs: PreferencesStore
    @Binding var adjustingNotchPreviewTarget: AgentNotchSizeAdjustmentTarget?

    private let columns = [
        GridItem(.adaptive(minimum: 84), spacing: 8)
    ]

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 14) {
            optionGroup(title: "刘海状态模式") {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                    ForEach(AgentActivityNotchDisplayMode.allCases) { mode in
                        AgentNotchDisplayModeOptionButton(
                            mode: mode,
                            isSelected: prefs.agentActivityNotchDisplayMode == mode
                        ) {
                            prefs.agentActivityNotchDisplayMode = mode
                        }
                    }
                }
            }

            optionGroup(title: "运行中") {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                    ForEach(AgentActivityIconStyle.allCases) { style in
                        AgentIconStyleOptionButton(
                            style: style,
                            isSelected: prefs.agentRunningIconStyle == style
                        ) {
                            prefs.agentRunningIconStyle = style
                        }
                    }
                }

                CustomIconPickerRow(
                    title: "自定义",
                    path: $prefs.agentRunningCustomIconPath
                )
            }

            optionGroup(title: "待处理") {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                    ForEach(AgentActivityIconStyle.allCases) { style in
                        AgentIconStyleOptionButton(
                            style: style,
                            isSelected: prefs.agentAttentionIconStyle == style
                        ) {
                            prefs.agentAttentionIconStyle = style
                        }
                    }
                }

                CustomIconPickerRow(
                    title: "自定义",
                    path: $prefs.agentAttentionCustomIconPath
                )
            }

            optionGroup(title: "位置") {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                    ForEach(AgentActivityIconPosition.allCases) { position in
                        AgentIconPositionOptionButton(
                            position: position,
                            isSelected: prefs.agentActivityIconPosition == position
                        ) {
                            prefs.agentActivityIconPosition = position
                        }
                    }
                }
            }

            optionGroup(title: "动效") {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                    ForEach(AgentActivityIconEffect.allCases) { effect in
                        AgentIconEffectOptionButton(
                            effect: effect,
                            isSelected: prefs.agentActivityIconEffect == effect
                        ) {
                            prefs.agentActivityIconEffect = effect
                        }
                    }
                }
            }

            optionGroup(title: "图标颜色") {
                VStack(spacing: 9) {
                    FlameWaveDebugColorRow(
                        title: "运行中",
                        color: runningIconColor,
                        detail: "closed 刘海中运行状态图标颜色。"
                    )
                    FlameWaveDebugColorRow(
                        title: "待处理",
                        color: attentionIconColor,
                        detail: "批准、询问、跳回等待处理状态图标颜色。"
                    )
                }
            }

            optionGroup(title: "图标像素微调") {
                VStack(spacing: 8) {
                    PixelAdjustmentRow(
                        title: "尺寸",
                        value: $prefs.agentActivityIconSize,
                        range: 8...40,
                        unit: "pt"
                    )
                    PixelAdjustmentRow(
                        title: "X",
                        value: $prefs.agentActivityIconOffsetX,
                        range: -80...80,
                        unit: "pt"
                    )
                    PixelAdjustmentRow(
                        title: "Y",
                        value: $prefs.agentActivityIconOffsetY,
                        range: -32...32,
                        unit: "pt"
                    )
                }
            }

            optionGroup(title: "刘海尺寸微调") {
                VStack(spacing: 10) {
                    notchSizeStateGroup(
                        title: "运行中",
                        systemImageName: "play.fill",
                        isAttention: false
                    )
                    notchSizeStateGroup(
                        title: "待处理",
                        systemImageName: "exclamationmark.bubble.fill",
                        isAttention: true
                    )
                }
            }
        }
    }

    private func optionGroup<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.42))
            content()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }

    private func notchSizeStateGroup(
        title: String,
        systemImageName: String,
        isAttention: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: systemImageName)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(isAttention ? .orange.opacity(0.9) : .cyan.opacity(0.9))
                    .frame(width: 12)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.62))
            }

            notchSizeModeRows(
                title: "详细",
                target: AgentNotchSizeAdjustmentTarget(isAttention: isAttention, mode: .detailed),
                width: isAttention ? $prefs.agentAttentionNotchWidthAdjustment : $prefs.agentRunningNotchWidthAdjustment,
                height: isAttention ? $prefs.agentAttentionNotchHeightAdjustment : $prefs.agentRunningNotchHeightAdjustment
            )

            notchSizeModeRows(
                title: "简约",
                target: AgentNotchSizeAdjustmentTarget(isAttention: isAttention, mode: .simple),
                width: isAttention ? $prefs.agentAttentionSimpleNotchWidthAdjustment : $prefs.agentRunningSimpleNotchWidthAdjustment,
                height: isAttention ? $prefs.agentAttentionSimpleNotchHeightAdjustment : $prefs.agentRunningSimpleNotchHeightAdjustment
            )
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(0.035))
        )
    }

    private func notchSizeModeRows(
        title: String,
        target: AgentNotchSizeAdjustmentTarget,
        width: Binding<Double>,
        height: Binding<Double>
    ) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.44))
                    .frame(width: 36, alignment: .leading)

                Rectangle()
                    .fill(Color.white.opacity(0.09))
                    .frame(height: 1)
            }

            PixelAdjustmentRow(
                title: "左右宽",
                value: width,
                range: -180...360,
                unit: "pt",
                onEditingChanged: { updatePreviewTarget(target, isEditing: $0) }
            )
            PixelAdjustmentRow(
                title: "高度",
                value: height,
                range: -6...32,
                unit: "pt",
                onEditingChanged: { updatePreviewTarget(target, isEditing: $0) }
            )
        }
    }

    private func updatePreviewTarget(_ target: AgentNotchSizeAdjustmentTarget, isEditing: Bool) {
        adjustingNotchPreviewTarget = isEditing ? target : nil
    }

    private var runningIconColor: Binding<Color> {
        Binding(
            get: {
                Color(
                    red: prefs.agentRunningIconRed,
                    green: prefs.agentRunningIconGreen,
                    blue: prefs.agentRunningIconBlue
                )
            },
            set: { newColor in
                guard let rgb = NSColor(newColor).usingColorSpace(.sRGB) else { return }
                prefs.agentRunningIconRed = Double(rgb.redComponent)
                prefs.agentRunningIconGreen = Double(rgb.greenComponent)
                prefs.agentRunningIconBlue = Double(rgb.blueComponent)
            }
        )
    }

    private var attentionIconColor: Binding<Color> {
        Binding(
            get: {
                Color(
                    red: prefs.agentAttentionIconRed,
                    green: prefs.agentAttentionIconGreen,
                    blue: prefs.agentAttentionIconBlue
                )
            },
            set: { newColor in
                guard let rgb = NSColor(newColor).usingColorSpace(.sRGB) else { return }
                prefs.agentAttentionIconRed = Double(rgb.redComponent)
                prefs.agentAttentionIconGreen = Double(rgb.greenComponent)
                prefs.agentAttentionIconBlue = Double(rgb.blueComponent)
            }
        )
    }
}

private struct CustomIconPickerRow: View {
    private static let previewCache = NSCache<NSString, NSImage>()

    let title: String
    @Binding var path: String?

    @State private var hovered = false
    @State private var previewImage: NSImage?
    @State private var previewPath: String?

    var body: some View {
        HStack(spacing: 8) {
            preview

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.62))
                Text(fileName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.36))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            Button(path == nil ? "选择" : "更换") {
                chooseIcon()
            }
            .buttonStyle(.plain)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.black)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.9)))

            if path != nil {
                Button("清除") {
                    path = nil
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.68))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08)))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(hovered ? Color.white.opacity(0.07) : Color.white.opacity(0.035))
        )
        .onHover { hovered = $0 }
        .task(id: path ?? "") {
            await loadPreview(for: path)
        }
    }

    @ViewBuilder
    private var preview: some View {
        if let path, previewPath == path, let image = previewImage {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 20, height: 20)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        } else {
            Image(systemName: "photo.badge.plus")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.cyan.opacity(0.85))
                .frame(width: 20, height: 20)
        }
    }

    private func loadPreview(for path: String?) async {
        guard let path, !path.isEmpty else {
            await MainActor.run {
                previewImage = nil
                previewPath = nil
            }
            return
        }

        let key = path as NSString
        if let image = Self.previewCache.object(forKey: key) {
            setPreviewImage(image, for: path)
            return
        }

        let imageData = await Task.detached(priority: .utility) {
            try? Data(contentsOf: URL(fileURLWithPath: path), options: [.mappedIfSafe])
        }.value
        let image = imageData.flatMap(NSImage.init(data:))

        if let image {
            Self.previewCache.setObject(image, forKey: key)
        }
        setPreviewImage(image, for: path)
    }

    private func setPreviewImage(_ image: NSImage?, for loadedPath: String) {
        guard path == loadedPath else {
            return
        }
        previewImage = image
        previewPath = image == nil ? nil : loadedPath
    }

    private var fileName: String {
        guard let path else { return "未选择文件" }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    private func chooseIcon() {
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.png, .jpeg, .gif, .tiff, .svg, .icns, .webP]
        panel.prompt = "选择"
        panel.title = "选择图标文件"
        panel.level = .modalPanel
        panel.makeKeyAndOrderFront(nil)

        if panel.runModal() == .OK, let url = panel.url {
            path = url.path
        }
    }
}

private struct PixelAdjustmentRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let unit: String
    var onEditingChanged: (Bool) -> Void = { _ in }

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.58))
                .frame(width: 44, alignment: .leading)

            Slider(
                value: pixelValue,
                in: range,
                step: 1,
                onEditingChanged: onEditingChanged
            )
                .controlSize(.small)
                .tint(.cyan)

            TextField("", value: pixelValue, format: .number.precision(.fractionLength(0)))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.78))
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.plain)
                .padding(.horizontal, 5)
                .frame(width: 52)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )

            Text(unit)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.white.opacity(0.36))
                .frame(width: 16, alignment: .leading)

            Stepper(value: pixelValue, in: range, step: 1) {
                EmptyView()
            }
            .labelsHidden()
            .frame(width: 36)
        }
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private var pixelValue: Binding<Double> {
        Binding(
            get: { value },
            set: { value = min(max($0.rounded(), range.lowerBound), range.upperBound) }
        )
    }
}

private final class AgentFlameWaveDebugWindowController {
    static let shared = AgentFlameWaveDebugWindowController()

    private var window: NSWindow?
    private var closeObserver: NSObjectProtocol?

    private init() {}

    func show() {
        if Thread.isMainThread {
            showOnMainThread()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.showOnMainThread()
            }
        }
    }

    private func showOnMainThread() {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let hostingController = NSHostingController(rootView: AgentFlameWaveDebugPanelView())
        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = "火焰波 Debug"
        newWindow.contentMinSize = NSSize(width: 640, height: 460)
        newWindow.isReleasedWhenClosed = false
        newWindow.contentViewController = hostingController
        newWindow.center()

        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: newWindow,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            if let closeObserver = self.closeObserver {
                NotificationCenter.default.removeObserver(closeObserver)
            }
            self.closeObserver = nil
            self.window = nil
        }

        window = newWindow
        NSApp.activate(ignoringOtherApps: true)
        newWindow.makeKeyAndOrderFront(nil)
    }
}

private final class NotchDebugToolsWindowController {
    static let shared = NotchDebugToolsWindowController()

    private var window: NSWindow?
    private var closeObserver: NSObjectProtocol?

    private init() {}

    func show(viewModel: NotchViewModel) {
        if Thread.isMainThread {
            showOnMainThread(viewModel: viewModel)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.showOnMainThread(viewModel: viewModel)
            }
        }
    }

    private func showOnMainThread(viewModel: NotchViewModel) {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let hostingController = NSHostingController(rootView: NotchDebugToolsPanelView(viewModel: viewModel))
        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 250),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = "Debug 工具"
        newWindow.contentMinSize = NSSize(width: 380, height: 220)
        newWindow.isReleasedWhenClosed = false
        newWindow.contentViewController = hostingController
        newWindow.center()

        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: newWindow,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            if let closeObserver = self.closeObserver {
                NotificationCenter.default.removeObserver(closeObserver)
            }
            self.closeObserver = nil
            self.window = nil
        }

        window = newWindow
        NSApp.activate(ignoringOtherApps: true)
        newWindow.makeKeyAndOrderFront(nil)
    }
}

private struct NotchDebugToolsPanelView: View {
    @ObservedObject var viewModel: NotchViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.cyan)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Debug 工具")
                        .font(.system(size: 16, weight: .semibold))
                    Text("从版本号 5 连击进入；普通设置不显示这些入口。")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.42))
                }
            }

            VStack(spacing: 8) {
                DebugToolButton(
                    icon: "slider.horizontal.3",
                    title: "火焰波 Debug 调参",
                    subtitle: "粒子、颜色、文字位置、扩散速度等参数"
                ) {
                    AgentFlameWaveDebugWindowController.shared.show()
                }

                DebugToolButton(
                    icon: "square.stack.3d.up",
                    title: "Notch UI 层级",
                    subtitle: "查看层级树、点击高亮、右键临时调整布局"
                ) {
                    NotchUIHierarchyDebugWindowController.shared.show(viewModel: viewModel)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .foregroundColor(.white)
        .background(Color.black.opacity(0.94))
        .frame(minWidth: 380, minHeight: 220)
    }
}

private struct DebugToolButton: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.cyan.opacity(hovered ? 1 : 0.78))
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(hovered ? 0.96 : 0.78))
                    Text(subtitle)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(hovered ? 0.48 : 0.34))
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(hovered ? 0.5 : 0.28))
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.white.opacity(hovered ? 0.08 : 0.045))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

private final class NotchUIHierarchyDebugWindowController {
    static let shared = NotchUIHierarchyDebugWindowController()

    private var window: NSWindow?
    private var closeObserver: NSObjectProtocol?

    private init() {}

    func show(viewModel: NotchViewModel) {
        if Thread.isMainThread {
            showOnMainThread(viewModel: viewModel)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.showOnMainThread(viewModel: viewModel)
            }
        }
    }

    private func showOnMainThread(viewModel: NotchViewModel) {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let hostingController = NSHostingController(rootView: NotchUIHierarchyDebugPanelView(viewModel: viewModel))
        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = "Notch UI 层级"
        newWindow.contentMinSize = NSSize(width: 620, height: 460)
        newWindow.isReleasedWhenClosed = false
        newWindow.contentViewController = hostingController
        newWindow.center()

        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: newWindow,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            if let closeObserver = self.closeObserver {
                NotificationCenter.default.removeObserver(closeObserver)
            }
            self.closeObserver = nil
            self.window = nil
        }

        window = newWindow
        NSApp.activate(ignoringOtherApps: true)
        newWindow.makeKeyAndOrderFront(nil)
    }
}

private struct NotchUIHierarchyNode: Identifiable {
    let id: String
    let title: String
    let badge: String?
    let detail: String
    let color: Color
    let children: [NotchUIHierarchyNode]

    init(
        _ id: String,
        title: String,
        badge: String? = nil,
        detail: String = "",
        color: Color = .white.opacity(0.72),
        children: [NotchUIHierarchyNode] = []
    ) {
        self.id = id
        self.title = title
        self.badge = badge
        self.detail = detail
        self.color = color
        self.children = children
    }
}

private struct NotchUIHierarchyDebugPanelView: View {
    @ObservedObject var viewModel: NotchViewModel
    @ObservedObject private var prefs = PreferencesStore.shared
    @ObservedObject private var vibeStore = VibeAgentStore.shared

    var body: some View {
        VStack(spacing: 0) {
            hierarchyHeader

            Divider()
                .overlay(Color.white.opacity(0.08))

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 16) {
                    stateGrid
                    hierarchyTree
                    legend
                }
                .padding(22)
            }
        }
        .foregroundColor(.white)
        .background(Color.black.opacity(0.94))
        .frame(minWidth: 620, minHeight: 460)
        .onDisappear {
            clearHierarchyDebugState()
        }
    }

    private var hierarchyHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.cyan)
            VStack(alignment: .leading, spacing: 2) {
                Text("Notch UI 层级")
                    .font(.system(size: 16, weight: .semibold))
                Text("左键高亮对应边缘；右键打开临时大小/位置调整")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.42))
            }
            Spacer()
            if viewModel.highlightedHierarchyNodeID != nil {
                Button("清除高亮") {
                    clearHierarchyDebugState()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.cyan.opacity(0.86))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.cyan.opacity(0.10))
                )
            }
            Text(statusBadge)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.black)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule(style: .continuous)
                        .fill(viewModel.status == .opened ? Color.cyan.opacity(0.92) : Color.white.opacity(0.88))
                )
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var stateGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 10) {
            NotchHierarchyMetricCard(title: "status", value: statusText, tint: viewModel.status == .opened ? .cyan : .white)
            NotchHierarchyMetricCard(title: "content", value: contentTypeText, tint: contentTint)
            NotchHierarchyMetricCard(title: "copyHint", value: copyHintText, tint: copyHintTint)
            NotchHierarchyMetricCard(title: "agent", value: agentText, tint: agentTint)
            NotchHierarchyMetricCard(title: "device notch", value: sizeText(viewModel.deviceNotchRect.size), tint: .white.opacity(0.72))
            NotchHierarchyMetricCard(title: "opened size", value: sizeText(viewModel.openedSize), tint: .white.opacity(0.72))
        }
    }

    private var hierarchyTree: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("层级树")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.68))

            VStack(alignment: .leading, spacing: 3) {
                ForEach(hierarchyNodes) { node in
                    NotchHierarchyNodeRow(
                        node: node,
                        depth: 0,
                        selectedID: $viewModel.highlightedHierarchyNodeID,
                        adjustmentPanelNodeID: $viewModel.hierarchyDebugAdjustmentPanelNodeID
                    )
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.045))
            )

            if
                let nodeID = viewModel.hierarchyDebugAdjustmentPanelNodeID,
                let node = hierarchyNode(for: nodeID)
            {
                NotchHierarchyAdjustmentPanel(
                    node: node,
                    adjustment: hierarchyAdjustmentBinding(for: nodeID),
                    onReset: { resetHierarchyAdjustment(for: nodeID) },
                    onClose: { viewModel.hierarchyDebugAdjustmentPanelNodeID = nil }
                )
            }
        }
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("说明")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.68))
            Text("左键节点会把节点 id 写入 NotchViewModel.debug 状态，并在主 Notch UI 对应层绘制 cyan/orange/purple 描边。右键节点打开临时调整面板：宽/高会改变对应层的真实 SwiftUI 布局，X/Y 是临时 offset；所有值只保存在内存中，关闭窗口或清除高亮后恢复。子控件不是独立布局层时，会高亮最近的父区域。")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.44))
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(3)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.035))
        )
    }

    private var hierarchyNodes: [NotchUIHierarchyNode] {
        [
            NotchUIHierarchyNode(
                "appkit-window",
                title: "NotchWindowController / NSWindow",
                badge: "AppKit",
                detail: "顶部 borderless 刘海窗口，承载 SwiftUI NotchView。",
                color: .white.opacity(0.78),
                children: [
                    NotchUIHierarchyNode(
                        "root-notch-view",
                        title: "NotchView.body",
                        badge: "SwiftUI",
                        detail: "根 ZStack(alignment: .top)，负责 notchContainer 和调试预览叠放。",
                        color: .cyan.opacity(0.9),
                        children: rootChildren
                    )
                ]
            )
        ]
    }

    private var rootChildren: [NotchUIHierarchyNode] {
        [
            NotchUIHierarchyNode(
                "notch-container",
                title: "notchContainer",
                badge: "z 0",
                detail: "frame -> padding -> black background -> clipShape(NotchShape) -> top 1px overlay -> shadow。",
                color: .cyan.opacity(0.78),
                children: [
                    NotchUIHierarchyNode(
                        "notch-inner",
                        title: "notchInner",
                        detail: "VStack: headerRow 固定在顶部；opened 时下方挂 contentView。",
                        children: notchInnerChildren
                    ),
                    NotchUIHierarchyNode(
                        "notch-shape",
                        title: "clipShape(NotchShape)",
                        detail: "最终裁剪边界；closed/opened 通过 top/bottom corner radius 变形。",
                        color: .orange.opacity(0.85)
                    ),
                    NotchUIHierarchyNode(
                        "top-seam-overlay",
                        title: "top 1px black overlay",
                        detail: "修补 clip 顶部抗锯齿细缝。"
                    )
                ]
            ),
            NotchUIHierarchyNode(
                "width-adjustment-preview",
                title: "notchWidthAdjustmentTopPreview",
                badge: "z 20",
                detail: "仅设置页拖动刘海宽高时出现；显示顶部 1:1 预览和黄色极限线。",
                color: .yellow.opacity(0.9)
            )
        ]
    }

    private var notchInnerChildren: [NotchUIHierarchyNode] {
        var children = [
            NotchUIHierarchyNode(
                "header-row",
                title: "headerRow",
                badge: statusBadge,
                detail: "opened 显示 openedHeader；closed 显示 closedHeader。",
                color: .white.opacity(0.78),
                children: headerChildren
            )
        ]

        if viewModel.status == .opened {
            children.append(
                NotchUIHierarchyNode(
                    "opened-content",
                    title: "contentView",
                    badge: contentTypeText,
                    detail: "在 header 下方，延迟淡入并 clipped 到 opened 内容槽。",
                    color: contentTint,
                    children: openedContentChildren
                )
            )
        }

        return children
    }

    private var headerChildren: [NotchUIHierarchyNode] {
        if viewModel.status == .opened {
            return [
                NotchUIHierarchyNode(
                    "opened-header",
                    title: "openedHeader",
                    detail: "标题 + tab 切换 + 设置按钮 + 关闭按钮。",
                    children: [
                        NotchUIHierarchyNode("opened-title", title: "header icon/title", detail: viewModel.contentType.headerTitle(itemCount: viewModel.itemCount)),
                        NotchUIHierarchyNode("opened-tabs", title: "panel tabs", detail: "剪贴板 / Vibe"),
                        NotchUIHierarchyNode("opened-settings", title: "settingsToggleButton", detail: "设置与列表之间切换"),
                        NotchUIHierarchyNode("opened-close", title: "closeButton", detail: "关闭 notch")
                    ]
                )
            ]
        }

        return [
            NotchUIHierarchyNode(
                "closed-header",
                title: "closedHeader",
                badge: copyHintText,
                detail: "closed 态内容槽，显示复制提示、Agent 状态或透明占位。",
                children: closedHeaderChildren
            )
        ]
    }

    private var closedHeaderChildren: [NotchUIHierarchyNode] {
        if let copyHint = viewModel.copyHint {
            switch copyHint {
            case .text:
                return [NotchUIHierarchyNode("copy-text-hint", title: "textHint", detail: "左侧剪贴板图标 + 右侧文本预览。", color: .cyan.opacity(0.8))]
            case .file(let urls):
                return [NotchUIHierarchyNode("copy-file-hint", title: "fileHint", detail: "QuickLook 缩略图 + 文件名。当前 \(urls.count) 个文件。", color: .cyan.opacity(0.8))]
            case .image(let data):
                return [NotchUIHierarchyNode("copy-image-hint", title: "imageHint", detail: "图片缩略图 + 数据大小。当前 \(byteSizeString(data.count))。", color: .cyan.opacity(0.8))]
            }
        }

        if vibeStore.dashboard.notchActivity != .idle {
            return [
                NotchUIHierarchyNode(
                    "agent-activity-hint",
                    title: "agentActivityHint",
                    badge: agentText,
                    detail: "根据详细/简约模式切换；运行中可显示火焰波。",
                    color: agentTint,
                    children: [
                        NotchUIHierarchyNode(
                            "agent-flame-wave",
                            title: "AgentFlameWaveView",
                            badge: prefs.agentActivityIconEffect == .flameWave ? "visible" : "hidden",
                            detail: "Canvas 背景层；运行中 + 火焰波动效时显示，位于 Agent 图标与文案下方。",
                            color: .purple.opacity(0.9)
                        ),
                        NotchUIHierarchyNode(
                            "agent-icon-text",
                            title: "Agent icon / status / sessions",
                            detail: "图标、Working/Needs input 文案、session 数。"
                        )
                    ]
                )
            ]
        }

        return [NotchUIHierarchyNode("closed-empty", title: "Color.clear", detail: "没有复制提示和 Agent 活动时，closed header 透明占位。", color: .white.opacity(0.36))]
    }

    private var openedContentChildren: [NotchUIHierarchyNode] {
        switch viewModel.contentType {
        case .list:
            return [
                NotchUIHierarchyNode("clipboard-list", title: "ClipboardListView", detail: "剪贴板搜索、分类、分页/列表项、拖拽导出入口。", color: .cyan.opacity(0.85))
            ]
        case .vibe:
            return [
                NotchUIHierarchyNode(
                    "lazy-vibe",
                    title: "LazyVibeContentView",
                    detail: "只在点击 Vibe 后加载 Agent 数据。",
                    color: .purple.opacity(0.86),
                    children: [
                        NotchUIHierarchyNode("latest-diff", title: "Latest Diff tab", detail: "默认折叠；点击箭头展开完整 diff。"),
                        NotchUIHierarchyNode("vibe-tabs", title: "总览 / 批准 / 询问 / 跳回", detail: "Vibe Agent 操作过滤。"),
                        NotchUIHierarchyNode("agent-session-list", title: "Agent session list/detail", detail: "Claude / Codex / Gemini 会话、Jump、问答和批准控件。")
                    ]
                )
            ]
        case .settings:
            return [
                NotchUIHierarchyNode(
                    "settings-view",
                    title: "NotchSettingsView",
                    detail: "设置列表；Debug 工具入口隐藏在版本号 5 连击。",
                    color: .orange.opacity(0.85)
                )
            ]
        }
    }

    private var statusBadge: String {
        viewModel.status == .opened ? "opened" : "closed"
    }

    private var statusText: String {
        switch viewModel.status {
        case .closed: return "closed"
        case .opened: return "opened"
        }
    }

    private var contentTypeText: String {
        viewModel.contentType.tabTitle
    }

    private var contentTint: Color {
        switch viewModel.contentType {
        case .list: return .cyan.opacity(0.86)
        case .vibe: return .purple.opacity(0.9)
        case .settings: return .orange.opacity(0.88)
        }
    }

    private var copyHintText: String {
        switch viewModel.copyHint {
        case .none: return "none"
        case .text: return "text"
        case .file(let urls): return "file \(urls.count)"
        case .image(let data): return "image \(byteSizeString(data.count))"
        }
    }

    private var copyHintTint: Color {
        viewModel.copyHint == nil ? .white.opacity(0.5) : .cyan.opacity(0.9)
    }

    private var agentText: String {
        switch vibeStore.dashboard.notchActivity {
        case .idle:
            return "idle"
        case .running:
            return "running \(vibeStore.dashboard.activeSessionCount)"
        case .needsInteraction:
            return "needs input \(vibeStore.dashboard.activeSessionCount)"
        }
    }

    private var agentTint: Color {
        switch vibeStore.dashboard.notchActivity {
        case .idle: return .white.opacity(0.5)
        case .running: return .cyan.opacity(0.9)
        case .needsInteraction: return .orange.opacity(0.92)
        }
    }

    private func sizeText(_ size: CGSize) -> String {
        "\(Int(size.width.rounded())) x \(Int(size.height.rounded()))"
    }

    private func byteSizeString(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return "\(bytes / 1024) KB" }
        return String(format: "%.1f MB", Double(bytes) / 1024.0 / 1024.0)
    }

    private func hierarchyNode(for id: String) -> NotchUIHierarchyNode? {
        hierarchyNode(for: id, in: hierarchyNodes)
    }

    private func hierarchyNode(for id: String, in nodes: [NotchUIHierarchyNode]) -> NotchUIHierarchyNode? {
        for node in nodes {
            if node.id == id { return node }
            if let child = hierarchyNode(for: id, in: node.children) {
                return child
            }
        }
        return nil
    }

    private func hierarchyAdjustmentBinding(for nodeID: String) -> Binding<NotchHierarchyDebugAdjustment> {
        Binding(
            get: {
                viewModel.hierarchyDebugAdjustments[nodeID] ?? .zero
            },
            set: { newValue in
                var adjustments = viewModel.hierarchyDebugAdjustments
                if newValue == .zero {
                    adjustments.removeValue(forKey: nodeID)
                } else {
                    adjustments[nodeID] = newValue
                }
                viewModel.hierarchyDebugAdjustments = adjustments
            }
        )
    }

    private func resetHierarchyAdjustment(for nodeID: String) {
        var adjustments = viewModel.hierarchyDebugAdjustments
        adjustments.removeValue(forKey: nodeID)
        viewModel.hierarchyDebugAdjustments = adjustments
    }

    private func clearHierarchyDebugState() {
        viewModel.highlightedHierarchyNodeID = nil
        viewModel.hierarchyDebugAdjustmentPanelNodeID = nil
        viewModel.hierarchyDebugAdjustments.removeAll()
    }
}

private struct NotchHierarchyMetricCard: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.36))
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(tint)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.045))
        )
    }
}

private struct NotchHierarchyNodeRow: View {
    let node: NotchUIHierarchyNode
    let depth: Int
    @Binding var selectedID: String?
    @Binding var adjustmentPanelNodeID: String?

    private var isSelected: Bool {
        selectedID == node.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Button {
                selectedID = isSelected ? nil : node.id
            } label: {
                HStack(alignment: .top, spacing: 8) {
                    Rectangle()
                        .fill(node.color)
                        .frame(width: 4, height: 18)
                        .cornerRadius(2)
                        .padding(.leading, CGFloat(depth) * 18)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 7) {
                            Text(node.title)
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundColor(isSelected ? .white : .white.opacity(0.84))
                            if let badge = node.badge {
                                Text(badge)
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundColor(.black.opacity(0.82))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule(style: .continuous)
                                            .fill(node.color.opacity(isSelected ? 1.0 : 0.92))
                                    )
                            }
                        }

                        if !node.detail.isEmpty {
                            Text(node.detail)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(isSelected ? .white.opacity(0.58) : .white.opacity(0.38))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isSelected ? node.color.opacity(0.16) : Color.clear)
                )
                .background(
                    NotchHierarchyRightClickMonitor {
                        selectedID = node.id
                        adjustmentPanelNodeID = node.id
                    }
                )
            }
            .buttonStyle(.plain)
            .help("左键高亮；右键打开临时大小/位置调整")

            ForEach(node.children) { child in
                NotchHierarchyNodeRow(
                    node: child,
                    depth: depth + 1,
                    selectedID: $selectedID,
                    adjustmentPanelNodeID: $adjustmentPanelNodeID
                )
            }
        }
    }
}

private struct NotchHierarchyAdjustmentPanel: View {
    let node: NotchUIHierarchyNode
    @Binding var adjustment: NotchHierarchyDebugAdjustment
    let onReset: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "ruler")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(node.color)
                Text("临时大小/位置调整")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.76))
                Text(node.title)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(node.color.opacity(0.88))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("重置") {
                    onReset()
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.58))
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.46))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
            }

            Text("宽/高会临时改变真实 UI 布局；X/Y 只做临时位置偏移。所有值只在内存中生效，不会保存。")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.38))

            VStack(spacing: 8) {
                debugAdjustmentRow(
                    title: "X",
                    value: doubleBinding(\.offsetX),
                    range: -180...180,
                    suffix: "pt"
                )
                debugAdjustmentRow(
                    title: "Y",
                    value: doubleBinding(\.offsetY),
                    range: -180...180,
                    suffix: "pt"
                )
                debugAdjustmentRow(
                    title: "宽",
                    value: doubleBinding(\.widthDelta),
                    range: -240...240,
                    suffix: "pt"
                )
                debugAdjustmentRow(
                    title: "高",
                    value: doubleBinding(\.heightDelta),
                    range: -180...180,
                    suffix: "pt"
                )
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.045))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(node.color.opacity(0.28), lineWidth: 1)
                )
        )
    }

    private func debugAdjustmentRow(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        suffix: String
    ) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.52))
                .frame(width: 22, alignment: .leading)

            Slider(value: value, in: range, step: 1)
                .controlSize(.small)
                .tint(node.color)

            Stepper(value: value, in: range, step: 1) {
                Text("\(Int(value.wrappedValue.rounded())) \(suffix)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.70))
                    .frame(width: 72, alignment: .trailing)
            }
            .labelsHidden()
            .frame(width: 96)
        }
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private func doubleBinding(_ keyPath: WritableKeyPath<NotchHierarchyDebugAdjustment, Double>) -> Binding<Double> {
        Binding(
            get: { adjustment[keyPath: keyPath] },
            set: { newValue in
                var next = adjustment
                next[keyPath: keyPath] = newValue
                adjustment = next
            }
        )
    }
}

private struct NotchHierarchyRightClickMonitor: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> NotchHierarchyRightClickMonitorView {
        let view = NotchHierarchyRightClickMonitorView()
        view.action = action
        return view
    }

    func updateNSView(_ nsView: NotchHierarchyRightClickMonitorView, context: Context) {
        nsView.action = action
    }
}

private final class NotchHierarchyRightClickMonitorView: NSView {
    var action: (() -> Void)?
    private var monitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            uninstallMonitor()
        } else {
            installMonitor()
        }
    }

    deinit {
        uninstallMonitor()
    }

    private func installMonitor() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown]) { [weak self] event in
            guard let self, self.window === event.window else { return event }
            let point = self.convert(event.locationInWindow, from: nil)
            guard self.bounds.contains(point) else { return event }
            self.action?()
            return nil
        }
    }

    private func uninstallMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }
}

private struct AgentFlameWaveDebugPanelView: View {
    @ObservedObject private var prefs = PreferencesStore.shared

    @State private var previewWidth: Double = 620
    @State private var previewHeight: Double = 44
    @State private var presetMessage: String = ""

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()
                .overlay(Color.white.opacity(0.08))

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 18) {
                    livePreview
                    controls
                }
                .padding(22)
            }
        }
        .foregroundColor(.white)
        .background(Color.black.opacity(0.94))
        .frame(minWidth: 640, minHeight: 460)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.cyan)
            VStack(alignment: .leading, spacing: 2) {
                Text("火焰波 Debug")
                    .font(.system(size: 16, weight: .semibold))
                Text("独立窗口实时微调，不占用 notch 面板布局")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.42))
            }
            Spacer()
            if !presetMessage.isEmpty {
                Text(presetMessage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.42))
                    .lineLimit(1)
            }
            Button("保存参数") {
                prefs.saveAgentFlameWavePreset()
                presetMessage = "已保存"
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.white.opacity(0.82))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.white.opacity(0.10))
            )
            Button("载入参数") {
                presetMessage = prefs.loadAgentFlameWavePreset() ? "已载入" : "暂无保存"
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.white.opacity(0.82))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.white.opacity(0.10))
            )
            Button("恢复默认") {
                resetDefaults()
                presetMessage = "已恢复默认"
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.black)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.white.opacity(0.9))
            )
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var livePreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("实时预览")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.68))
                Spacer()
                Text("\(Int(previewWidth.rounded())) x \(Int(previewHeight.rounded())) pt")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.42))
            }

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: CGFloat(previewHeight) / 2, style: .continuous)
                    .fill(Color.black)
                    .overlay(
                        RoundedRectangle(cornerRadius: CGFloat(previewHeight) / 2, style: .continuous)
                            .stroke(Color.cyan.opacity(0.24), lineWidth: 1)
                    )

                AgentFlameWaveView(capCenterX: 34, capCenterYOffset: 0)
                    .clipShape(RoundedRectangle(cornerRadius: CGFloat(previewHeight) / 2, style: .continuous))
            }
            .frame(width: CGFloat(previewWidth), height: CGFloat(previewHeight))
            .shadow(color: Color.cyan.opacity(0.16), radius: 18, x: 0, y: 0)
            .frame(maxWidth: .infinity, alignment: .center)

            HStack(spacing: 12) {
                FlameWaveDebugSliderRow(
                    title: "预览宽度",
                    value: $previewWidth,
                    range: 360...900,
                    step: 1,
                    format: "%.0f pt"
                )
                FlameWaveDebugSliderRow(
                    title: "预览高度",
                    value: $previewHeight,
                    range: 28...76,
                    step: 1,
                    format: "%.0f pt"
                )
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.045))
        )
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("方块与 Bloom 参数")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.68))

            FlameWaveDebugSliderRow(
                title: "方块尺寸",
                value: $prefs.agentFlameWaveCellSize,
                range: 0...5.2,
                step: 0.1,
                format: "%.1f pt",
                detail: "单个像素块的固定尺寸；0 会交给渲染层使用最小安全尺寸。"
            )
            FlameWaveDebugSliderRow(
                title: "列间距",
                value: $prefs.agentFlameWaveColumnPitch,
                range: 0...12,
                step: 0.1,
                format: "%.1f pt",
                detail: "每列粒子中心之间的固定间距；0 会使用最小安全间距计算列数。"
            )
            FlameWaveDebugSliderRow(
                title: "总宽倍率",
                value: $prefs.agentFlameWaveWidthScale,
                range: 0...4,
                step: 0.05,
                format: "%.2fx",
                detail: "控制火焰波生成区域总宽度；0 会压缩到最小安全宽度，1 为当前刘海宽度。"
            )
            FlameWaveDebugSliderRow(
                title: "整体横移",
                value: $prefs.agentFlameWaveHorizontalOffset,
                range: -240...240,
                step: 1,
                format: "%.0f pt",
                detail: "整体左右移动火焰波；负值向左压住图标边缘黑缝，0 为默认位置。"
            )
            FlameWaveDebugSliderRow(
                title: "Working X",
                value: $prefs.agentWorkingTextOffset,
                range: -160...160,
                step: 1,
                format: "%.0f pt",
                detail: "详细模式左侧 Working 文案水平位置；正值向右，负值向左。"
            )
            FlameWaveDebugSliderRow(
                title: "Session X",
                value: $prefs.agentSessionsTextOffset,
                range: -160...160,
                step: 1,
                format: "%.0f pt",
                detail: "详细模式右侧 sessions 文案水平位置；正值向右，负值向左。"
            )
            FlameWaveDebugSliderRow(
                title: "泛光范围",
                value: $prefs.agentFlameWaveGlowScale,
                range: 0...8.0,
                step: 0.05,
                format: "%.2fx",
                detail: "每个方块的外圈发光扩散倍率；0 表示不扩散。"
            )
            FlameWaveDebugSliderRow(
                title: "泛光透明",
                value: $prefs.agentFlameWaveGlowOpacity,
                range: 0...3,
                step: 0.05,
                format: "%.2fx",
                detail: "方块泛光层整体强度。"
            )
            FlameWaveDebugSliderRow(
                title: "左侧模糊",
                value: $prefs.agentFlameWaveLeadingBlur,
                range: 0...4,
                step: 0.05,
                format: "%.2f pt",
                detail: "靠近图标左侧的方块本身 blur 半径，不再放大周围区域。"
            )
            FlameWaveDebugSliderRow(
                title: "明度曲线",
                value: $prefs.agentFlameWaveBrightnessPower,
                range: 0...4,
                step: 0.05,
                format: "%.2f",
                detail: "控制紫色到白紫高亮的渐变速度。"
            )
            FlameWaveDebugSliderRow(
                title: "Bloom 强度",
                value: $prefs.agentFlameWaveBloomStrength,
                range: 0...3,
                step: 0.05,
                format: "%.2fx",
                detail: "方块泛光层的整体高亮强度；不再显示左侧圆角矩形。"
            )
            FlameWaveDebugColorRow(
                title: "主紫色",
                color: purpleColor,
                detail: "火焰波默认紫色主色，明度曲线会基于这个颜色生成深浅变化。"
            )
            FlameWaveDebugColorRow(
                title: "白点颜色",
                color: sparkColor,
                detail: "火焰波中高亮白点的颜色。"
            )
            FlameWaveDebugSliderRow(
                title: "扩散速度",
                value: $prefs.agentFlameWaveExpansionSpeed,
                range: 0...4,
                step: 0.05,
                format: "%.2fx",
                detail: "控制火焰波从左向右生长的速度；0 表示不继续扩散。"
            )
            FlameWaveDebugSliderRow(
                title: "左右波幅",
                value: $prefs.agentFlameWaveHorizontalDrift,
                range: 0...0.08,
                step: 0.001,
                format: "%.3f",
                detail: "方块自身左右游动的幅度，按火焰波宽度比例计算。"
            )
            FlameWaveDebugSliderRow(
                title: "左右速度",
                value: $prefs.agentFlameWaveHorizontalDriftSpeed,
                range: 0...4,
                step: 0.05,
                format: "%.2fx",
                detail: "方块左右波动的运动速度；0 表示静止。"
            )
            FlameWaveDebugSliderRow(
                title: "消失强度",
                value: $prefs.agentFlameWaveFadeDepth,
                range: 0...0.95,
                step: 0.01,
                format: "%.2f",
                detail: "控制方块动态变暗、消失的强度。"
            )
            FlameWaveDebugSliderRow(
                title: "消失速度",
                value: $prefs.agentFlameWaveFadeSpeed,
                range: 0...4,
                step: 0.05,
                format: "%.2fx",
                detail: "方块消失与恢复的动态速度；0 表示停止动态变化。"
            )
            FlameWaveDebugSliderRow(
                title: "波动噪声",
                value: $prefs.agentFlameWaveWaveNoise,
                range: 0...3,
                step: 0.05,
                format: "%.2fx",
                detail: "控制上下波动强度；拖到最左侧时完全不做上下波动。"
            )
            FlameWaveDebugSliderRow(
                title: "白点噪声",
                value: $prefs.agentFlameWaveSparkNoise,
                range: 0...3,
                step: 0.05,
                format: "%.2fx",
                detail: "控制高亮点出现时的随机扰动。"
            )
            FlameWaveDebugSliderRow(
                title: "白点分布",
                value: $prefs.agentFlameWaveSparkDistribution,
                range: 0...4,
                step: 0.05,
                format: "%.2f",
                detail: "分布函数指数；低值更分散，高值更集中。"
            )
            FlameWaveDebugSliderRow(
                title: "横向中心",
                value: $prefs.agentFlameWaveSparkHorizontalCenter,
                range: 0...1,
                step: 0.01,
                format: "%.2f",
                detail: "白点横向高发位置；0 在尾部，1 靠近图标起点。"
            )
            FlameWaveDebugSliderRow(
                title: "横向范围",
                value: $prefs.agentFlameWaveSparkHorizontalSpread,
                range: 0...1,
                step: 0.01,
                format: "%.2f",
                detail: "白点横向扩散宽度；越大覆盖越宽。"
            )
            FlameWaveDebugSliderRow(
                title: "闪烁速度",
                value: $prefs.agentFlameWaveSparkSpeed,
                range: 0...4,
                step: 0.05,
                format: "%.2fx",
                detail: "白点闪烁与随机步进速度；0 表示不随时间闪烁。"
            )
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.045))
        )
    }

    private func resetDefaults() {
        prefs.agentFlameWaveCellSize = 2.6
        prefs.agentFlameWaveGlowScale = 2.45
        prefs.agentFlameWaveGlowOpacity = 1.0
        prefs.agentFlameWaveLeadingBlur = 1.0
        prefs.agentFlameWaveBrightnessPower = 1.35
        prefs.agentFlameWaveBloomStrength = 1.0
        prefs.agentFlameWavePurpleRed = 0.78
        prefs.agentFlameWavePurpleGreen = 0.28
        prefs.agentFlameWavePurpleBlue = 1.0
        prefs.agentFlameWaveSparkRed = 1.0
        prefs.agentFlameWaveSparkGreen = 1.0
        prefs.agentFlameWaveSparkBlue = 1.0
        prefs.agentFlameWaveColumnPitch = 5.8
        prefs.agentFlameWaveWidthScale = 1.0
        prefs.agentFlameWaveHorizontalOffset = 0
        prefs.agentWorkingTextOffset = 0
        prefs.agentSessionsTextOffset = 0
        prefs.agentFlameWaveWaveNoise = 1.0
        prefs.agentFlameWaveSparkNoise = 1.0
        prefs.agentFlameWaveSparkDistribution = 1.65
        prefs.agentFlameWaveSparkHorizontalCenter = 0.78
        prefs.agentFlameWaveSparkHorizontalSpread = 0.30
        prefs.agentFlameWaveSparkSpeed = 1.0
        prefs.agentFlameWaveExpansionSpeed = 1.0
        prefs.agentFlameWaveHorizontalDrift = 0.012
        prefs.agentFlameWaveHorizontalDriftSpeed = 1.0
        prefs.agentFlameWaveFadeDepth = 0.10
        prefs.agentFlameWaveFadeSpeed = 1.0
    }

    private var sparkColor: Binding<Color> {
        Binding(
            get: {
                Color(
                    red: prefs.agentFlameWaveSparkRed,
                    green: prefs.agentFlameWaveSparkGreen,
                    blue: prefs.agentFlameWaveSparkBlue
                )
            },
            set: { newColor in
                guard let rgb = NSColor(newColor).usingColorSpace(.sRGB) else { return }
                prefs.agentFlameWaveSparkRed = Double(rgb.redComponent)
                prefs.agentFlameWaveSparkGreen = Double(rgb.greenComponent)
                prefs.agentFlameWaveSparkBlue = Double(rgb.blueComponent)
            }
        )
    }

    private var purpleColor: Binding<Color> {
        Binding(
            get: {
                Color(
                    red: prefs.agentFlameWavePurpleRed,
                    green: prefs.agentFlameWavePurpleGreen,
                    blue: prefs.agentFlameWavePurpleBlue
                )
            },
            set: { newColor in
                guard let rgb = NSColor(newColor).usingColorSpace(.sRGB) else { return }
                prefs.agentFlameWavePurpleRed = Double(rgb.redComponent)
                prefs.agentFlameWavePurpleGreen = Double(rgb.greenComponent)
                prefs.agentFlameWavePurpleBlue = Double(rgb.blueComponent)
            }
        )
    }
}

private struct FlameWaveDebugColorRow: View {
    let title: String
    @Binding var color: Color
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.62))
                    .frame(width: 74, alignment: .leading)

                ColorPicker("", selection: $color, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 48)

                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(color)
                    .frame(width: 42, height: 18)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )

                Spacer()
            }

            if let detail {
                Text(detail)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.34))
                    .padding(.leading, 84)
            }
        }
        .transaction { transaction in
            transaction.animation = nil
        }
    }
}

private struct FlameWaveDebugSliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: String
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.62))
                    .frame(width: 74, alignment: .leading)

                Slider(value: clampedValue, in: range, step: step)
                    .controlSize(.small)
                    .tint(.cyan)

                TextField("", value: clampedValue, format: numericFormat)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.78))
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 5)
                    .frame(width: 66)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )

                Stepper(value: clampedValue, in: range, step: step) { EmptyView() }
                .labelsHidden()
                .frame(width: 36)
            }

            if let detail {
                Text(detail)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.34))
                    .padding(.leading, 84)
            }
        }
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private var clampedValue: Binding<Double> {
        Binding(
            get: { value },
            set: { newValue in
                value = min(max(newValue, range.lowerBound), range.upperBound)
            }
        )
    }

    private var numericFormat: FloatingPointFormatStyle<Double> {
        .number.precision(.fractionLength(0...fractionDigits))
    }

    private var fractionDigits: Int {
        if step >= 1 { return 0 }
        if step >= 0.1 { return 1 }
        if step >= 0.01 { return 2 }
        return 3
    }
}

private struct AgentSettingsDeferredPlaceholder: View {
    let onLoad: () -> Void

    var body: some View {
        Button(action: onLoad) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
                Text("打开完整图标设置窗口")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.44))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.white.opacity(0.32))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.035))
            )
        }
        .buttonStyle(.plain)
    }
}

private struct StaticAgentLifeGridIcon: View {
    let color: Color

    private let cells = AgentLifeGridIcon.cells(for: 0)

    var body: some View {
        GeometryReader { proxy in
            Canvas(opaque: false, colorMode: .linear, rendersAsynchronously: true) { context, size in
                let side = min(size.width, size.height)
                let gap = max(1, side * 0.055)
                let cellSide = max(1, (side - gap * CGFloat(AgentLifeGridIcon.dimension - 1)) / CGFloat(AgentLifeGridIcon.dimension))
                let xInset = (size.width - side) / 2
                let yInset = (size.height - side) / 2

                for index in cells.indices {
                    let row = index / AgentLifeGridIcon.dimension
                    let column = index % AgentLifeGridIcon.dimension
                    let rect = CGRect(
                        x: xInset + CGFloat(column) * (cellSide + gap),
                        y: yInset + CGFloat(row) * (cellSide + gap),
                        width: cellSide,
                        height: cellSide
                    )
                    context.fill(
                        Path(rect),
                        with: .color(color.opacity(cells[index] ? 0.96 : 0.14))
                    )
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

private struct AgentNotchDisplayModeOptionButton: View {
    let mode: AgentActivityNotchDisplayMode
    let isSelected: Bool
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Image(systemName: mode.systemImageName)
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 12)
                    Text(mode.title)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                }

                Text(mode.subtitle)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(isSelected ? .black.opacity(0.62) : .white.opacity(hovered ? 0.54 : 0.34))
                    .lineLimit(1)
            }
            .foregroundColor(isSelected ? .black : .white.opacity(hovered ? 0.95 : 0.62))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 7)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.9) : Color.white.opacity(hovered ? 0.09 : 0.045))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

private struct AgentIconStyleOptionButton: View {
    let style: AgentActivityIconStyle
    let isSelected: Bool
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                icon
                Text(style.title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundColor(contentColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .padding(.horizontal, 7)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.9) : Color.white.opacity(hovered ? 0.09 : 0.045))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }

    private var contentColor: Color {
        isSelected ? .black : .white.opacity(hovered ? 0.95 : 0.62)
    }

    @ViewBuilder
    private var icon: some View {
        if style == .lifeGrid {
            StaticAgentLifeGridIcon(color: contentColor)
                .frame(width: 12, height: 12)
        } else if style.isPixelSymbol {
            AgentActivitySymbolIcon(style: style, color: contentColor)
                .frame(width: 12, height: 12)
        } else if style.isASCII {
            Text(style.asciiFrames.first ?? ">_")
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .frame(width: 18, height: 12)
        } else {
            Image(systemName: style.systemImageName)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 12)
        }
    }
}

private struct AgentIconPositionOptionButton: View {
    let position: AgentActivityIconPosition
    let isSelected: Bool
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: position.systemImageName)
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 12)
                Text(position.title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundColor(isSelected ? .black : .white.opacity(hovered ? 0.95 : 0.62))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .padding(.horizontal, 7)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.9) : Color.white.opacity(hovered ? 0.09 : 0.045))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

private struct AgentIconEffectOptionButton: View {
    let effect: AgentActivityIconEffect
    let isSelected: Bool
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: effect.systemImageName)
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 12)
                Text(effect.title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundColor(isSelected ? .black : .white.opacity(hovered ? 0.95 : 0.62))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .padding(.horizontal, 7)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.9) : Color.white.opacity(hovered ? 0.09 : 0.045))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

struct NotchAccessibilityRow: View {
    let isEnabled: Bool
    let refreshTick: Bool
    let onEnable: () -> Void

    @State private var hovered = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "hand.raised")
                .font(.system(size: 12))
                .foregroundColor(textColor)
                .frame(width: 16)
            Text("辅助功能权限")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(textColor)
            Spacer()
            if isEnabled {
                Circle()
                    .fill(Color(red: 0.4, green: 0.85, blue: 0.5))
                    .frame(width: 6, height: 6)
                Text("已授权")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
            } else {
                Button(action: onEnable) {
                    Text("立即授权")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color.white)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(hovered ? Color.white.opacity(0.08) : .clear)
        )
        .onHover { hovered = $0 }
    }

    private var textColor: Color {
        .white.opacity(hovered ? 1.0 : 0.75)
    }
}
