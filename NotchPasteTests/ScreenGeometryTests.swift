import Testing
import AppKit
@testable import NotchPaste

@Suite("ScreenGeometry")
struct ScreenGeometryTests {

    /// 1512×982 大致是 14" MBP 的逻辑分辨率。刘海宽度约 200pt，居中在屏幕顶部。
    @Test("notchFrame returns nil for screens without notch (auxiliaryTopLeftArea zero)")
    func noNotchReturnsNil() {
        let frame = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let result = ScreenGeometry.notchFrame(
            screenFrame: frame,
            auxiliaryTopLeftArea: nil,
            auxiliaryTopRightArea: nil
        )
        #expect(result == nil)
    }

    @Test("notchFrame returns notch rect when auxiliary areas are present")
    func notchPresent() {
        let screen = NSRect(x: 0, y: 0, width: 1512, height: 982)
        // 在带刘海机型上，auxiliaryTopLeftArea 是刘海左侧菜单栏区域
        let leftAux = NSRect(x: 0, y: 950, width: 656, height: 32)
        let rightAux = NSRect(x: 856, y: 950, width: 656, height: 32)
        let notch = ScreenGeometry.notchFrame(
            screenFrame: screen,
            auxiliaryTopLeftArea: leftAux,
            auxiliaryTopRightArea: rightAux
        )
        #expect(notch != nil)
        #expect(notch?.minX == 656)
        #expect(notch?.maxX == 856)
        #expect(notch?.width == 200)
    }

    @Test("pillFrame on right side sits flush against notch right edge")
    func pillFrameRight() {
        let notch = NSRect(x: 656, y: 950, width: 200, height: 32)
        let pill = ScreenGeometry.pillFrame(
            side: .right,
            notch: notch,
            pillSize: NSSize(width: 60, height: 24)
        )
        #expect(pill.minX == notch.maxX)             // 紧贴刘海右缘
        #expect(pill.maxX == notch.maxX + 60)
        #expect(pill.height == 24)
        #expect(pill.maxY == notch.maxY)             // 顶端对齐刘海顶端
    }

    @Test("pillFrame on left side sits flush against notch left edge")
    func pillFrameLeft() {
        let notch = NSRect(x: 656, y: 950, width: 200, height: 32)
        let pill = ScreenGeometry.pillFrame(
            side: .left,
            notch: notch,
            pillSize: NSSize(width: 60, height: 24)
        )
        #expect(pill.maxX == notch.minX)
        #expect(pill.minX == notch.minX - 60)
        #expect(pill.maxY == notch.maxY)
    }

    @Test("notchOverlayWindowFrame spans full screen width and sits flush to screen top")
    func notchOverlayFrame() {
        let screen = NSRect(x: 0, y: 0, width: 1512, height: 982)
        let notch = NSRect(x: 656, y: 950, width: 200, height: 32)
        let frame = ScreenGeometry.notchOverlayWindowFrame(
            screenFrame: screen,
            notch: notch,
            maxExtraWidth: 100,
            maxExtraHeight: 60
        )
        // 横跨整个屏幕宽度（让 avoidance 形态平移不被截断）
        #expect(frame.width == screen.width)
        #expect(frame.minX == screen.minX)
        // 顶端贴齐屏幕物理顶部
        #expect(frame.maxY == screen.maxY)
        #expect(frame.height == notch.height + 60)
    }
}
