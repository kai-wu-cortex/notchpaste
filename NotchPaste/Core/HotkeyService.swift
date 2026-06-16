import Foundation
import HotKey
import os

/// 全局快捷键注册器。v0.1 注册一个固定快捷键 ⇧⌘V → 触发回调。
final class HotkeyService {

    /// 注册成功后保留引用；释放即注销。
    private var hotKey: HotKey?

    /// 用户偏好关闭/重绑后，重新调用 register。
    func register(handler: @escaping () -> Void) {
        hotKey = HotKey(key: .v, modifiers: [.command, .shift])
        hotKey?.keyDownHandler = {
            AppLogger.hotkey.debug("global hotkey ⇧⌘V fired")
            handler()
        }
        AppLogger.hotkey.info("registered ⇧⌘V")
    }

    func unregister() {
        hotKey = nil
    }
}
