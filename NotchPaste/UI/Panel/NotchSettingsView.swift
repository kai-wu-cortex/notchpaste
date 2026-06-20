import SwiftUI
import AppKit
import ServiceManagement
import UniformTypeIdentifiers

/// 设置面板视图。风格参考 farouqaldori/vibe-notch (Apache 2.0)：
/// 黑色背景上的 row 列表，hover 高亮，每行 icon + 中文标签 + 状态/按钮。
struct NotchSettingsView: View {
    @ObservedObject var viewModel: NotchViewModel
    @ObservedObject private var prefs = PreferencesStore.shared
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

                AgentActivityIconSettingsRow(prefs: prefs)

                divider

                // 快捷键
                ShortcutPickerRow(prefs: prefs)

                divider

                // 系统集成
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
                NotchMenuRow(icon: "info.circle", label: "版本信息", trailing: appVersionString) {}

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

    @State private var isExpanded = false
    @State private var hovered = false

    private let columns = [
        GridItem(.adaptive(minimum: 72), spacing: 6)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                    isExpanded.toggle()
                }
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
                    Text("\(prefs.agentRunningIconStyle.title) · \(prefs.agentActivityIconPosition.title)")
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
            optionGroup(title: "运行中") {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
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
                LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
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
                LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
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
                LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
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

            optionGroup(title: "图标像素微调") {
                VStack(spacing: 7) {
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
                VStack(spacing: 7) {
                    PixelAdjustmentRow(
                        title: "统一宽",
                        value: $prefs.agentRunningNotchWidthAdjustment,
                        range: -80...120,
                        unit: "pt"
                    )
                    PixelAdjustmentRow(
                        title: "运行高",
                        value: $prefs.agentRunningNotchHeightAdjustment,
                        range: -6...32,
                        unit: "pt"
                    )
                }
            }
        }
        .padding(.leading, 30)
        .padding(.trailing, 12)
        .padding(.bottom, 8)
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

    private var textColor: Color {
        .white.opacity(hovered ? 1.0 : 0.75)
    }
}

private struct CustomIconPickerRow: View {
    private static let previewCache = NSCache<NSString, NSImage>()

    let title: String
    @Binding var path: String?

    @State private var hovered = false

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
    }

    @ViewBuilder
    private var preview: some View {
        if let path, let image = cachedPreviewImage(at: path) {
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

    private func cachedPreviewImage(at path: String) -> NSImage? {
        let key = path as NSString
        if let image = Self.previewCache.object(forKey: key) {
            return image
        }
        guard let image = NSImage(contentsOfFile: path) else { return nil }
        Self.previewCache.setObject(image, forKey: key)
        return image
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

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.58))
                .frame(width: 44, alignment: .leading)

            Slider(value: pixelValue, in: range, step: 1)
                .controlSize(.small)
                .tint(.cyan)

            Stepper(value: pixelValue, in: range, step: 1) {
                Text("\(Int(value.rounded())) \(unit)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.68))
                    .frame(width: 54, alignment: .trailing)
            }
            .labelsHidden()
            .frame(width: 72)
        }
    }

    private var pixelValue: Binding<Double> {
        Binding(
            get: { value },
            set: { value = min(max($0.rounded(), range.lowerBound), range.upperBound) }
        )
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
        if style.isPixelSymbol {
            AgentActivitySymbolIcon(style: style, color: contentColor)
                .frame(width: 12, height: 12)
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
