import Foundation
import Combine

enum AgentActivityIconStyle: String, CaseIterable, Identifiable {
    case none
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
    case lifeGrid
    case asciiPrompt
    case asciiScan
    case asciiPulse

    var id: String { rawValue }

    var isPixelSymbol: Bool {
        switch self {
        case .symbol, .cascadeSymbol, .lifeGrid:
            return true
        default:
            return false
        }
    }

    var isASCII: Bool {
        switch self {
        case .asciiPrompt, .asciiScan, .asciiPulse:
            return true
        default:
            return false
        }
    }

    var asciiFrames: [String] {
        switch self {
        case .asciiPrompt:
            return [">_", ">>", ">.", ">_"]
        case .asciiScan:
            return ["|..", ".|.", "..|", ".|."]
        case .asciiPulse:
            return ["..", ":.", "::", ".:"]
        default:
            return []
        }
    }

    var title: String {
        switch self {
        case .none: return "无图标"
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
        case .lifeGrid: return "Life 6x6"
        case .asciiPrompt: return "ASCII >_"
        case .asciiScan: return "ASCII Scan"
        case .asciiPulse: return "ASCII Pulse"
        }
    }

    var systemImageName: String {
        switch self {
        case .none: return "circle.slash"
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
        case .lifeGrid: return "square.grid.3x3.square"
        case .asciiPrompt: return "terminal"
        case .asciiScan: return "slider.horizontal.below.square.filled.and.square"
        case .asciiPulse: return "ellipsis"
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
    case flameWave
    case breathe
    case spin
    case bounce

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "关闭"
        case .glow: return "发光"
        case .edgeBloom: return "边缘泛光"
        case .flameWave: return "火焰波"
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
        case .flameWave: return "waveform.path.ecg.rectangle"
        case .breathe: return "arrow.up.left.and.down.right.magnifyingglass"
        case .spin: return "arrow.triangle.2.circlepath"
        case .bounce: return "arrow.up.and.down"
        }
    }
}

enum AgentActivityNotchDisplayMode: String, CaseIterable, Identifiable {
    case detailed
    case simple

    var id: String { rawValue }

    var title: String {
        switch self {
        case .detailed: return "详细"
        case .simple: return "简约"
        }
    }

    var subtitle: String {
        switch self {
        case .detailed: return "显示状态文案和会话数"
        case .simple: return "只显示动态图标"
        }
    }

    var systemImageName: String {
        switch self {
        case .detailed: return "text.alignleft"
        case .simple: return "sparkle"
        }
    }
}

struct AgentNotchSizeAdjustment: Equatable {
    let widthAdjustment: Double
    let heightAdjustment: Double
}

struct AgentFlameWavePreset: Codable, Equatable {
    let cellSize: Double
    let glowScale: Double
    let glowOpacity: Double
    let leadingBlur: Double
    let brightnessPower: Double
    let bloomStrength: Double
    let purpleRed: Double
    let purpleGreen: Double
    let purpleBlue: Double
    let sparkRed: Double
    let sparkGreen: Double
    let sparkBlue: Double
    let columnPitch: Double
    let widthScale: Double
    let horizontalOffset: Double
    let workingTextOffset: Double
    let sessionsTextOffset: Double
    let waveNoise: Double
    let sparkNoise: Double
    let sparkDistribution: Double
    let sparkHorizontalCenter: Double
    let sparkHorizontalSpread: Double
    let sparkSpeed: Double
    let expansionSpeed: Double
    let horizontalDrift: Double
    let horizontalDriftSpeed: Double
    let fadeDepth: Double
    let fadeSpeed: Double

