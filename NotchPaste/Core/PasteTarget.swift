import AppKit

/// 自动粘贴的目标：原前台 app + 打开面板前的辅助功能焦点元素。
/// 只保存 app 不够，Notion 这类应用可能把焦点恢复到搜索框等临时输入框。
struct PasteTarget {
    let app: NSRunningApplication?
    let bundleIdentifier: String?
    private let restoreFocusedElement: () -> Void

    init(
        app: NSRunningApplication?,
        bundleIdentifier: String? = nil,
        restoreFocusedElement: @escaping () -> Void = {}
    ) {
        self.app = app
        self.bundleIdentifier = bundleIdentifier ?? app?.bundleIdentifier
        self.restoreFocusedElement = restoreFocusedElement
    }

    static func capture(excluding bundleIdentifier: String? = Bundle.main.bundleIdentifier) -> PasteTarget? {
        guard let frontmost = NSWorkspace.shared.frontmostApplication,
              frontmost.bundleIdentifier != bundleIdentifier else { return nil }

        let restorer = focusedElementRestorer() ?? {}
        return PasteTarget(app: frontmost, restoreFocusedElement: restorer)
    }

    static func captureApplicationOnly(excluding bundleIdentifier: String? = Bundle.main.bundleIdentifier) -> PasteTarget? {
        guard let frontmost = NSWorkspace.shared.frontmostApplication,
              frontmost.bundleIdentifier != bundleIdentifier else { return nil }

        return PasteTarget(app: frontmost)
    }

    static func captureFocusedElementTarget(app: NSRunningApplication) -> PasteTarget {
        let restorer = focusedElementRestorer() ?? {}
        return PasteTarget(app: app, restoreFocusedElement: restorer)
    }

    func restoreFocus() {
        restoreFocusedElement()
    }

    private static func focusedElementRestorer() -> (() -> Void)? {
        let systemWide = AXUIElementCreateSystemWide()
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &value
        )
        guard result == .success, let value else { return nil }

        let element = value as! AXUIElement
        return {
            AXUIElementSetAttributeValue(
                element,
                kAXFocusedAttribute as CFString,
                kCFBooleanTrue
            )
        }
    }
}
