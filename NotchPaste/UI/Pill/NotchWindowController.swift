import AppKit
import Combine
import SwiftUI

/// 管理 NotchPanel 的生命周期 + 在 status 变化时切换 ignoresMouseEvents。
/// 复刻自 farouqaldori/vibe-notch (Apache 2.0)。
final class NotchWindowController: NSWindowController {

    let viewModel: NotchViewModel
    let panelVM: PanelViewModel
    private var cancellables = Set<AnyCancellable>()

    init(
        screen: NSScreen,
        panelVM: PanelViewModel,
        onRequestPermission: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        let screenFrame = screen.frame
        let notchSize = screen.notchSize

        // 窗口横跨整屏宽度，高度 750pt 容纳打开后的面板
        let windowHeight: CGFloat = 750
        let windowFrame = NSRect(
            x: screenFrame.origin.x,
            y: screenFrame.maxY - windowHeight,
            width: screenFrame.width,
            height: windowHeight
        )

        // 物理刘海在窗口内的局部 rect（窗口顶部居中）
        let deviceNotchRect = CGRect(
            x: (screenFrame.width - notchSize.width) / 2,
            y: 0,
            width: notchSize.width,
            height: notchSize.height
        )

        self.panelVM = panelVM
        self.viewModel = NotchViewModel(
            deviceNotchRect: deviceNotchRect,
            screenRect: screenFrame,
            windowHeight: windowHeight,
            hasPhysicalNotch: screen.hasPhysicalNotch
        )

        let panel = NotchPanel(contentRect: windowFrame)
        // 注入键盘事件处理器（opened 态生效）
        panel.keyHandler = NotchPanelKeyHandler(panelVM: panelVM, notchVM: viewModel)
        super.init(window: panel)

        let host = NSHostingController(
            rootView: NotchView(
                viewModel: viewModel,
                panelVM: panelVM,
                onRequestPermission: onRequestPermission,
                onQuit: onQuit
            )
        )
        panel.contentViewController = host
        panel.setFrame(windowFrame, display: true)

        // status 切换 → ignoresMouseEvents 切换
        viewModel.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak panel] status in
                switch status {
                case .opened:
                    panel?.ignoresMouseEvents = false
                    NSApp.activate(ignoringOtherApps: false)
                    panel?.makeKey()
                case .closed:
                    panel?.ignoresMouseEvents = true
                }
            }
            .store(in: &cancellables)

        panel.ignoresMouseEvents = true
    }

    @MainActor required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
