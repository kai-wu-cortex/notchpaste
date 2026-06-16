import AppKit

/// 菜单栏图标 + 下拉菜单。常驻显示，提供"显示面板/重新申请权限/退出"等总入口。
///
/// v0.1：始终显示。v0.3 避让能力上线后，会在 pill 不可见（菜单栏 fallback 模式）时承担主要交互。
@MainActor
final class MenuBarController {

    private let statusItem: NSStatusItem
    private let onShowPanel: () -> Void
    private let onRequestPermission: () -> Void

    init(
        onShowPanel: @escaping () -> Void,
        onRequestPermission: @escaping () -> Void
    ) {
        self.onShowPanel = onShowPanel
        self.onRequestPermission = onRequestPermission

        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "doc.on.clipboard",
                accessibilityDescription: "NotchPaste"
            )
            button.image?.isTemplate = true
        }
        statusItem.menu = makeMenu()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()

        let show = NSMenuItem(
            title: "显示剪贴板",
            action: #selector(showPanelAction),
            keyEquivalent: "v"
        )
        show.keyEquivalentModifierMask = [.command, .shift]
        show.target = self
        menu.addItem(show)

        menu.addItem(.separator())

        let perm = NSMenuItem(
            title: "重新申请辅助功能权限…",
            action: #selector(requestPermissionAction),
            keyEquivalent: ""
        )
        perm.target = self
        menu.addItem(perm)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "退出 NotchPaste",
            action: #selector(quitAction),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    @objc private func showPanelAction() {
        onShowPanel()
    }

    @objc private func requestPermissionAction() {
        onRequestPermission()
    }

    @objc private func quitAction() {
        NSApp.terminate(nil)
    }
}
