import AppKit
import Combine

/// 菜单栏图标 + 下拉菜单。常驻显示，提供"显示面板/重新申请权限/退出"等总入口。
///
/// v0.1：始终显示。v0.3 避让能力上线后，会在 pill 不可见（菜单栏 fallback 模式）时承担主要交互。
@MainActor
final class MenuBarController {

    private var statusItem: NSStatusItem?
    private let preferences: PreferencesStore
    private let onShowPanel: () -> Void
    private let onRequestPermission: () -> Void
    private var cancellables = Set<AnyCancellable>()

    init(
        preferences: PreferencesStore = .shared,
        onShowPanel: @escaping () -> Void,
        onRequestPermission: @escaping () -> Void
    ) {
        self.preferences = preferences
        self.onShowPanel = onShowPanel
        self.onRequestPermission = onRequestPermission

        syncStatusItemVisibility(preferences.showMenuBarIcon)

        preferences.$showMenuBarIcon
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] show in
                self?.syncStatusItemVisibility(show)
            }
            .store(in: &cancellables)
    }

    private func syncStatusItemVisibility(_ show: Bool) {
        if show {
            guard statusItem == nil else { return }
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            configure(item)
            statusItem = item
        } else if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    private func configure(_ item: NSStatusItem) {
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "doc.on.clipboard",
                accessibilityDescription: "NotchPaste"
            )
            button.image?.isTemplate = true
        }
        item.menu = makeMenu()
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

        let hideIcon = NSMenuItem(
            title: "隐藏菜单栏图标",
            action: #selector(hideMenuBarIconAction),
            keyEquivalent: ""
        )
        hideIcon.target = self
        menu.addItem(hideIcon)

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

    @objc private func hideMenuBarIconAction() {
        preferences.showMenuBarIcon = false
    }

    @objc private func quitAction() {
        NSApp.terminate(nil)
    }
}
