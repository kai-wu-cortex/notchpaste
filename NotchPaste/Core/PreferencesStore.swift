import Foundation
import Combine

/// UserDefaults 包装，集中管理用户偏好。线程安全，可观察。
final class PreferencesStore: ObservableObject {
    static let shared = PreferencesStore()

    private let defaults: UserDefaults

    private enum Key {
        static let maxItems = "NotchPaste.maxItems"
        static let autoPasteEnabled = "NotchPaste.autoPasteEnabled"
        static let hoverToExpand = "NotchPaste.hoverToExpand"
        static let closeAfterCopy = "NotchPaste.closeAfterCopy"
        static let monitoringEnabled = "NotchPaste.monitoringEnabled"
        static let shortcutId = "NotchPaste.shortcutId"
    }

    @Published var maxItems: Int {
        didSet { defaults.set(maxItems, forKey: Key.maxItems) }
    }

    /// 复制后是否自动注入 ⌘V 到原应用。
    @Published var autoPasteEnabled: Bool {
        didSet { defaults.set(autoPasteEnabled, forKey: Key.autoPasteEnabled) }
    }

    /// 鼠标悬停 1s 是否自动展开面板。关掉后只能点击 / 快捷键打开。
    @Published var hoverToExpand: Bool {
        didSet { defaults.set(hoverToExpand, forKey: Key.hoverToExpand) }
    }

    /// 选择历史项后是否自动收起面板。关掉则面板保持打开方便连续复制。
    @Published var closeAfterCopy: Bool {
        didSet { defaults.set(closeAfterCopy, forKey: Key.closeAfterCopy) }
    }

    /// 隐私模式：剪贴板监听总开关。关闭后不再记录新的剪贴内容。
    @Published var monitoringEnabled: Bool {
        didSet { defaults.set(monitoringEnabled, forKey: Key.monitoringEnabled) }
    }

    /// 当前快捷键的序列化 id。
    @Published var shortcut: GlobalShortcut {
        didSet { defaults.set(shortcut.id, forKey: Key.shortcutId) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedMaxItems: Int = (defaults.object(forKey: Key.maxItems) as? Int) ?? 200
        let storedAutoPaste: Bool = (defaults.object(forKey: Key.autoPasteEnabled) as? Bool) ?? true
        let storedHover: Bool = (defaults.object(forKey: Key.hoverToExpand) as? Bool) ?? true
        let storedClose: Bool = (defaults.object(forKey: Key.closeAfterCopy) as? Bool) ?? true
        let storedMonitor: Bool = (defaults.object(forKey: Key.monitoringEnabled) as? Bool) ?? true
        let storedShortcutId: String = (defaults.object(forKey: Key.shortcutId) as? String) ?? GlobalShortcut.default.id

        self.maxItems = storedMaxItems
        self.autoPasteEnabled = storedAutoPaste
        self.hoverToExpand = storedHover
        self.closeAfterCopy = storedClose
        self.monitoringEnabled = storedMonitor
        self.shortcut = GlobalShortcut.fromConfig(storedShortcutId)
    }
}
