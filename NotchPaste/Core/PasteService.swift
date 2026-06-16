import Foundation
import AppKit
import Carbon.HIToolbox
import os

/// 把内容写入系统剪贴板，并（若已授权辅助功能）模拟 ⌘V 注入到当前焦点应用。
final class PasteService {

    private let preferences: PreferencesStore
    /// 弱引用 monitor，让我们在写剪贴板前通知它"忽略接下来一次 changeCount 增长"，
    /// 避免自动粘贴的内容被监听器当作新复制再记一遍（回流 bug）。
    weak var monitor: ClipboardMonitor?

    init(preferences: PreferencesStore = .shared) {
        self.preferences = preferences
    }

    /// 把 item 内容写入系统剪贴板。
    /// 仅当 `autoPasteEnabled` 且辅助功能已授权 **且** `targetApp` 非 nil 时才模拟 ⌘V。
    /// `targetApp` 为 nil 表示"只复制不自动粘贴"——典型场景：用户开启了"复制后保留面板"，
    /// 焦点没有切回原应用，注入 ⌘V 也没意义。
    func paste(_ item: ClipboardItem, activating targetApp: NSRunningApplication? = nil) {
        copyToPasteboard(item)
        guard preferences.autoPasteEnabled else {
            AppLogger.paste.info("auto-paste disabled in prefs; clipboard updated only")
            return
        }
        guard let target = targetApp else {
            AppLogger.paste.info("no target app; clipboard updated only (no ⌘V)")
            return
        }
        guard isAccessibilityTrusted() else {
            AppLogger.paste.notice("accessibility not granted; clipboard updated only")
            return
        }
        simulateCommandV(activating: target)
    }

    /// 检查辅助功能权限。`promptIfNeeded=true` 时若未授权会触发系统对话框。
    @discardableResult
    func isAccessibilityTrusted(promptIfNeeded: Bool = false) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue()
        let opts: [CFString: Any] = [key: promptIfNeeded]
        return AXIsProcessTrustedWithOptions(opts as CFDictionary)
    }

    /// 跳转到"系统设置 → 隐私与安全 → 辅助功能"，并把 NotchPaste 加入候选。
    /// 在启动时检测到未授权且首次提示对话框无效时使用。
    func openAccessibilityPreferences() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
        AppLogger.paste.info("opened Accessibility preferences pane")
    }

    // MARK: - Internals

    private func copyToPasteboard(_ item: ClipboardItem) {
        // 写之前通知 monitor 忽略下一次 change（避免自动粘贴回流）
        monitor?.ignoreNextChange()

        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.type {
        case .text(let s):
            pb.setString(s, forType: .string)
        case .url(let raw, _):
            pb.setString(raw, forType: .string)
        case .file(let urls):
            pb.writeObjects(urls as [NSURL])
        case .image(let data):
            pb.setData(data, forType: .png)
            if let img = NSImage(data: data) {
                pb.writeObjects([img])
            }
        }
    }

    private func simulateCommandV(activating targetApp: NSRunningApplication) {
        // 不再用 NSApp.hide（那会把 NotchPanel 一起隐藏，之后 hover 唤不回来）。
        // 显式激活目标 app 即可让 macOS 把焦点交回去。
        if !targetApp.isTerminated {
            targetApp.activate(options: [])
        }

        // 等焦点真正切过去再注入 ⌘V。180ms 是经验值：
        // macOS 的 activation 是异步的，太短会注入到我们自己上。
        let src = CGEventSource(stateID: .combinedSessionState)
        let vCode = CGKeyCode(kVK_ANSI_V)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            let down = CGEvent(keyboardEventSource: src, virtualKey: vCode, keyDown: true)
            down?.flags = .maskCommand
            let up = CGEvent(keyboardEventSource: src, virtualKey: vCode, keyDown: false)
            up?.flags = .maskCommand
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
            AppLogger.paste.debug("posted ⌘V to \(targetApp.bundleIdentifier ?? "<unknown>", privacy: .public)")
        }
    }
}
