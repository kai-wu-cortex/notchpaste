import AppKit
import SwiftUI
import Carbon.HIToolbox

/// 展开后的剪贴板面板窗口。失焦自动关闭；处理键盘 ↑/↓/Enter/Esc。
final class PanelWindow: NSPanel {

    private weak var viewModel: PanelViewModel?

    init(contentSize: NSSize, viewModel: PanelViewModel) {
        super.init(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.viewModel = viewModel
        self.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true
        self.isMovable = false
        self.becomesKeyOnlyIfNeeded = false

        let host = NSHostingView(rootView: PanelView(viewModel: viewModel))
        host.frame = NSRect(origin: .zero, size: contentSize)
        host.autoresizingMask = [.width, .height]
        self.contentView = host
    }

    override var canBecomeKey: Bool { true }     // 接受按键事件
    override var canBecomeMain: Bool { false }

    override func resignKey() {
        super.resignKey()
        // 失焦自动关闭
        DispatchQueue.main.async { [weak self] in self?.close() }
    }

    override func keyDown(with event: NSEvent) {
        guard let vm = viewModel else { return super.keyDown(with: event) }
        switch Int(event.keyCode) {
        case kVK_UpArrow:
            vm.selectionUp()
        case kVK_DownArrow:
            vm.selectionDown()
        case kVK_Return:
            // 先关再粘贴：让焦点回到原 app，再注入 ⌘V
            self.orderOut(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                vm.commitSelection()
            }
        case kVK_Escape:
            self.orderOut(nil)
        default:
            super.keyDown(with: event)
        }
    }
}
