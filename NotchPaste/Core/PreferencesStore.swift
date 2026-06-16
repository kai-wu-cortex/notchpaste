import Foundation
import Combine

/// UserDefaults 包装，集中管理用户偏好。线程安全，可观察。
final class PreferencesStore: ObservableObject {
    static let shared = PreferencesStore()

    private let defaults: UserDefaults

    private enum Key {
        static let maxItems = "NotchPaste.maxItems"
        static let autoPasteEnabled = "NotchPaste.autoPasteEnabled"
    }

    @Published var maxItems: Int {
        didSet { defaults.set(maxItems, forKey: Key.maxItems) }
    }

    @Published var autoPasteEnabled: Bool {
        didSet { defaults.set(autoPasteEnabled, forKey: Key.autoPasteEnabled) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // 注意：直接读 .integer(forKey:) 时，未设置返回 0；这里用 object 检查
        if let v = defaults.object(forKey: Key.maxItems) as? Int {
            self.maxItems = v
        } else {
            self.maxItems = 200
        }
        if let v = defaults.object(forKey: Key.autoPasteEnabled) as? Bool {
            self.autoPasteEnabled = v
        } else {
            self.autoPasteEnabled = true
        }
    }
}
