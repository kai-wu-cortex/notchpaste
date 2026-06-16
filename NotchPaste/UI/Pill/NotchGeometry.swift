import CoreGraphics
import Foundation

/// 刘海窗口的几何计算 + hit-testing。纯 Sendable struct。
/// 复刻自 farouqaldori/vibe-notch (Apache 2.0)。
struct NotchGeometry: Sendable {
    /// 物理刘海在窗口内的局部坐标（窗口顶部居中）。
    let deviceNotchRect: CGRect
    /// 屏幕全幅 frame（用于将窗口定位到屏幕顶部）。
    let screenRect: CGRect
    /// 窗口高度（够大以容纳打开后的面板内容）。
    let windowHeight: CGFloat

    /// 物理刘海在屏幕坐标系（y 向上）中的 rect。
    var notchScreenRect: CGRect {
        CGRect(
            x: screenRect.midX - deviceNotchRect.width / 2,
            y: screenRect.maxY - deviceNotchRect.height,
            width: deviceNotchRect.width,
            height: deviceNotchRect.height
        )
    }

    /// 打开态面板在屏幕坐标系中的 rect。
    func openedScreenRect(for size: CGSize) -> CGRect {
        let width = size.width
        let height = size.height
        return CGRect(
            x: screenRect.midX - width / 2,
            y: screenRect.maxY - height,
            width: width,
            height: height
        )
    }

    /// 命中测试：点击/移动是否落在刘海区域（含 padding 让交互更宽容）。
    func isPointInNotch(_ point: CGPoint) -> Bool {
        notchScreenRect.insetBy(dx: -10, dy: -5).contains(point)
    }

    /// 命中测试：点击是否落在打开态面板内。
    func isPointInOpenedPanel(_ point: CGPoint, size: CGSize) -> Bool {
        openedScreenRect(for: size).contains(point)
    }

    func isPointOutsidePanel(_ point: CGPoint, size: CGSize) -> Bool {
        !openedScreenRect(for: size).contains(point)
    }
}
