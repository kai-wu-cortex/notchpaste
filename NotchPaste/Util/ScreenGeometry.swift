import Foundation
import AppKit

/// 刘海周围空间的几何计算。所有方法都是纯函数，便于单测。
enum ScreenGeometry {

    enum NotchSide {
        case left, right
    }

    /// 根据 NSScreen 的辅助区域推断刘海矩形（屏幕坐标系，y 向上）。
    /// 在带刘海的 Mac 上，`auxiliaryTopLeftArea` / `auxiliaryTopRightArea` 是菜单栏被刘海切开的两段。
    /// 不带刘海时这两个属性返回 nil。
    static func notchFrame(
        screenFrame: NSRect,
        auxiliaryTopLeftArea: NSRect?,
        auxiliaryTopRightArea: NSRect?
    ) -> NSRect? {
        guard let left = auxiliaryTopLeftArea,
              let right = auxiliaryTopRightArea else {
            return nil
        }
        let x = left.maxX
        let width = right.minX - left.maxX
        guard width > 0 else { return nil }
        return NSRect(
            x: x,
            y: left.minY,
            width: width,
            height: left.height
        )
    }

    /// 给定刘海矩形和 pill 尺寸，计算 pill 应放置的 frame（v0.3 避让用：放刘海一侧）。
    static func pillFrame(
        side: NotchSide,
        notch: NSRect,
        pillSize: NSSize
    ) -> NSRect {
        let y = notch.maxY - pillSize.height
        let x: CGFloat
        switch side {
        case .right: x = notch.maxX
        case .left:  x = notch.minX - pillSize.width
        }
        return NSRect(x: x, y: y, width: pillSize.width, height: pillSize.height)
    }

    /// "覆盖刘海"形态的窗口 frame（v0.1 默认）：窗口横跨**整个屏幕宽度**、贴齐屏幕物理顶部，
    /// 高度足以容纳膨胀动画。由 SwiftUI 视图把 pill 渲染到中心 + offset 调整到刘海左/右侧。
    /// 横跨整屏宽是为了 avoidance 形态平移时不被窗口边界截断。
    static func notchOverlayWindowFrame(
        screenFrame: NSRect,
        notch: NSRect,
        maxExtraWidth: CGFloat = 120,
        maxExtraHeight: CGFloat = 60
    ) -> NSRect {
        let winH = notch.height + maxExtraHeight
        return NSRect(
            x: screenFrame.minX,
            y: screenFrame.maxY - winH,
            width: screenFrame.width,
            height: winH
        )
    }

    /// 主屏快捷：拿到刘海尺寸 + 覆盖刘海的窗口 frame。
    static func currentNotchOverlay() -> (notchSize: NSSize, windowFrame: NSRect)? {
        guard let screen = NSScreen.main else { return nil }
        guard let notch = notchFrame(
            screenFrame: screen.frame,
            auxiliaryTopLeftArea: screen.auxiliaryTopLeftArea,
            auxiliaryTopRightArea: screen.auxiliaryTopRightArea
        ) else { return nil }
        let frame = notchOverlayWindowFrame(screenFrame: screen.frame, notch: notch)
        return (NSSize(width: notch.width, height: notch.height), frame)
    }

    /// 计算面板从刘海"展开"出来的 frame：窗口顶端贴齐屏幕物理顶部，水平居中刘海中线。
    /// 这样面板从刘海里"长"出来，与覆盖刘海的 pill 视觉连贯。
    static func currentDropdownPanelFrame(panelSize: NSSize) -> NSRect? {
        guard let screen = NSScreen.main else { return nil }
        let centerX: CGFloat
        if let notch = notchFrame(
            screenFrame: screen.frame,
            auxiliaryTopLeftArea: screen.auxiliaryTopLeftArea,
            auxiliaryTopRightArea: screen.auxiliaryTopRightArea
        ) {
            centerX = notch.midX
        } else {
            centerX = screen.frame.midX
        }
        return NSRect(
            x: centerX - panelSize.width / 2,
            y: screen.frame.maxY - panelSize.height,
            width: panelSize.width,
            height: panelSize.height
        )
    }

    /// 用主屏当前几何快速算出右侧 pill frame（v0.3 避让用，保留原 API）。
    static func currentRightPillFrame(pillSize: NSSize) -> NSRect? {
        guard let screen = NSScreen.main else { return nil }
        guard let notch = notchFrame(
            screenFrame: screen.frame,
            auxiliaryTopLeftArea: screen.auxiliaryTopLeftArea,
            auxiliaryTopRightArea: screen.auxiliaryTopRightArea
        ) else { return nil }
        return pillFrame(side: .right, notch: notch, pillSize: pillSize)
    }
}
