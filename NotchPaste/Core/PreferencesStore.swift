import Foundation
import Combine

enum AgentActivityIconStyle: String, CaseIterable, Identifiable {
    case spinner
    case sparkles
    case bolt
    case terminal
    case pulse
    case symbol
    case cascadeSymbol
    case command
    case braces
    case cpu
    case network
    case wand
    case paperplane
    case cursor
    case scope
    case waveform

    var id: String { rawValue }

    var isPixelSymbol: Bool {
        switch self {
        case .symbol, .cascadeSymbol:
            return true
        default:
            return false
        }
    }

    var title: String {
        switch self {
        case .spinner: return "旋转"
        case .sparkles: return "闪光"
        case .bolt: return "闪电"
        case .terminal: return "终端"
        case .pulse: return "脉冲"
        case .symbol: return "Symbol"
        case .cascadeSymbol: return "Cascade"
        case .command: return "Command"
        case .braces: return "Code"
        case .cpu: return "CPU"
        case .network: return "Network"
        case .wand: return "Wand"
        case .paperplane: return "Send"
        case .cursor: return "Cursor"
        case .scope: return "Scope"
        case .waveform: return "Wave"
        }
    }

    var systemImageName: String {
        switch self {
        case .spinner: return "arrow.triangle.2.circlepath"
        case .sparkles: return "sparkles"
        case .bolt: return "bolt.fill"
        case .terminal: return "apple.terminal.fill"
        case .pulse: return "circle.fill"
        case .symbol: return "square.grid.3x3.fill"
        case .cascadeSymbol: return "chevron.down"
        case .command: return "command"
        case .braces: return "curlybraces"
        case .cpu: return "cpu"
        case .network: return "dot.radiowaves.left.and.right"
        case .wand: return "wand.and.stars"
        case .paperplane: return "paperplane.fill"
        case .cursor: return "cursorarrow.rays"
        case .scope: return "scope"
        case .waveform: return "waveform"
        }
    }
}

enum AgentActivityIconPosition: String, CaseIterable, Identifiable {
    case leading
    case center
    case trailing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .leading: return "左侧"
        case .center: return "居中"
        case .trailing: return "右侧"
        }
    }

    var systemImageName: String {
        switch self {
        case .leading: return "align.horizontal.left.fill"
        case .center: return "align.horizontal.center.fill"
        case .trailing: return "align.horizontal.right.fill"
        }
    }
}

enum AgentActivityIconEffect: String, CaseIterable, Identifiable {
    case none
    case glow
    case edgeBloom
    case breathe
    case spin
    case bounce

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "关闭"
        case .glow: return "发光"
        case .edgeBloom: return "边缘泛光"
        case .breathe: return "呼吸"
        case .spin: return "旋转"
        case .bounce: return "跳动"
        }
    }

    var systemImageName: String {
        switch self {
        case .none: return "minus.circle"
        case .glow: return "circle.hexagongrid.circle"
        case .edgeBloom: return "sparkle.magnifyingglass"
        case .breathe: return "arrow.up.left.and.down.right.magnifyingglass"
        case .spin: return "arrow.triangle.2.circlepath"
        case .bounce: return "arrow.up.and.down"
        }
    }
}

/// UserDefaults 包装，集中管理用户偏好。线程安全，可观察。
final class PreferencesStore: ObservableObject {
    static let shared = PreferencesStore()

    private let defaults: UserDefaults

    private enum Key {
        static let maxItems = "NotchPaste.maxItems"
        static let autoPasteEnabled = "NotchPaste.autoPasteEnabled"
        static let hoverToExpand = "NotchPaste.hoverToExpand"
        static let closeAfterCopy = "NotchPaste.closeAfterCopy"
        static let monitoringEnabled = "NotchPaste.monitoringEnabled"
        static let shortcutId = "NotchPaste.shortcutId"
        static let agentRunningIconStyle = "NotchPaste.agentRunningIconStyle"
        static let agentAttentionIconStyle = "NotchPaste.agentAttentionIconStyle"
        static let agentActivityIconPosition = "NotchPaste.agentActivityIconPosition"
        static let agentActivityIconSize = "NotchPaste.agentActivityIconSize"
        static let agentActivityIconOffsetX = "NotchPaste.agentActivityIconOffsetX"
        static let agentActivityIconOffsetY = "NotchPaste.agentActivityIconOffsetY"
        static let agentActivityIconEffect = "NotchPaste.agentActivityIconEffect"
        static let agentRunningCustomIconPath = "NotchPaste.agentRunningCustomIconPath"
        static let agentAttentionCustomIconPath = "NotchPaste.agentAttentionCustomIconPath"
        static let agentRunningNotchWidthAdjustment = "NotchPaste.agentRunningNotchWidthAdjustment"
        static let agentRunningNotchHeightAdjustment = "NotchPaste.agentRunningNotchHeightAdjustment"
        static let agentAttentionNotchWidthAdjustment = "NotchPaste.agentAttentionNotchWidthAdjustment"
        static let agentAttentionNotchHeightAdjustment = "NotchPaste.agentAttentionNotchHeightAdjustment"
    }

