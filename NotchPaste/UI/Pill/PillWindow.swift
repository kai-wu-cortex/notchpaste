import AppKit
import SwiftUI

/// 承载 PillView 的 NSPanel：无边框、不抢焦、置顶、跨 Space 常驻。
final class PillWindow: NSPanel {

    init(contentSize: NSSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.isMovable = false
        self.hidesOnDeactivate = false
    }

    /// SwiftUI 内容容器。调用方传入闭包构造视图。
    func setContent<V: View>(_ view: V) {
        let host = NSHostingView(rootView: view)
        host.translatesAutoresizingMaskIntoConstraints = true
        host.frame = NSRect(origin: .zero, size: self.frame.size)
        host.autoresizingMask = [.width, .height]
        self.contentView = host
    }

    /// 不接受 keyWindow，避免抢焦点。
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
