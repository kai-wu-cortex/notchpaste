import AppKit
import Carbon.HIToolbox

/// 透明 NSPanel：覆盖整屏顶部。窗口本身 ignoresMouseEvents，hover/click 由 EventMonitors 全局监听。
/// 复刻自 farouqaldori/vibe-notch (Apache 2.0)。
///
/// 键盘事件：用 NSEvent.addLocalMonitorForEvents 在事件分发链最前端拦截。
/// 这比 override `keyDown` 更可靠 —— SwiftUI 的 TextField 会吃掉 keyDown，
/// 等不到 panel.keyDown 触发；local monitor 在 TextField 之前。
final class NotchPanel: NSPanel {

    /// opened 态下的键盘事件处理器。controller 注入。
    var keyHandler: NotchPanelKeyHandler? {
        didSet { installKeyMonitorIfNeeded() }
    }

    private var keyMonitor: Any?

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true

        isOpaque = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        backgroundColor = .clear
        hasShadow = false
        isMovable = false

        collectionBehavior = [
            .fullScreenAuxiliary,
            .stationary,
            .canJoinAllSpaces,
            .ignoresCycle
        ]

        // 高于菜单栏，盖住物理刘海
        level = .mainMenu + 3

        allowsToolTipsWhenApplicationIsInactive = true

        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    deinit {
        if let m = keyMonitor {
            NSEvent.removeMonitor(m)
        }
    }

    private func installKeyMonitorIfNeeded() {
        guard keyMonitor == nil else { return }
        // local monitor：仅本进程的事件；这里不需要全局，免得在我们关闭时还吃别人的键。
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self,
                  let h = self.keyHandler,
                  // 仅当我们的 panel 是 key 时（即 opened 态）才参与
                  self.isKeyWindow else { return event }
            if h.handle(event) {
                return nil // 吞掉
            }
            return event
        }
    }
}

/// 面板键盘事件处理。在 opened 态把按键映射到 PanelViewModel / NotchViewModel 操作。
@MainActor
final class NotchPanelKeyHandler {
    let panelVM: PanelViewModel
    let notchVM: NotchViewModel
    let preferences: PreferencesStore

    init(panelVM: PanelViewModel, notchVM: NotchViewModel, preferences: PreferencesStore = .shared) {
        self.panelVM = panelVM
        self.notchVM = notchVM
        self.preferences = preferences
    }

    /// 返回 true 表示已处理事件并应吞掉；返回 false 让事件继续派发到 TextField 等。
    func handle(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let keyCode = Int(event.keyCode)

        // ⇧⌘P：全局优先级最高 —— 切换隐私模式
        if mods == [.command, .shift], keyCode == kVK_ANSI_P {
            preferences.monitoringEnabled.toggle()
            return true
        }

        // 设置态：把按键完全交给 SwiftUI（包括录制快捷键的 KeyCaptureView）
        guard notchVM.contentType == .list else { return false }

        // 全局可用导航键
        switch keyCode {
        case kVK_UpArrow:
            panelVM.selectionUp()
            return true
        case kVK_DownArrow:
            panelVM.selectionDown()
            return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            panelVM.commitSelection()
            return true
        case kVK_Escape:
            notchVM.notchClose()
            return true
        default:
            break
        }

        // Tab / Shift+Tab 分类切换
        if keyCode == kVK_Tab {
            if mods == [.shift] {
                panelVM.previousCategory()
                return true
            } else if mods.isEmpty {
                panelVM.nextCategory()
                return true
            }
        }

        // Cmd+1..6 直达
        if mods == [.command] {
            let categoryByDigit: [Int: ClipboardStore.Category] = [
                kVK_ANSI_1: .all,
                kVK_ANSI_2: .favorite,
                kVK_ANSI_3: .text,
                kVK_ANSI_4: .image,
                kVK_ANSI_5: .url,
                kVK_ANSI_6: .file
            ]
            if let cat = categoryByDigit[keyCode] {
                panelVM.category = cat
                return true
            }
        }

        return false
    }
}