    @Published var maxItems: Int {
        didSet { defaults.set(maxItems, forKey: Key.maxItems) }
    }

    /// 复制后是否自动注入 ⌘V 到原应用。
    @Published var autoPasteEnabled: Bool {
        didSet { defaults.set(autoPasteEnabled, forKey: Key.autoPasteEnabled) }
    }

    /// 鼠标悬停 1s 是否自动展开面板。关掉后只能点击 / 快捷键打开。
    @Published var hoverToExpand: Bool {
        didSet { defaults.set(hoverToExpand, forKey: Key.hoverToExpand) }
    }

    /// 选择历史项后是否自动收起面板。关掉则面板保持打开方便连续复制。
    @Published var closeAfterCopy: Bool {
        didSet { defaults.set(closeAfterCopy, forKey: Key.closeAfterCopy) }
    }

    /// 隐私模式：剪贴板监听总开关。关闭后不再记录新的剪贴内容。
    @Published var monitoringEnabled: Bool {
        didSet { defaults.set(monitoringEnabled, forKey: Key.monitoringEnabled) }
    }

    /// 当前快捷键的序列化 id。
    @Published var shortcut: GlobalShortcut {
        didSet { defaults.set(shortcut.id, forKey: Key.shortcutId) }
    }

    /// Agent 正在运行时，closed 刘海里显示的动态图标。
    @Published var agentRunningIconStyle: AgentActivityIconStyle {
        didSet { defaults.set(agentRunningIconStyle.rawValue, forKey: Key.agentRunningIconStyle) }
    }

    /// Agent 需要批准/询问/跳回时，closed 刘海里显示的动态图标。
    @Published var agentAttentionIconStyle: AgentActivityIconStyle {
        didSet { defaults.set(agentAttentionIconStyle.rawValue, forKey: Key.agentAttentionIconStyle) }
    }

    /// Agent 状态图标在 closed 刘海里的位置。
    @Published var agentActivityIconPosition: AgentActivityIconPosition {
        didSet { defaults.set(agentActivityIconPosition.rawValue, forKey: Key.agentActivityIconPosition) }
    }

    /// Agent 状态图标尺寸，单位 pt，设置页按像素级步进调整。
    @Published var agentActivityIconSize: Double {
        didSet { defaults.set(agentActivityIconSize, forKey: Key.agentActivityIconSize) }
    }

    /// Agent 状态图标水平偏移，单位 pt。
    @Published var agentActivityIconOffsetX: Double {
        didSet { defaults.set(agentActivityIconOffsetX, forKey: Key.agentActivityIconOffsetX) }
    }

    /// Agent 状态图标垂直偏移，单位 pt。
    @Published var agentActivityIconOffsetY: Double {
        didSet { defaults.set(agentActivityIconOffsetY, forKey: Key.agentActivityIconOffsetY) }
    }

    /// Agent 状态图标动效。
    @Published var agentActivityIconEffect: AgentActivityIconEffect {
        didSet { defaults.set(agentActivityIconEffect.rawValue, forKey: Key.agentActivityIconEffect) }
    }

    /// 运行中状态的用户自定义图标文件路径。nil 时使用内置动态图标。
    @Published var agentRunningCustomIconPath: String? {
        didSet { setOptional(agentRunningCustomIconPath, forKey: Key.agentRunningCustomIconPath) }
    }

    /// 待处理状态的用户自定义图标文件路径。nil 时使用内置动态图标。
    @Published var agentAttentionCustomIconPath: String? {
        didSet { setOptional(agentAttentionCustomIconPath, forKey: Key.agentAttentionCustomIconPath) }
    }

    /// 运行中 closed 刘海宽度微调，单位 pt。
    @Published var agentRunningNotchWidthAdjustment: Double {
        didSet {
            defaults.set(agentRunningNotchWidthAdjustment, forKey: Key.agentRunningNotchWidthAdjustment)
            if agentAttentionNotchWidthAdjustment != agentRunningNotchWidthAdjustment {
                agentAttentionNotchWidthAdjustment = agentRunningNotchWidthAdjustment
            }
        }
    }

