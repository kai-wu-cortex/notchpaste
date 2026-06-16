import Foundation
import AppKit
import Carbon.HIToolbox
import os

/// 把内容写入系统剪贴板，并（若已授权辅助功能）模拟 ⌘V 注入到原焦点位置。
final class PasteService {

    private let preferences: PreferencesStore
    private let pasteAttemptDelays: [TimeInterval] = [0.12, 0.16, 0.22, 0.30, 0.42]
    var accessibilityTrustedProvider: (_ promptIfNeeded: Bool) -> Bool = { promptIfNeeded in
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue()
        let opts: [CFString: Any] = [key: promptIfNeeded]
        return AXIsProcessTrustedWithOptions(opts as CFDictionary)
    }
    var frontmostBundleIdentifierProvider: () -> String? = {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }
    var delayScheduler: (_ delay: TimeInterval, _ action: @escaping () -> Void) -> Void = { delay, action in
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: action)
    }
    var pasteShortcutPoster: () -> Void = {
        let src = CGEventSource(stateID: .combinedSessionState)
        let vCode = CGKeyCode(kVK_ANSI_V)
        let down = CGEvent(keyboardEventSource: src, virtualKey: vCode, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: src, virtualKey: vCode, keyDown: false)
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
    /// 弱引用 monitor，让我们在写剪贴板前通知它"忽略接下来一次 changeCount 增长"，
    /// 避免自动粘贴的内容被监听器当作新复制再记一遍（回流 bug）。
    weak var changeIgnorer: ClipboardChangeIgnoring?

    var monitor: ClipboardMonitor? {
        get { changeIgnorer as? ClipboardMonitor }
        set { changeIgnorer = newValue }
    }

    init(preferences: PreferencesStore = .shared) {
        self.preferences = preferences
    }

    /// 把 item 内容写入系统剪贴板。
    /// 仅当 `autoPasteEnabled` 且辅助功能已授权 **且** `target` 非 nil 时才模拟 ⌘V。
    /// `target` 为 nil 表示"只复制不自动粘贴"——典型场景：用户开启了"复制后保留面板"，
    /// 焦点没有切回原应用，注入 ⌘V 也没意义。
    func paste(_ item: ClipboardItem, activating target: PasteTarget? = nil) {
        copyToPasteboard(item)
        guard preferences.autoPasteEnabled else {
            AppLogger.paste.info("auto-paste disabled in prefs; clipboard updated only")
            return
        }
        guard let target else {
            AppLogger.paste.info("no target app; clipboard updated only (no ⌘V)")
            return
        }
        guard isAccessibilityTrusted() else {
            AppLogger.paste.notice("accessibility not granted; clipboard updated only")
            return
        }
        changeIgnorer?.ignoreNextChange(matching: item)
        simulateCommandV(activating: target)
    }

    /// 检查辅助功能权限。`promptIfNeeded=true` 时若未授权会触发系统对话框。
    @discardableResult
    func isAccessibilityTrusted(promptIfNeeded: Bool = false) -> Bool {
        accessibilityTrustedProvider(promptIfNeeded)
    }

    /// 用户主动"立即授权"流程：先触发系统对话框（让 NotchPaste 出现在辅助功能列表里），
    /// 再打开"系统设置 → 隐私与安全 → 辅助功能"面板。
    /// 这样即使 app 之前被用户从列表删除，也会被重新加回。
    func requestAccessibilityAndOpenPreferences() {
        // 1. 先触发系统对话框：未授权时把当前 app 加入辅助功能名单
        _ = isAccessibilityTrusted(promptIfNeeded: true)
        // 2. 再打开系统设置面板让用户去勾选
        openAccessibilityPreferences()
        AppLogger.paste.info("triggered system permission dialog + opened pane")
    }

    /// 跳转到"系统设置 → 隐私与安全 → 辅助功能"。
    func openAccessibilityPreferences() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - Internals

    private func copyToPasteboard(_ item: ClipboardItem) {
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

    private func simulateCommandV(activating target: PasteTarget) {
        // 不再用 NSApp.hide（那会把 NotchPanel 一起隐藏，之后 hover 唤不回来）。
        // 显式激活目标 app 即可让 macOS 把焦点交回去。
        if let app = target.app, !app.isTerminated {
            app.activate(options: [])
        }

        schedulePasteAttempt(activating: target, attempt: 0)
    }

    private func schedulePasteAttempt(activating target: PasteTarget, attempt: Int) {
        let delay = pasteAttemptDelays[min(attempt, pasteAttemptDelays.count - 1)]
        delayScheduler(delay) { [weak self] in
            guard let self else { return }

            if !self.isTargetFrontmost(target), attempt + 1 < self.pasteAttemptDelays.count {
                self.schedulePasteAttempt(activating: target, attempt: attempt + 1)
                return
            }

            guard self.isTargetFrontmost(target) else {
                AppLogger.paste.notice("target app did not become frontmost; clipboard updated only")
                return
            }

            target.restoreFocus()
            self.pasteShortcutPoster()
            AppLogger.paste.debug("posted ⌘V to \(target.bundleIdentifier ?? "<unknown>", privacy: .public)")
        }
    }

    private func isTargetFrontmost(_ target: PasteTarget) -> Bool {
        guard let bundleIdentifier = target.bundleIdentifier else { return true }
        return frontmostBundleIdentifierProvider() == bundleIdentifier
    }
}
