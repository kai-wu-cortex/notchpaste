import Foundation
import AppKit
import Carbon.HIToolbox
import os

/// 把内容写入系统剪贴板，并（若已授权辅助功能）模拟 ⌘V 注入到当前焦点应用。
final class PasteService {

    private let preferences: PreferencesStore

    init(preferences: PreferencesStore = .shared) {
        self.preferences = preferences
    }

    /// 把 item 内容写入系统剪贴板。
    /// 若 `autoPasteEnabled` 且辅助功能已授权，进一步模拟 ⌘V。
    func paste(_ item: ClipboardItem) {
        copyToPasteboard(item)
        guard preferences.autoPasteEnabled else {
            AppLogger.paste.info("auto-paste disabled in prefs; clipboard updated only")
            return
        }
        guard isAccessibilityTrusted() else {
            AppLogger.paste.notice("accessibility not granted; clipboard updated only")
            return
        }
        simulateCommandV()
    }

    /// 检查辅助功能权限。第一次会弹系统对话框（promptIfNeeded=true）。
    @discardableResult
    func isAccessibilityTrusted(promptIfNeeded: Bool = false) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue()
        let opts: [CFString: Any] = [key: promptIfNeeded]
        return AXIsProcessTrustedWithOptions(opts as CFDictionary)
    }

    // MARK: - Internals

    private func copyToPasteboard(_ item: ClipboardItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.type {
        case .text(let s):
            pb.setString(s, forType: .string)
        }
    }

    private func simulateCommandV() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let vCode = CGKeyCode(kVK_ANSI_V)

        let down = CGEvent(keyboardEventSource: src, virtualKey: vCode, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: src, virtualKey: vCode, keyDown: false)
        up?.flags = .maskCommand

        // 微小延迟，让目标 app 有机会处理 pasteboard 写入
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
            AppLogger.paste.debug("posted ⌘V")
        }
    }
}
