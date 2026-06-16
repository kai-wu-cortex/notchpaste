import AppKit
import Combine
import SwiftUI

/// 刘海窗口的状态机。简化自 vibe-notch (Apache 2.0)：
/// - .closed：默认；与物理刘海完全同形
/// - .opened：展开成剪贴板面板
///
/// hover 1s 自动展开；点击外部关闭；点击刘海本身打开。
@MainActor
final class NotchViewModel: ObservableObject {

    enum NotchStatus: Equatable {
        case closed
        case opened
    }

    enum NotchOpenReason {
        case click
        case hover
        case copyHint
        case unknown
    }

    /// 打开后展示的内容类型。`.list` 是默认剪贴板列表；`.settings` 是设置面板。
    enum ContentType: Equatable {
        case list
        case settings
    }

    // MARK: - Published State

    @Published var status: NotchStatus = .closed
    @Published var openReason: NotchOpenReason = .unknown
    @Published var isHovering: Bool = false
    @Published var contentType: ContentType = .list

    /// 复制事件触发的临时预览（外部 1.2-2s 后清空）。
    /// 区分 text / file / image 让 UI 渲染不同样式。
    enum CopyHint: Equatable {
        case text(String)
        case file(urls: [URL])
        case image(Data)
    }

    @Published var copyHint: CopyHint? = nil

    /// 历史条数（pill 默认态不显示，hover 时显示）。
    @Published var itemCount: Int = 0

    /// 检测到其他刘海 app 运行 → 缩成左侧小药丸。
    @Published var avoidanceMode: Bool = false

    /// 隐私模式：监听是否启用（由 AppDelegate 同步自 PreferencesStore）。
    /// 关闭时刘海上方显示一个红点提示用户。
    @Published var monitoringEnabled: Bool = true

    /// 打开面板时记录的原粘贴目标；粘贴前恢复它，让 ⌘V 注入到正确输入框。
    var previousPasteTarget: PasteTarget?

    // MARK: - Geometry

    let geometry: NotchGeometry
    let hasPhysicalNotch: Bool

    var deviceNotchRect: CGRect { geometry.deviceNotchRect }
    var screenRect: CGRect { geometry.screenRect }
    var windowHeight: CGFloat { geometry.windowHeight }

    /// 打开态面板尺寸。
    let openedSize = CGSize(width: 460, height: 420)

    // MARK: - Animations (与 vibe-notch 一致的 spring 配置)

    static let openAnim = Animation.spring(response: 0.42, dampingFraction: 0.8, blendDuration: 0)
    static let closeAnim = Animation.spring(response: 0.45, dampingFraction: 1.0, blendDuration: 0)

    // MARK: - Private

    private var cancellables = Set<AnyCancellable>()
    private let events = EventMonitors.shared
    private var hoverTimer: DispatchWorkItem?

    // MARK: - Init

    init(deviceNotchRect: CGRect, screenRect: CGRect, windowHeight: CGFloat, hasPhysicalNotch: Bool) {
        self.geometry = NotchGeometry(
            deviceNotchRect: deviceNotchRect,
            screenRect: screenRect,
            windowHeight: windowHeight
        )
        self.hasPhysicalNotch = hasPhysicalNotch
        setupEventHandlers()
    }

    // MARK: - Event handling

    private func setupEventHandlers() {
        events.mouseLocation
            .throttle(for: .milliseconds(50), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] location in self?.handleMouseMove(location) }
            .store(in: &cancellables)

        events.mouseDown
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.handleMouseDown() }
            .store(in: &cancellables)
    }

    private func handleMouseMove(_ location: CGPoint) {
        let inNotch = geometry.isPointInNotch(location)
        let inOpened = status == .opened && geometry.isPointInOpenedPanel(location, size: openedSize)
        let newHovering = inNotch || inOpened

        guard newHovering != isHovering else { return }
        isHovering = newHovering

        hoverTimer?.cancel()
        hoverTimer = nil

        // hover 1s 自动展开（仅 closed 态；可被 PreferencesStore.hoverToExpand 关闭）
        if isHovering && status == .closed && PreferencesStore.shared.hoverToExpand {
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.isHovering else { return }
                self.notchOpen(reason: .hover)
            }
            hoverTimer = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
        }
    }

    private func handleMouseDown() {
        let location = NSEvent.mouseLocation
        switch status {
        case .opened:
            if geometry.isPointOutsidePanel(location, size: openedSize) {
                notchClose()
                repostClickAt(location)
            } else if geometry.notchScreenRect.contains(location) {
                notchClose()
            }
        case .closed:
            if geometry.isPointInNotch(location) {
                notchOpen(reason: .click)
            }
        }
    }

    /// 重新派发点击：避免我们关闭面板时把用户的点击吞掉。
    private func repostClickAt(_ location: CGPoint) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard let screen = NSScreen.main else { return }
            let h = screen.frame.height
            let cgPoint = CGPoint(x: location.x, y: h - location.y)
            for type in [CGEventType.leftMouseDown, .leftMouseUp] {
                if let ev = CGEvent(
                    mouseEventSource: nil,
                    mouseType: type,
                    mouseCursorPosition: cgPoint,
                    mouseButton: .left
                ) {
                    ev.post(tap: .cghidEventTap)
                }
            }
        }
    }

    // MARK: - Actions

    func notchOpen(reason: NotchOpenReason = .unknown) {
        // 仅在从 closed → opened 转换时记录原粘贴目标。
        // 之后再调用 notchOpen（如 hover 后又点击）不能覆盖：
        // 因为此时 panel 已经 makeKey，frontmostApplication 可能是我们自己。
        if status == .closed {
            previousPasteTarget = PasteTarget.capture()
        }
        openReason = reason
        status = .opened
    }

    func notchClose() {
        status = .closed
        contentType = .list
    }

    func toggle() {
        switch status {
        case .opened: notchClose()
        case .closed: notchOpen(reason: .click)
        }
    }
}
