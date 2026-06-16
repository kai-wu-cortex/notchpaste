import AppKit
import Combine

/// 全局鼠标事件监听器。窗口 `ignoresMouseEvents = true` 时，hover/click 落不到窗口里，
/// 只能用 NSEvent 的全局 monitor 抓 —— 这是 vibe-notch / NotchDrop 的通用做法。
///
/// 单例：一个 app 只要一组 monitor 就够了；订阅者通过 Combine publishers 接收。
@MainActor
final class EventMonitors {
    static let shared = EventMonitors()

    /// 全屏鼠标位置（屏幕坐标系，y 向上）。throttle 由订阅方处理。
    let mouseLocation = PassthroughSubject<CGPoint, Never>()

    /// 鼠标按下（左键）。值不重要，仅作为触发器。
    let mouseDown = PassthroughSubject<Void, Never>()

    private var moveMonitor: Any?
    private var localMoveMonitor: Any?
    private var downMonitor: Any?
    private var localDownMonitor: Any?

    private init() {
        // mouseMoved 全局监听
        moveMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            self?.emitMouseLocation()
        }
        // 同时加 local 防止焦点在我们 app 时漏事件
        localMoveMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            self?.emitMouseLocation()
            return event
        }

        downMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            self?.mouseDown.send(())
        }
        localDownMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            self?.mouseDown.send(())
            return event
        }
    }

    private func emitMouseLocation() {
        mouseLocation.send(NSEvent.mouseLocation)
    }

    deinit {
        [moveMonitor, localMoveMonitor, downMonitor, localDownMonitor].forEach {
            if let m = $0 { NSEvent.removeMonitor(m) }
        }
    }
}
