import Foundation
import AppKit

/// 刘海周围空间的几何计算。所有方法都是纯函数，便于单测。
enum ScreenGeometry {

    enum NotchSide {
        case left, right
    }

    /// 根据 NSScreen 的辅助区域推断刘海矩形。
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

    /// 给定刘海矩形和 pill 尺寸，计算 pill 应放置的 frame。
    /// pill 顶端对齐刘海顶端，紧贴刘海一侧。
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

    /// 用主屏当前几何快速算出右侧 pill frame。
    /// 主屏无刘海时返回 nil（v0.1 不支持非刘海机型，调用方需要做菜单栏 fallback —— v0.3 才接入）。
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