    /// 运行中 closed 刘海高度微调，单位 pt。
    @Published var agentRunningNotchHeightAdjustment: Double {
        didSet { defaults.set(agentRunningNotchHeightAdjustment, forKey: Key.agentRunningNotchHeightAdjustment) }
    }

    /// 待处理 closed 刘海宽度微调，单位 pt。
    @Published var agentAttentionNotchWidthAdjustment: Double {
        didSet {
            if agentAttentionNotchWidthAdjustment != agentRunningNotchWidthAdjustment {
                agentAttentionNotchWidthAdjustment = agentRunningNotchWidthAdjustment
            }
            defaults.set(agentAttentionNotchWidthAdjustment, forKey: Key.agentAttentionNotchWidthAdjustment)
        }
    }

    /// 待处理 closed 刘海高度微调，单位 pt。
    @Published var agentAttentionNotchHeightAdjustment: Double {
        didSet { defaults.set(agentAttentionNotchHeightAdjustment, forKey: Key.agentAttentionNotchHeightAdjustment) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedMaxItems: Int = (defaults.object(forKey: Key.maxItems) as? Int) ?? 200
        let storedAutoPaste: Bool = (defaults.object(forKey: Key.autoPasteEnabled) as? Bool) ?? true
        let storedHover: Bool = (defaults.object(forKey: Key.hoverToExpand) as? Bool) ?? true
        let storedClose: Bool = (defaults.object(forKey: Key.closeAfterCopy) as? Bool) ?? true
        let storedMonitor: Bool = (defaults.object(forKey: Key.monitoringEnabled) as? Bool) ?? true
        let storedShortcutId: String = (defaults.object(forKey: Key.shortcutId) as? String) ?? GlobalShortcut.default.id
        let storedRunningIcon = AgentActivityIconStyle(
            rawValue: (defaults.object(forKey: Key.agentRunningIconStyle) as? String) ?? ""
        ) ?? .spinner
        let storedAttentionIcon = AgentActivityIconStyle(
            rawValue: (defaults.object(forKey: Key.agentAttentionIconStyle) as? String) ?? ""
        ) ?? .spinner
        let storedIconPosition = AgentActivityIconPosition(
            rawValue: (defaults.object(forKey: Key.agentActivityIconPosition) as? String) ?? ""
        ) ?? .leading
        let storedIconSize = (defaults.object(forKey: Key.agentActivityIconSize) as? Double) ?? 18
        let storedIconOffsetX = (defaults.object(forKey: Key.agentActivityIconOffsetX) as? Double) ?? 0
        let storedIconOffsetY = (defaults.object(forKey: Key.agentActivityIconOffsetY) as? Double) ?? 0
        let storedIconEffect = AgentActivityIconEffect(
            rawValue: (defaults.object(forKey: Key.agentActivityIconEffect) as? String) ?? ""
        ) ?? .glow
        let storedRunningCustomIconPath = defaults.object(forKey: Key.agentRunningCustomIconPath) as? String
        let storedAttentionCustomIconPath = defaults.object(forKey: Key.agentAttentionCustomIconPath) as? String
        let storedRunningWidth = (defaults.object(forKey: Key.agentRunningNotchWidthAdjustment) as? Double) ?? 0
        let storedRunningHeight = (defaults.object(forKey: Key.agentRunningNotchHeightAdjustment) as? Double) ?? 0
        let storedAttentionHeight = (defaults.object(forKey: Key.agentAttentionNotchHeightAdjustment) as? Double) ?? 0

        self.maxItems = storedMaxItems
        self.autoPasteEnabled = storedAutoPaste
        self.hoverToExpand = storedHover
        self.closeAfterCopy = storedClose
        self.monitoringEnabled = storedMonitor
        self.shortcut = GlobalShortcut.fromConfig(storedShortcutId)
        self.agentRunningIconStyle = storedRunningIcon
        self.agentAttentionIconStyle = storedAttentionIcon
        self.agentActivityIconPosition = storedIconPosition
        self.agentActivityIconSize = storedIconSize
        self.agentActivityIconOffsetX = storedIconOffsetX
        self.agentActivityIconOffsetY = storedIconOffsetY
        self.agentActivityIconEffect = storedIconEffect
        self.agentRunningCustomIconPath = storedRunningCustomIconPath
        self.agentAttentionCustomIconPath = storedAttentionCustomIconPath
        self.agentRunningNotchWidthAdjustment = storedRunningWidth
        self.agentRunningNotchHeightAdjustment = storedRunningHeight
        self.agentAttentionNotchWidthAdjustment = storedRunningWidth
        self.agentAttentionNotchHeightAdjustment = storedAttentionHeight
    }

    private func setOptional(_ value: String?, forKey key: String) {
        if let value, !value.isEmpty {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