    init(
        cellSize: Double,
        glowScale: Double,
        glowOpacity: Double,
        leadingBlur: Double,
        brightnessPower: Double,
        bloomStrength: Double,
        purpleRed: Double,
        purpleGreen: Double,
        purpleBlue: Double,
        sparkRed: Double,
        sparkGreen: Double,
        sparkBlue: Double,
        columnPitch: Double,
        widthScale: Double,
        horizontalOffset: Double,
        workingTextOffset: Double,
        sessionsTextOffset: Double,
        waveNoise: Double,
        sparkNoise: Double,
        sparkDistribution: Double,
        sparkHorizontalCenter: Double,
        sparkHorizontalSpread: Double,
        sparkSpeed: Double,
        expansionSpeed: Double,
        horizontalDrift: Double,
        horizontalDriftSpeed: Double,
        fadeDepth: Double,
        fadeSpeed: Double
    ) {
        self.cellSize = cellSize
        self.glowScale = glowScale
        self.glowOpacity = glowOpacity
        self.leadingBlur = leadingBlur
        self.brightnessPower = brightnessPower
        self.bloomStrength = bloomStrength
        self.purpleRed = purpleRed
        self.purpleGreen = purpleGreen
        self.purpleBlue = purpleBlue
        self.sparkRed = sparkRed
        self.sparkGreen = sparkGreen
        self.sparkBlue = sparkBlue
        self.columnPitch = columnPitch
        self.widthScale = widthScale
        self.horizontalOffset = horizontalOffset
        self.workingTextOffset = workingTextOffset
        self.sessionsTextOffset = sessionsTextOffset
        self.waveNoise = waveNoise
        self.sparkNoise = sparkNoise
        self.sparkDistribution = sparkDistribution
        self.sparkHorizontalCenter = sparkHorizontalCenter
        self.sparkHorizontalSpread = sparkHorizontalSpread
        self.sparkSpeed = sparkSpeed
        self.expansionSpeed = expansionSpeed
        self.horizontalDrift = horizontalDrift
        self.horizontalDriftSpeed = horizontalDriftSpeed
        self.fadeDepth = fadeDepth
        self.fadeSpeed = fadeSpeed
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        cellSize = try values.decode(Double.self, forKey: .cellSize)
        glowScale = try values.decode(Double.self, forKey: .glowScale)
        glowOpacity = try values.decode(Double.self, forKey: .glowOpacity)
        leadingBlur = try values.decode(Double.self, forKey: .leadingBlur)
        brightnessPower = try values.decode(Double.self, forKey: .brightnessPower)
        bloomStrength = try values.decode(Double.self, forKey: .bloomStrength)
        purpleRed = try values.decodeIfPresent(Double.self, forKey: .purpleRed) ?? 0.78
        purpleGreen = try values.decodeIfPresent(Double.self, forKey: .purpleGreen) ?? 0.28
        purpleBlue = try values.decodeIfPresent(Double.self, forKey: .purpleBlue) ?? 1.0
        sparkRed = try values.decode(Double.self, forKey: .sparkRed)
        sparkGreen = try values.decode(Double.self, forKey: .sparkGreen)
        sparkBlue = try values.decode(Double.self, forKey: .sparkBlue)
        columnPitch = try values.decodeIfPresent(Double.self, forKey: .columnPitch) ?? 5.8
        widthScale = try values.decodeIfPresent(Double.self, forKey: .widthScale) ?? 1.0
        horizontalOffset = try values.decodeIfPresent(Double.self, forKey: .horizontalOffset) ?? 0
        workingTextOffset = try values.decodeIfPresent(Double.self, forKey: .workingTextOffset) ?? 0
        sessionsTextOffset = try values.decodeIfPresent(Double.self, forKey: .sessionsTextOffset) ?? 0
        waveNoise = try values.decode(Double.self, forKey: .waveNoise)
        sparkNoise = try values.decode(Double.self, forKey: .sparkNoise)
        sparkDistribution = try values.decode(Double.self, forKey: .sparkDistribution)
        sparkHorizontalCenter = try values.decode(Double.self, forKey: .sparkHorizontalCenter)
        sparkHorizontalSpread = try values.decode(Double.self, forKey: .sparkHorizontalSpread)
        sparkSpeed = try values.decode(Double.self, forKey: .sparkSpeed)
        expansionSpeed = try values.decodeIfPresent(Double.self, forKey: .expansionSpeed) ?? 1.0
        horizontalDrift = try values.decodeIfPresent(Double.self, forKey: .horizontalDrift) ?? 0.012
        horizontalDriftSpeed = try values.decodeIfPresent(Double.self, forKey: .horizontalDriftSpeed) ?? 1.0
        fadeDepth = try values.decodeIfPresent(Double.self, forKey: .fadeDepth) ?? 0.10
        fadeSpeed = try values.decodeIfPresent(Double.self, forKey: .fadeSpeed) ?? 1.0
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
        static let showMenuBarIcon = "NotchPaste.showMenuBarIcon"
        static let shortcutId = "NotchPaste.shortcutId"
        static let agentRunningIconStyle = "NotchPaste.agentRunningIconStyle"
        static let agentAttentionIconStyle = "NotchPaste.agentAttentionIconStyle"
        static let agentActivityIconPosition = "NotchPaste.agentActivityIconPosition"
        static let agentActivityIconSize = "NotchPaste.agentActivityIconSize"
        static let agentActivityIconOffsetX = "NotchPaste.agentActivityIconOffsetX"
        static let agentActivityIconOffsetY = "NotchPaste.agentActivityIconOffsetY"
        static let agentActivityIconEffect = "NotchPaste.agentActivityIconEffect"
        static let agentActivityNotchDisplayMode = "NotchPaste.agentActivityNotchDisplayMode"
        static let agentRunningIconRed = "NotchPaste.agentRunningIconRed"
        static let agentRunningIconGreen = "NotchPaste.agentRunningIconGreen"
        static let agentRunningIconBlue = "NotchPaste.agentRunningIconBlue"
        static let agentAttentionIconRed = "NotchPaste.agentAttentionIconRed"
        static let agentAttentionIconGreen = "NotchPaste.agentAttentionIconGreen"
        static let agentAttentionIconBlue = "NotchPaste.agentAttentionIconBlue"
        static let agentRunningCustomIconPath = "NotchPaste.agentRunningCustomIconPath"
        static let agentAttentionCustomIconPath = "NotchPaste.agentAttentionCustomIconPath"
        static let agentRunningNotchWidthAdjustment = "NotchPaste.agentRunningNotchWidthAdjustment"
        static let agentRunningNotchHeightAdjustment = "NotchPaste.agentRunningNotchHeightAdjustment"
        static let agentAttentionNotchWidthAdjustment = "NotchPaste.agentAttentionNotchWidthAdjustment"
        static let agentAttentionNotchHeightAdjustment = "NotchPaste.agentAttentionNotchHeightAdjustment"
        static let agentRunningSimpleNotchWidthAdjustment = "NotchPaste.agentRunningSimpleNotchWidthAdjustment"
        static let agentRunningSimpleNotchHeightAdjustment = "NotchPaste.agentRunningSimpleNotchHeightAdjustment"
        static let agentAttentionSimpleNotchWidthAdjustment = "NotchPaste.agentAttentionSimpleNotchWidthAdjustment"
        static let agentAttentionSimpleNotchHeightAdjustment = "NotchPaste.agentAttentionSimpleNotchHeightAdjustment"
        static let agentFlameWaveCellSize = "NotchPaste.agentFlameWaveCellSize"
        static let agentFlameWaveGlowScale = "NotchPaste.agentFlameWaveGlowScale"
        static let agentFlameWaveGlowOpacity = "NotchPaste.agentFlameWaveGlowOpacity"
        static let agentFlameWaveLeadingBlur = "NotchPaste.agentFlameWaveLeadingBlur"
        static let agentFlameWaveBrightnessPower = "NotchPaste.agentFlameWaveBrightnessPower"
        static let agentFlameWaveBloomStrength = "NotchPaste.agentFlameWaveBloomStrength"
        static let agentFlameWavePurpleRed = "NotchPaste.agentFlameWavePurpleRed"
        static let agentFlameWavePurpleGreen = "NotchPaste.agentFlameWavePurpleGreen"
        static let agentFlameWavePurpleBlue = "NotchPaste.agentFlameWavePurpleBlue"
        static let agentFlameWaveSparkRed = "NotchPaste.agentFlameWaveSparkRed"
        static let agentFlameWaveSparkGreen = "NotchPaste.agentFlameWaveSparkGreen"
        static let agentFlameWaveSparkBlue = "NotchPaste.agentFlameWaveSparkBlue"
        static let agentFlameWaveColumnPitch = "NotchPaste.agentFlameWaveColumnPitch"
        static let agentFlameWaveWidthScale = "NotchPaste.agentFlameWaveWidthScale"
        static let agentFlameWaveHorizontalOffset = "NotchPaste.agentFlameWaveHorizontalOffset"
        static let agentWorkingTextOffset = "NotchPaste.agentWorkingTextOffset"
        static let agentSessionsTextOffset = "NotchPaste.agentSessionsTextOffset"
        static let agentFlameWaveWaveNoise = "NotchPaste.agentFlameWaveWaveNoise"
        static let agentFlameWaveSparkNoise = "NotchPaste.agentFlameWaveSparkNoise"
        static let agentFlameWaveSparkDistribution = "NotchPaste.agentFlameWaveSparkDistribution"
        static let agentFlameWaveSparkHorizontalCenter = "NotchPaste.agentFlameWaveSparkHorizontalCenter"
        static let agentFlameWaveSparkHorizontalSpread = "NotchPaste.agentFlameWaveSparkHorizontalSpread"
        static let agentFlameWaveSparkSpeed = "NotchPaste.agentFlameWaveSparkSpeed"
        static let agentFlameWaveExpansionSpeed = "NotchPaste.agentFlameWaveExpansionSpeed"
        static let agentFlameWaveHorizontalDrift = "NotchPaste.agentFlameWaveHorizontalDrift"
        static let agentFlameWaveHorizontalDriftSpeed = "NotchPaste.agentFlameWaveHorizontalDriftSpeed"
        static let agentFlameWaveFadeDepth = "NotchPaste.agentFlameWaveFadeDepth"
        static let agentFlameWaveFadeSpeed = "NotchPaste.agentFlameWaveFadeSpeed"
        static let agentFlameWaveSavedPreset = "NotchPaste.agentFlameWaveSavedPreset"
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

    /// 是否在系统菜单栏显示 NotchPaste 图标。关闭后仍可从刘海设置重新打开。
    @Published var showMenuBarIcon: Bool {
        didSet { defaults.set(showMenuBarIcon, forKey: Key.showMenuBarIcon) }
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

    /// Agent closed 刘海的显示模式。详细模式显示文案和会话数，简约模式只显示动态图标。
    @Published var agentActivityNotchDisplayMode: AgentActivityNotchDisplayMode {
        didSet { defaults.set(agentActivityNotchDisplayMode.rawValue, forKey: Key.agentActivityNotchDisplayMode) }
    }

    /// 运行中 Agent 图标颜色 red 分量。
    @Published var agentRunningIconRed: Double {
        didSet { defaults.set(agentRunningIconRed, forKey: Key.agentRunningIconRed) }
    }

    /// 运行中 Agent 图标颜色 green 分量。
    @Published var agentRunningIconGreen: Double {
        didSet { defaults.set(agentRunningIconGreen, forKey: Key.agentRunningIconGreen) }
    }

    /// 运行中 Agent 图标颜色 blue 分量。
    @Published var agentRunningIconBlue: Double {
        didSet { defaults.set(agentRunningIconBlue, forKey: Key.agentRunningIconBlue) }
    }

    /// 待处理 Agent 图标颜色 red 分量。
    @Published var agentAttentionIconRed: Double {
        didSet { defaults.set(agentAttentionIconRed, forKey: Key.agentAttentionIconRed) }
    }

    /// 待处理 Agent 图标颜色 green 分量。
    @Published var agentAttentionIconGreen: Double {
        didSet { defaults.set(agentAttentionIconGreen, forKey: Key.agentAttentionIconGreen) }
    }

    /// 待处理 Agent 图标颜色 blue 分量。
    @Published var agentAttentionIconBlue: Double {
        didSet { defaults.set(agentAttentionIconBlue, forKey: Key.agentAttentionIconBlue) }
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
        didSet { defaults.set(agentRunningNotchWidthAdjustment, forKey: Key.agentRunningNotchWidthAdjustment) }
    }

    /// 运行中 closed 刘海高度微调，单位 pt。
    @Published var agentRunningNotchHeightAdjustment: Double {
        didSet { defaults.set(agentRunningNotchHeightAdjustment, forKey: Key.agentRunningNotchHeightAdjustment) }
    }

    /// 待处理 closed 刘海宽度微调，单位 pt。
    @Published var agentAttentionNotchWidthAdjustment: Double {
        didSet { defaults.set(agentAttentionNotchWidthAdjustment, forKey: Key.agentAttentionNotchWidthAdjustment) }
    }

    /// 待处理 closed 刘海高度微调，单位 pt。
    @Published var agentAttentionNotchHeightAdjustment: Double {
        didSet { defaults.set(agentAttentionNotchHeightAdjustment, forKey: Key.agentAttentionNotchHeightAdjustment) }
    }

    /// 简约模式下运行中 closed 刘海宽度微调，单位 pt。
    @Published var agentRunningSimpleNotchWidthAdjustment: Double {
        didSet { defaults.set(agentRunningSimpleNotchWidthAdjustment, forKey: Key.agentRunningSimpleNotchWidthAdjustment) }
    }

    /// 简约模式下运行中 closed 刘海高度微调，单位 pt。
    @Published var agentRunningSimpleNotchHeightAdjustment: Double {
        didSet { defaults.set(agentRunningSimpleNotchHeightAdjustment, forKey: Key.agentRunningSimpleNotchHeightAdjustment) }
    }

    /// 简约模式下待处理 closed 刘海宽度微调，单位 pt。
    @Published var agentAttentionSimpleNotchWidthAdjustment: Double {
        didSet { defaults.set(agentAttentionSimpleNotchWidthAdjustment, forKey: Key.agentAttentionSimpleNotchWidthAdjustment) }
    }

    /// 简约模式下待处理 closed 刘海高度微调，单位 pt。
    @Published var agentAttentionSimpleNotchHeightAdjustment: Double {
        didSet { defaults.set(agentAttentionSimpleNotchHeightAdjustment, forKey: Key.agentAttentionSimpleNotchHeightAdjustment) }
    }

    /// 火焰波方块固定尺寸，单位 pt。
    @Published var agentFlameWaveCellSize: Double {
        didSet { defaults.set(agentFlameWaveCellSize, forKey: Key.agentFlameWaveCellSize) }
    }

    /// 火焰波方块泛光大小倍率。
    @Published var agentFlameWaveGlowScale: Double {
        didSet { defaults.set(agentFlameWaveGlowScale, forKey: Key.agentFlameWaveGlowScale) }
    }

    /// 火焰波方块泛光透明度倍率。
    @Published var agentFlameWaveGlowOpacity: Double {
        didSet { defaults.set(agentFlameWaveGlowOpacity, forKey: Key.agentFlameWaveGlowOpacity) }
    }

    /// 火焰波左侧方块模糊倍率。
    @Published var agentFlameWaveLeadingBlur: Double {
        didSet { defaults.set(agentFlameWaveLeadingBlur, forKey: Key.agentFlameWaveLeadingBlur) }
    }

    /// 火焰波紫色明度曲线指数。
    @Published var agentFlameWaveBrightnessPower: Double {
        didSet { defaults.set(agentFlameWaveBrightnessPower, forKey: Key.agentFlameWaveBrightnessPower) }
    }

    /// 火焰波末端圆角矩形 bloom 强度。
    @Published var agentFlameWaveBloomStrength: Double {
        didSet { defaults.set(agentFlameWaveBloomStrength, forKey: Key.agentFlameWaveBloomStrength) }
    }

    /// 火焰波主紫色 red 分量。
    @Published var agentFlameWavePurpleRed: Double {
        didSet { defaults.set(agentFlameWavePurpleRed, forKey: Key.agentFlameWavePurpleRed) }
    }

    /// 火焰波主紫色 green 分量。
    @Published var agentFlameWavePurpleGreen: Double {
        didSet { defaults.set(agentFlameWavePurpleGreen, forKey: Key.agentFlameWavePurpleGreen) }
    }

    /// 火焰波主紫色 blue 分量。
    @Published var agentFlameWavePurpleBlue: Double {
        didSet { defaults.set(agentFlameWavePurpleBlue, forKey: Key.agentFlameWavePurpleBlue) }
    }

    /// 火焰波白点颜色 red 分量。
    @Published var agentFlameWaveSparkRed: Double {
        didSet { defaults.set(agentFlameWaveSparkRed, forKey: Key.agentFlameWaveSparkRed) }
    }

    /// 火焰波白点颜色 green 分量。
    @Published var agentFlameWaveSparkGreen: Double {
        didSet { defaults.set(agentFlameWaveSparkGreen, forKey: Key.agentFlameWaveSparkGreen) }
    }

    /// 火焰波白点颜色 blue 分量。
    @Published var agentFlameWaveSparkBlue: Double {
        didSet { defaults.set(agentFlameWaveSparkBlue, forKey: Key.agentFlameWaveSparkBlue) }
    }

    /// 火焰波每列粒子中心间距，单位 pt。
    @Published var agentFlameWaveColumnPitch: Double {
        didSet { defaults.set(agentFlameWaveColumnPitch, forKey: Key.agentFlameWaveColumnPitch) }
    }

    /// 火焰波总生成宽度倍率。
    @Published var agentFlameWaveWidthScale: Double {
        didSet { defaults.set(agentFlameWaveWidthScale, forKey: Key.agentFlameWaveWidthScale) }
    }

    /// 火焰波整体水平偏移，单位 pt。
    @Published var agentFlameWaveHorizontalOffset: Double {
        didSet { defaults.set(agentFlameWaveHorizontalOffset, forKey: Key.agentFlameWaveHorizontalOffset) }
    }

    /// 详细模式 Working 文案水平偏移，单位 pt；正值向右。
    @Published var agentWorkingTextOffset: Double {
        didSet { defaults.set(agentWorkingTextOffset, forKey: Key.agentWorkingTextOffset) }
    }

    /// 详细模式 session 文案水平偏移，单位 pt；正值向右。
    @Published var agentSessionsTextOffset: Double {
        didSet { defaults.set(agentSessionsTextOffset, forKey: Key.agentSessionsTextOffset) }
    }

    /// 火焰波上下波动的随机噪声强度。
    @Published var agentFlameWaveWaveNoise: Double {
        didSet { defaults.set(agentFlameWaveWaveNoise, forKey: Key.agentFlameWaveWaveNoise) }
    }

    /// 火焰波白点生成噪声强度。
    @Published var agentFlameWaveSparkNoise: Double {
        didSet { defaults.set(agentFlameWaveSparkNoise, forKey: Key.agentFlameWaveSparkNoise) }
    }

    /// 火焰波白点分布函数指数。
    @Published var agentFlameWaveSparkDistribution: Double {
        didSet { defaults.set(agentFlameWaveSparkDistribution, forKey: Key.agentFlameWaveSparkDistribution) }
    }

    /// 火焰波白点横向中心，0 靠近尾部，1 靠近图标高亮处。
    @Published var agentFlameWaveSparkHorizontalCenter: Double {
        didSet { defaults.set(agentFlameWaveSparkHorizontalCenter, forKey: Key.agentFlameWaveSparkHorizontalCenter) }
    }

    /// 火焰波白点横向分布宽度。
    @Published var agentFlameWaveSparkHorizontalSpread: Double {
        didSet { defaults.set(agentFlameWaveSparkHorizontalSpread, forKey: Key.agentFlameWaveSparkHorizontalSpread) }
    }

    /// 火焰波白点闪烁运动速度倍率。
    @Published var agentFlameWaveSparkSpeed: Double {
        didSet { defaults.set(agentFlameWaveSparkSpeed, forKey: Key.agentFlameWaveSparkSpeed) }
    }

    /// 火焰波从左向右扩散的速度倍率。
    @Published var agentFlameWaveExpansionSpeed: Double {
        didSet { defaults.set(agentFlameWaveExpansionSpeed, forKey: Key.agentFlameWaveExpansionSpeed) }
    }

    /// 火焰波方块水平左右波动幅度，按波形宽度比例计算。
    @Published var agentFlameWaveHorizontalDrift: Double {
        didSet { defaults.set(agentFlameWaveHorizontalDrift, forKey: Key.agentFlameWaveHorizontalDrift) }
    }

    /// 火焰波方块水平左右波动速度倍率。
    @Published var agentFlameWaveHorizontalDriftSpeed: Double {
        didSet { defaults.set(agentFlameWaveHorizontalDriftSpeed, forKey: Key.agentFlameWaveHorizontalDriftSpeed) }
    }

    /// 火焰波方块消失/淡出动态强度。
    @Published var agentFlameWaveFadeDepth: Double {
        didSet { defaults.set(agentFlameWaveFadeDepth, forKey: Key.agentFlameWaveFadeDepth) }
    }

    /// 火焰波方块消失/淡出动态速度倍率。
    @Published var agentFlameWaveFadeSpeed: Double {
        didSet { defaults.set(agentFlameWaveFadeSpeed, forKey: Key.agentFlameWaveFadeSpeed) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedMaxItems: Int = (defaults.object(forKey: Key.maxItems) as? Int) ?? ClipboardStore.defaultMaxItems
        let storedAutoPaste: Bool = (defaults.object(forKey: Key.autoPasteEnabled) as? Bool) ?? true
        let storedHover: Bool = (defaults.object(forKey: Key.hoverToExpand) as? Bool) ?? true
        let storedClose: Bool = (defaults.object(forKey: Key.closeAfterCopy) as? Bool) ?? true
        let storedMonitor: Bool = (defaults.object(forKey: Key.monitoringEnabled) as? Bool) ?? true
        let storedShowMenuBarIcon: Bool = (defaults.object(forKey: Key.showMenuBarIcon) as? Bool) ?? true
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
        let storedDisplayMode = AgentActivityNotchDisplayMode(
            rawValue: (defaults.object(forKey: Key.agentActivityNotchDisplayMode) as? String) ?? ""
        ) ?? .detailed
        let storedRunningIconRed = (defaults.object(forKey: Key.agentRunningIconRed) as? Double) ?? 0.0
        let storedRunningIconGreen = (defaults.object(forKey: Key.agentRunningIconGreen) as? Double) ?? 0.78
        let storedRunningIconBlue = (defaults.object(forKey: Key.agentRunningIconBlue) as? Double) ?? 1.0
        let storedAttentionIconRed = (defaults.object(forKey: Key.agentAttentionIconRed) as? Double) ?? 1.0
        let storedAttentionIconGreen = (defaults.object(forKey: Key.agentAttentionIconGreen) as? Double) ?? 0.55
        let storedAttentionIconBlue = (defaults.object(forKey: Key.agentAttentionIconBlue) as? Double) ?? 0.16
        let storedRunningCustomIconPath = defaults.object(forKey: Key.agentRunningCustomIconPath) as? String
        let storedAttentionCustomIconPath = defaults.object(forKey: Key.agentAttentionCustomIconPath) as? String
        let storedRunningWidth = (defaults.object(forKey: Key.agentRunningNotchWidthAdjustment) as? Double) ?? 0
        let storedRunningHeight = (defaults.object(forKey: Key.agentRunningNotchHeightAdjustment) as? Double) ?? 0
        let storedAttentionWidth = (defaults.object(forKey: Key.agentAttentionNotchWidthAdjustment) as? Double) ?? storedRunningWidth
        let storedAttentionHeight = (defaults.object(forKey: Key.agentAttentionNotchHeightAdjustment) as? Double) ?? 0
        let storedRunningSimpleWidth = (defaults.object(forKey: Key.agentRunningSimpleNotchWidthAdjustment) as? Double) ?? storedRunningWidth
        let storedRunningSimpleHeight = (defaults.object(forKey: Key.agentRunningSimpleNotchHeightAdjustment) as? Double) ?? storedRunningHeight
        let storedAttentionSimpleWidth = (defaults.object(forKey: Key.agentAttentionSimpleNotchWidthAdjustment) as? Double) ?? storedAttentionWidth
        let storedAttentionSimpleHeight = (defaults.object(forKey: Key.agentAttentionSimpleNotchHeightAdjustment) as? Double) ?? storedAttentionHeight
        let storedFlameWaveCellSize = (defaults.object(forKey: Key.agentFlameWaveCellSize) as? Double) ?? 2.6
        let storedFlameWaveGlowScale = (defaults.object(forKey: Key.agentFlameWaveGlowScale) as? Double) ?? 2.45
        let storedFlameWaveGlowOpacity = (defaults.object(forKey: Key.agentFlameWaveGlowOpacity) as? Double) ?? 1.0
        let storedFlameWaveLeadingBlur = (defaults.object(forKey: Key.agentFlameWaveLeadingBlur) as? Double) ?? 1.0
        let storedFlameWaveBrightnessPower = (defaults.object(forKey: Key.agentFlameWaveBrightnessPower) as? Double) ?? 1.35
        let storedFlameWaveBloomStrength = (defaults.object(forKey: Key.agentFlameWaveBloomStrength) as? Double) ?? 1.0
        let storedFlameWavePurpleRed = (defaults.object(forKey: Key.agentFlameWavePurpleRed) as? Double) ?? 0.78
        let storedFlameWavePurpleGreen = (defaults.object(forKey: Key.agentFlameWavePurpleGreen) as? Double) ?? 0.28
        let storedFlameWavePurpleBlue = (defaults.object(forKey: Key.agentFlameWavePurpleBlue) as? Double) ?? 1.0
        let storedFlameWaveSparkRed = (defaults.object(forKey: Key.agentFlameWaveSparkRed) as? Double) ?? 1.0
        let storedFlameWaveSparkGreen = (defaults.object(forKey: Key.agentFlameWaveSparkGreen) as? Double) ?? 1.0
        let storedFlameWaveSparkBlue = (defaults.object(forKey: Key.agentFlameWaveSparkBlue) as? Double) ?? 1.0
        let storedFlameWaveColumnPitch = (defaults.object(forKey: Key.agentFlameWaveColumnPitch) as? Double) ?? 5.8
        let storedFlameWaveWidthScale = (defaults.object(forKey: Key.agentFlameWaveWidthScale) as? Double) ?? 1.0
        let storedFlameWaveHorizontalOffset = (defaults.object(forKey: Key.agentFlameWaveHorizontalOffset) as? Double) ?? 0
        let storedWorkingTextOffset = (defaults.object(forKey: Key.agentWorkingTextOffset) as? Double) ?? 0
        let storedSessionsTextOffset = (defaults.object(forKey: Key.agentSessionsTextOffset) as? Double) ?? 0
        let storedFlameWaveWaveNoise = (defaults.object(forKey: Key.agentFlameWaveWaveNoise) as? Double) ?? 1.0
        let storedFlameWaveSparkNoise = (defaults.object(forKey: Key.agentFlameWaveSparkNoise) as? Double) ?? 1.0
        let storedFlameWaveSparkDistribution = (defaults.object(forKey: Key.agentFlameWaveSparkDistribution) as? Double) ?? 1.65
        let storedFlameWaveSparkHorizontalCenter = (defaults.object(forKey: Key.agentFlameWaveSparkHorizontalCenter) as? Double) ?? 0.78
        let storedFlameWaveSparkHorizontalSpread = (defaults.object(forKey: Key.agentFlameWaveSparkHorizontalSpread) as? Double) ?? 0.30
        let storedFlameWaveSparkSpeed = (defaults.object(forKey: Key.agentFlameWaveSparkSpeed) as? Double) ?? 1.0
        let storedFlameWaveExpansionSpeed = (defaults.object(forKey: Key.agentFlameWaveExpansionSpeed) as? Double) ?? 1.0
        let storedFlameWaveHorizontalDrift = (defaults.object(forKey: Key.agentFlameWaveHorizontalDrift) as? Double) ?? 0.012
        let storedFlameWaveHorizontalDriftSpeed = (defaults.object(forKey: Key.agentFlameWaveHorizontalDriftSpeed) as? Double) ?? 1.0
        let storedFlameWaveFadeDepth = (defaults.object(forKey: Key.agentFlameWaveFadeDepth) as? Double) ?? 0.10
        let storedFlameWaveFadeSpeed = (defaults.object(forKey: Key.agentFlameWaveFadeSpeed) as? Double) ?? 1.0

        self.maxItems = storedMaxItems
        self.autoPasteEnabled = storedAutoPaste
        self.hoverToExpand = storedHover
        self.closeAfterCopy = storedClose
        self.monitoringEnabled = storedMonitor
        self.showMenuBarIcon = storedShowMenuBarIcon
        self.shortcut = GlobalShortcut.fromConfig(storedShortcutId)
        self.agentRunningIconStyle = storedRunningIcon
        self.agentAttentionIconStyle = storedAttentionIcon
        self.agentActivityIconPosition = storedIconPosition
        self.agentActivityIconSize = storedIconSize
        self.agentActivityIconOffsetX = storedIconOffsetX
        self.agentActivityIconOffsetY = storedIconOffsetY
        self.agentActivityIconEffect = storedIconEffect
        self.agentActivityNotchDisplayMode = storedDisplayMode
        self.agentRunningIconRed = storedRunningIconRed
        self.agentRunningIconGreen = storedRunningIconGreen
        self.agentRunningIconBlue = storedRunningIconBlue
        self.agentAttentionIconRed = storedAttentionIconRed
        self.agentAttentionIconGreen = storedAttentionIconGreen
        self.agentAttentionIconBlue = storedAttentionIconBlue
        self.agentRunningCustomIconPath = storedRunningCustomIconPath
        self.agentAttentionCustomIconPath = storedAttentionCustomIconPath
        self.agentRunningNotchWidthAdjustment = storedRunningWidth
        self.agentRunningNotchHeightAdjustment = storedRunningHeight
        self.agentAttentionNotchWidthAdjustment = storedAttentionWidth
        self.agentAttentionNotchHeightAdjustment = storedAttentionHeight
        self.agentRunningSimpleNotchWidthAdjustment = storedRunningSimpleWidth
        self.agentRunningSimpleNotchHeightAdjustment = storedRunningSimpleHeight
        self.agentAttentionSimpleNotchWidthAdjustment = storedAttentionSimpleWidth
        self.agentAttentionSimpleNotchHeightAdjustment = storedAttentionSimpleHeight
        self.agentFlameWaveCellSize = storedFlameWaveCellSize
        self.agentFlameWaveGlowScale = storedFlameWaveGlowScale
        self.agentFlameWaveGlowOpacity = storedFlameWaveGlowOpacity
        self.agentFlameWaveLeadingBlur = storedFlameWaveLeadingBlur
        self.agentFlameWaveBrightnessPower = storedFlameWaveBrightnessPower
        self.agentFlameWaveBloomStrength = storedFlameWaveBloomStrength
        self.agentFlameWavePurpleRed = storedFlameWavePurpleRed
        self.agentFlameWavePurpleGreen = storedFlameWavePurpleGreen
        self.agentFlameWavePurpleBlue = storedFlameWavePurpleBlue
        self.agentFlameWaveSparkRed = storedFlameWaveSparkRed
        self.agentFlameWaveSparkGreen = storedFlameWaveSparkGreen
        self.agentFlameWaveSparkBlue = storedFlameWaveSparkBlue
        self.agentFlameWaveColumnPitch = storedFlameWaveColumnPitch
        self.agentFlameWaveWidthScale = storedFlameWaveWidthScale
        self.agentFlameWaveHorizontalOffset = storedFlameWaveHorizontalOffset
        self.agentWorkingTextOffset = storedWorkingTextOffset
        self.agentSessionsTextOffset = storedSessionsTextOffset
        self.agentFlameWaveWaveNoise = storedFlameWaveWaveNoise
        self.agentFlameWaveSparkNoise = storedFlameWaveSparkNoise
        self.agentFlameWaveSparkDistribution = storedFlameWaveSparkDistribution
        self.agentFlameWaveSparkHorizontalCenter = storedFlameWaveSparkHorizontalCenter
        self.agentFlameWaveSparkHorizontalSpread = storedFlameWaveSparkHorizontalSpread
        self.agentFlameWaveSparkSpeed = storedFlameWaveSparkSpeed
        self.agentFlameWaveExpansionSpeed = storedFlameWaveExpansionSpeed
        self.agentFlameWaveHorizontalDrift = storedFlameWaveHorizontalDrift
        self.agentFlameWaveHorizontalDriftSpeed = storedFlameWaveHorizontalDriftSpeed
        self.agentFlameWaveFadeDepth = storedFlameWaveFadeDepth
        self.agentFlameWaveFadeSpeed = storedFlameWaveFadeSpeed
    }

    var hasSavedAgentFlameWavePreset: Bool {
        defaults.object(forKey: Key.agentFlameWaveSavedPreset) != nil
    }

    func agentNotchSizeAdjustment(isAttention: Bool, mode: AgentActivityNotchDisplayMode) -> AgentNotchSizeAdjustment {
        switch (isAttention, mode) {
        case (false, .detailed):
            return AgentNotchSizeAdjustment(
                widthAdjustment: agentRunningNotchWidthAdjustment,
                heightAdjustment: agentRunningNotchHeightAdjustment
            )
        case (false, .simple):
            return AgentNotchSizeAdjustment(
                widthAdjustment: agentRunningSimpleNotchWidthAdjustment,
                heightAdjustment: agentRunningSimpleNotchHeightAdjustment
            )
        case (true, .detailed):
            return AgentNotchSizeAdjustment(
                widthAdjustment: agentAttentionNotchWidthAdjustment,
                heightAdjustment: agentAttentionNotchHeightAdjustment
            )
        case (true, .simple):
            return AgentNotchSizeAdjustment(
                widthAdjustment: agentAttentionSimpleNotchWidthAdjustment,
                heightAdjustment: agentAttentionSimpleNotchHeightAdjustment
            )
        }
    }

    func currentAgentFlameWavePreset() -> AgentFlameWavePreset {
        AgentFlameWavePreset(
            cellSize: agentFlameWaveCellSize,
            glowScale: agentFlameWaveGlowScale,
            glowOpacity: agentFlameWaveGlowOpacity,
            leadingBlur: agentFlameWaveLeadingBlur,
            brightnessPower: agentFlameWaveBrightnessPower,
            bloomStrength: agentFlameWaveBloomStrength,
            purpleRed: agentFlameWavePurpleRed,
            purpleGreen: agentFlameWavePurpleGreen,
            purpleBlue: agentFlameWavePurpleBlue,
            sparkRed: agentFlameWaveSparkRed,
            sparkGreen: agentFlameWaveSparkGreen,
            sparkBlue: agentFlameWaveSparkBlue,
            columnPitch: agentFlameWaveColumnPitch,
            widthScale: agentFlameWaveWidthScale,
            horizontalOffset: agentFlameWaveHorizontalOffset,
            workingTextOffset: agentWorkingTextOffset,
            sessionsTextOffset: agentSessionsTextOffset,
            waveNoise: agentFlameWaveWaveNoise,
            sparkNoise: agentFlameWaveSparkNoise,
            sparkDistribution: agentFlameWaveSparkDistribution,
            sparkHorizontalCenter: agentFlameWaveSparkHorizontalCenter,
            sparkHorizontalSpread: agentFlameWaveSparkHorizontalSpread,
            sparkSpeed: agentFlameWaveSparkSpeed,
            expansionSpeed: agentFlameWaveExpansionSpeed,
            horizontalDrift: agentFlameWaveHorizontalDrift,
            horizontalDriftSpeed: agentFlameWaveHorizontalDriftSpeed,
            fadeDepth: agentFlameWaveFadeDepth,
            fadeSpeed: agentFlameWaveFadeSpeed
        )
    }

    func saveAgentFlameWavePreset() {
        guard let data = try? JSONEncoder().encode(currentAgentFlameWavePreset()) else { return }
        defaults.set(data, forKey: Key.agentFlameWaveSavedPreset)
    }

    @discardableResult
    func loadAgentFlameWavePreset() -> Bool {
        guard
            let data = defaults.data(forKey: Key.agentFlameWaveSavedPreset),
            let preset = try? JSONDecoder().decode(AgentFlameWavePreset.self, from: data)
        else {
            return false
        }

        applyAgentFlameWavePreset(preset)
        return true
    }

    func applyAgentFlameWavePreset(_ preset: AgentFlameWavePreset) {
        agentFlameWaveCellSize = preset.cellSize
        agentFlameWaveGlowScale = preset.glowScale
        agentFlameWaveGlowOpacity = preset.glowOpacity
        agentFlameWaveLeadingBlur = preset.leadingBlur
        agentFlameWaveBrightnessPower = preset.brightnessPower
        agentFlameWaveBloomStrength = preset.bloomStrength
        agentFlameWavePurpleRed = preset.purpleRed
        agentFlameWavePurpleGreen = preset.purpleGreen
        agentFlameWavePurpleBlue = preset.purpleBlue
        agentFlameWaveSparkRed = preset.sparkRed
        agentFlameWaveSparkGreen = preset.sparkGreen
        agentFlameWaveSparkBlue = preset.sparkBlue
        agentFlameWaveColumnPitch = preset.columnPitch
        agentFlameWaveWidthScale = preset.widthScale
        agentFlameWaveHorizontalOffset = preset.horizontalOffset
        agentWorkingTextOffset = preset.workingTextOffset
        agentSessionsTextOffset = preset.sessionsTextOffset
        agentFlameWaveWaveNoise = preset.waveNoise
        agentFlameWaveSparkNoise = preset.sparkNoise
        agentFlameWaveSparkDistribution = preset.sparkDistribution
        agentFlameWaveSparkHorizontalCenter = preset.sparkHorizontalCenter
        agentFlameWaveSparkHorizontalSpread = preset.sparkHorizontalSpread
        agentFlameWaveSparkSpeed = preset.sparkSpeed
        agentFlameWaveExpansionSpeed = preset.expansionSpeed
        agentFlameWaveHorizontalDrift = preset.horizontalDrift
        agentFlameWaveHorizontalDriftSpeed = preset.horizontalDriftSpeed
        agentFlameWaveFadeDepth = preset.fadeDepth
        agentFlameWaveFadeSpeed = preset.fadeSpeed
    }

    private func setOptional(_ value: String?, forKey key: String) {
        if let value, !value.isEmpty {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
