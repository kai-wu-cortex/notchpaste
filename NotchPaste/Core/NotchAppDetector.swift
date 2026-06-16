import Foundation
import AppKit
import Combine

/// 监听其他刘海类 app 的运行状态，让 NotchPaste 可以让位。
///
/// v0.1：仅检测一个已知 bundle id（Vibe Notch / Claude Island）。
/// v0.3 会扩展为完整白名单 + 用户可配置。
@MainActor
final class NotchAppDetector: ObservableObject {

    /// 已知占用刘海的 app bundle id 白名单。
    /// 出现在白名单 + 当前正在运行 → 视为"刘海被占用"。
    static let knownNotchAppBundleIDs: Set<String> = [
        "com.celestial.ClaudeIsland",     // Vibe Notch (旧称 ClaudeIsland)
        "lol.boring.notch",               // Boring.notch
        "com.lo.cas.dynamic-notch",       // NotchNook
        "com.alvarofierro.alcove"         // AlcoveX
    ]

    /// 当前是否检测到任意已知刘海 app 在运行。
    @Published private(set) var isOtherNotchAppRunning: Bool = false

    private var cancellables = Set<AnyCancellable>()
    private let workspace = NSWorkspace.shared

    init() {
        recompute()

        // 启动通知
        workspace.notificationCenter
            .publisher(for: NSWorkspace.didLaunchApplicationNotification)
            .sink { [weak self] _ in self?.recompute() }
            .store(in: &cancellables)

        // 终止通知
        workspace.notificationCenter
            .publisher(for: NSWorkspace.didTerminateApplicationNotification)
            .sink { [weak self] _ in self?.recompute() }
            .store(in: &cancellables)
    }

    /// 用 NSWorkspace.runningApplications 真实查一遍当前状态。
    /// 这种"全量重算"比维护增量集合更不容易出错，N 通常 <200。
    private func recompute() {
        let running = workspace.runningApplications.compactMap(\.bundleIdentifier)
        let occupied = running.contains { Self.knownNotchAppBundleIDs.contains($0) }
        if occupied != isOtherNotchAppRunning {
            isOtherNotchAppRunning = occupied
            AppLogger.app.info("NotchAppDetector: occupied=\(occupied, privacy: .public)")
        }
    }
}
