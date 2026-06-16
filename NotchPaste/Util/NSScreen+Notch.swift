import AppKit

/// NSScreen 扩展：精确刘海尺寸 + 内建显示器检测。
/// 复刻自 farouqaldori/vibe-notch (Apache 2.0)；本项目 MIT，保留作者署名。
extension NSScreen {

    /// 物理刘海尺寸。无刘海机型返回 fallback (224x38)。
    /// 计算方式参考 boring.notch：宽 = 屏幕宽 - 左右辅助区宽 + 4 偏移。
    var notchSize: CGSize {
        guard safeAreaInsets.top > 0 else {
            return CGSize(width: 224, height: 38)
        }

        let notchHeight = safeAreaInsets.top
        let fullWidth = frame.width
        let leftPadding = auxiliaryTopLeftArea?.width ?? 0
        let rightPadding = auxiliaryTopRightArea?.width ?? 0

        guard leftPadding > 0, rightPadding > 0 else {
            return CGSize(width: 180, height: notchHeight)
        }

        // +4 与 boring.notch 对齐
        let notchWidth = fullWidth - leftPadding - rightPadding + 4
        return CGSize(width: notchWidth, height: notchHeight)
    }

    /// 是否是内建显示器。
    var isBuiltinDisplay: Bool {
        guard let n = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return false
        }
        return CGDisplayIsBuiltin(n) != 0
    }

    /// 是否有物理刘海（摄像头切口）。
    var hasPhysicalNotch: Bool {
        safeAreaInsets.top > 0
    }

    /// 内建显示器（带刘海的 MacBook）；找不到就 main。
    static var builtin: NSScreen? {
        screens.first(where: \.isBuiltinDisplay) ?? .main
    }
}
