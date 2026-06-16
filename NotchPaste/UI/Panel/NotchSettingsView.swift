import SwiftUI
import AppKit
import ServiceManagement

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
