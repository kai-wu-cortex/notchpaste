import AppKit
import Testing
@testable import NotchPaste

@Suite("PasteService")
struct PasteServiceTests {

    @Test("copy without auto paste does not ignore clipboard monitoring")
    func copyWithoutAutoPasteDoesNotIgnoreClipboardMonitoring() {
        let monitor = SpyClipboardChangeIgnorer()
        let service = PasteService(
            preferences: PreferencesStore(defaults: UserDefaults(suiteName: "PasteServiceTests-\(UUID().uuidString)")!)
        )
        service.changeIgnorer = monitor
        service.accessibilityTrustedProvider = { _ in true }

        service.paste(ClipboardItem.text("copy only"), activating: nil)

        #expect(monitor.ignoreCallCount == 0)
    }

    @Test("auto paste ignores clipboard monitoring echo")
    func autoPasteIgnoresClipboardMonitoringEcho() {
        let monitor = SpyClipboardChangeIgnorer()
        let service = PasteService(
            preferences: PreferencesStore(defaults: UserDefaults(suiteName: "PasteServiceTests-\(UUID().uuidString)")!)
        )
        service.changeIgnorer = monitor
        service.accessibilityTrustedProvider = { _ in true }

        service.paste(ClipboardItem.text("auto paste"), activating: PasteTarget(app: nil))

        #expect(monitor.ignoreCallCount == 1)
    }

    @Test("auto paste waits until target app is frontmost before posting shortcut")
    func autoPasteWaitsUntilTargetAppIsFrontmostBeforePostingShortcut() {
        let service = PasteService(
            preferences: PreferencesStore(defaults: UserDefaults(suiteName: "PasteServiceTests-\(UUID().uuidString)")!)
        )
        service.accessibilityTrustedProvider = { _ in true }

        var frontmostBundleID = "com.apple.finder"
        service.frontmostBundleIdentifierProvider = { frontmostBundleID }

        var scheduled: [(TimeInterval, () -> Void)] = []
        service.delayScheduler = { delay, action in
            scheduled.append((delay, action))
        }

        var restoredFocusCount = 0
        var postedPasteShortcutCount = 0
        service.pasteShortcutPoster = {
            postedPasteShortcutCount += 1
        }

        service.paste(
            ClipboardItem.text("wait for target"),
            activating: PasteTarget(
                app: nil,
                bundleIdentifier: "com.example.target",
                restoreFocusedElement: { restoredFocusCount += 1 }
            )
        )

        #expect(scheduled.count == 1)
        scheduled.removeFirst().1()
        #expect(postedPasteShortcutCount == 0)
        #expect(restoredFocusCount == 0)
        #expect(scheduled.count == 1)

        frontmostBundleID = "com.example.target"
        scheduled.removeFirst().1()

        #expect(restoredFocusCount == 1)
        #expect(postedPasteShortcutCount == 1)
    }
}

@Suite("PreferencesStore")
struct PreferencesStoreTests {

    @Test("agent activity icon preferences default to current behavior")
    func agentActivityIconPreferencesDefaultToCurrentBehavior() {
        let store = PreferencesStore(defaults: makeDefaults())

        #expect(store.maxItems >= 1_000)
        #expect(store.showMenuBarIcon)
        #expect(store.agentRunningIconStyle == .spinner)
        #expect(store.agentAttentionIconStyle == .spinner)
        #expect(store.agentActivityIconPosition == .leading)
        #expect(store.agentActivityIconSize == 18)
        #expect(store.agentActivityIconOffsetX == 0)
        #expect(store.agentActivityIconOffsetY == 0)
        #expect(store.agentActivityIconEffect == .glow)
        #expect(store.agentActivityNotchDisplayMode == .detailed)
        #expect(store.agentRunningIconRed == 0.0)
        #expect(store.agentRunningIconGreen == 0.78)
        #expect(store.agentRunningIconBlue == 1.0)
        #expect(store.agentAttentionIconRed == 1.0)
        #expect(store.agentAttentionIconGreen == 0.55)
        #expect(store.agentAttentionIconBlue == 0.16)
        #expect(store.agentRunningCustomIconPath == nil)
        #expect(store.agentAttentionCustomIconPath == nil)
        #expect(store.agentRunningNotchWidthAdjustment == 0)
        #expect(store.agentRunningNotchHeightAdjustment == 0)
        #expect(store.agentAttentionNotchWidthAdjustment == 0)
        #expect(store.agentAttentionNotchHeightAdjustment == 0)
        #expect(store.agentRunningSimpleNotchWidthAdjustment == 0)
        #expect(store.agentRunningSimpleNotchHeightAdjustment == 0)
        #expect(store.agentAttentionSimpleNotchWidthAdjustment == 0)
        #expect(store.agentAttentionSimpleNotchHeightAdjustment == 0)
        #expect(store.agentFlameWaveCellSize == 2.6)
        #expect(store.agentFlameWaveGlowScale == 2.45)
        #expect(store.agentFlameWaveGlowOpacity == 1.0)
        #expect(store.agentFlameWaveLeadingBlur == 1.0)
        #expect(store.agentFlameWaveBrightnessPower == 1.35)
        #expect(store.agentFlameWaveBloomStrength == 1.0)
        #expect(store.agentFlameWavePurpleRed == 0.78)
        #expect(store.agentFlameWavePurpleGreen == 0.28)
        #expect(store.agentFlameWavePurpleBlue == 1.0)
        #expect(store.agentFlameWaveSparkRed == 1.0)
        #expect(store.agentFlameWaveSparkGreen == 1.0)
        #expect(store.agentFlameWaveSparkBlue == 1.0)
        #expect(store.agentFlameWaveColumnPitch == 5.8)
        #expect(store.agentFlameWaveWidthScale == 1.0)
        #expect(store.agentFlameWaveHorizontalOffset == 0)
        #expect(store.agentWorkingTextOffset == 0)
        #expect(store.agentSessionsTextOffset == 0)
        #expect(store.agentFlameWaveWaveNoise == 1.0)
        #expect(store.agentFlameWaveSparkNoise == 1.0)
        #expect(store.agentFlameWaveSparkDistribution == 1.65)
        #expect(store.agentFlameWaveSparkHorizontalCenter == 0.78)
        #expect(store.agentFlameWaveSparkHorizontalSpread == 0.30)
        #expect(store.agentFlameWaveSparkSpeed == 1.0)
        #expect(store.agentFlameWaveExpansionSpeed == 1.0)
        #expect(store.agentFlameWaveHorizontalDrift == 0.012)
        #expect(store.agentFlameWaveHorizontalDriftSpeed == 1.0)
        #expect(store.agentFlameWaveFadeDepth == 0.10)
        #expect(store.agentFlameWaveFadeSpeed == 1.0)
    }

    @Test("agent activity icon preferences persist selected styles and position")
    func agentActivityIconPreferencesPersistSelectedStylesAndPosition() {
        let defaults = makeDefaults()
        let store = PreferencesStore(defaults: defaults)

        store.showMenuBarIcon = false
        store.agentRunningIconStyle = .cascadeSymbol
        store.agentAttentionIconStyle = .bolt
        store.agentActivityIconPosition = .trailing
        store.agentActivityIconSize = 24
        store.agentActivityIconOffsetX = -7
        store.agentActivityIconOffsetY = 3
        store.agentActivityIconEffect = .bounce
        store.agentActivityNotchDisplayMode = .simple
        store.agentRunningIconRed = 0.1
        store.agentRunningIconGreen = 0.2
        store.agentRunningIconBlue = 0.3
        store.agentAttentionIconRed = 0.8
        store.agentAttentionIconGreen = 0.7
        store.agentAttentionIconBlue = 0.6
        store.agentRunningCustomIconPath = "/tmp/running.png"
        store.agentAttentionCustomIconPath = "/tmp/attention.svg"
        store.agentRunningNotchWidthAdjustment = 18
        store.agentRunningNotchHeightAdjustment = 4
        store.agentAttentionNotchWidthAdjustment = -12
        store.agentAttentionNotchHeightAdjustment = 8
        store.agentRunningSimpleNotchWidthAdjustment = 32
        store.agentRunningSimpleNotchHeightAdjustment = 5
        store.agentAttentionSimpleNotchWidthAdjustment = -24
        store.agentAttentionSimpleNotchHeightAdjustment = 10
        store.agentFlameWaveCellSize = 3.1
        store.agentFlameWaveGlowScale = 3.4
        store.agentFlameWaveGlowOpacity = 1.7
        store.agentFlameWaveLeadingBlur = 2.2
        store.agentFlameWaveBrightnessPower = 1.8
        store.agentFlameWaveBloomStrength = 2.4
        store.agentFlameWavePurpleRed = 0.3
        store.agentFlameWavePurpleGreen = 0.2
        store.agentFlameWavePurpleBlue = 0.95
        store.agentFlameWaveSparkRed = 0.7
        store.agentFlameWaveSparkGreen = 0.4
        store.agentFlameWaveSparkBlue = 0.9
        store.agentFlameWaveColumnPitch = 6.7
        store.agentFlameWaveWidthScale = 1.45
        store.agentFlameWaveHorizontalOffset = -18
        store.agentWorkingTextOffset = 26
        store.agentSessionsTextOffset = -14
        store.agentFlameWaveWaveNoise = 2.1
        store.agentFlameWaveSparkNoise = 1.9
        store.agentFlameWaveSparkDistribution = 2.7
        store.agentFlameWaveSparkHorizontalCenter = 0.44
        store.agentFlameWaveSparkHorizontalSpread = 0.22
        store.agentFlameWaveSparkSpeed = 2.8
        store.agentFlameWaveExpansionSpeed = 1.7
        store.agentFlameWaveHorizontalDrift = 0.055
        store.agentFlameWaveHorizontalDriftSpeed = 2.2
        store.agentFlameWaveFadeDepth = 0.48
        store.agentFlameWaveFadeSpeed = 1.6
        store.saveAgentFlameWavePreset()

        store.agentFlameWaveSparkSpeed = 0.5
        store.agentFlameWavePurpleRed = 0.9
        store.agentFlameWaveColumnPitch = 3.4
        store.agentFlameWaveWidthScale = 2.4
        store.agentFlameWaveHorizontalOffset = 24
        store.agentWorkingTextOffset = -40
        store.agentSessionsTextOffset = 38
        store.agentFlameWaveExpansionSpeed = 0.2
        store.agentFlameWaveHorizontalDrift = 0.001
        store.agentFlameWaveHorizontalDriftSpeed = 0.2
        store.agentFlameWaveFadeDepth = 0.01
        store.agentFlameWaveFadeSpeed = 0.2
        #expect(store.loadAgentFlameWavePreset())
        #expect(store.agentFlameWavePurpleRed == 0.3)
        #expect(store.agentFlameWaveColumnPitch == 6.7)
        #expect(store.agentFlameWaveWidthScale == 1.45)
        #expect(store.agentFlameWaveHorizontalOffset == -18)
        #expect(store.agentWorkingTextOffset == 26)
        #expect(store.agentSessionsTextOffset == -14)
        #expect(store.agentFlameWaveSparkSpeed == 2.8)
        #expect(store.agentFlameWaveExpansionSpeed == 1.7)
        #expect(store.agentFlameWaveHorizontalDrift == 0.055)
        #expect(store.agentFlameWaveHorizontalDriftSpeed == 2.2)
        #expect(store.agentFlameWaveFadeDepth == 0.48)
        #expect(store.agentFlameWaveFadeSpeed == 1.6)

        let restored = PreferencesStore(defaults: defaults)

        #expect(!restored.showMenuBarIcon)
        #expect(restored.agentRunningIconStyle == .cascadeSymbol)
        #expect(restored.agentAttentionIconStyle == .bolt)
        #expect(restored.agentActivityIconPosition == .trailing)
        #expect(restored.agentActivityIconSize == 24)
        #expect(restored.agentActivityIconOffsetX == -7)
        #expect(restored.agentActivityIconOffsetY == 3)
        #expect(restored.agentActivityIconEffect == .bounce)
        #expect(restored.agentActivityNotchDisplayMode == .simple)
        #expect(restored.agentRunningIconRed == 0.1)
        #expect(restored.agentRunningIconGreen == 0.2)
        #expect(restored.agentRunningIconBlue == 0.3)
        #expect(restored.agentAttentionIconRed == 0.8)
        #expect(restored.agentAttentionIconGreen == 0.7)
        #expect(restored.agentAttentionIconBlue == 0.6)
        #expect(restored.agentRunningCustomIconPath == "/tmp/running.png")
        #expect(restored.agentAttentionCustomIconPath == "/tmp/attention.svg")
        #expect(restored.agentRunningNotchWidthAdjustment == 18)
        #expect(restored.agentRunningNotchHeightAdjustment == 4)
        #expect(restored.agentAttentionNotchWidthAdjustment == -12)
        #expect(restored.agentAttentionNotchHeightAdjustment == 8)
        #expect(restored.agentRunningSimpleNotchWidthAdjustment == 32)
        #expect(restored.agentRunningSimpleNotchHeightAdjustment == 5)
        #expect(restored.agentAttentionSimpleNotchWidthAdjustment == -24)
        #expect(restored.agentAttentionSimpleNotchHeightAdjustment == 10)
        #expect(restored.agentFlameWaveCellSize == 3.1)
        #expect(restored.agentFlameWaveGlowScale == 3.4)
        #expect(restored.agentFlameWaveGlowOpacity == 1.7)
        #expect(restored.agentFlameWaveLeadingBlur == 2.2)
        #expect(restored.agentFlameWaveBrightnessPower == 1.8)
        #expect(restored.agentFlameWaveBloomStrength == 2.4)
        #expect(restored.agentFlameWavePurpleRed == 0.3)
        #expect(restored.agentFlameWavePurpleGreen == 0.2)
        #expect(restored.agentFlameWavePurpleBlue == 0.95)
        #expect(restored.agentFlameWaveSparkRed == 0.7)
        #expect(restored.agentFlameWaveSparkGreen == 0.4)
        #expect(restored.agentFlameWaveSparkBlue == 0.9)
        #expect(restored.agentFlameWaveColumnPitch == 6.7)
        #expect(restored.agentFlameWaveWidthScale == 1.45)
        #expect(restored.agentFlameWaveHorizontalOffset == -18)
        #expect(restored.agentWorkingTextOffset == 26)
        #expect(restored.agentSessionsTextOffset == -14)
        #expect(restored.agentFlameWaveWaveNoise == 2.1)
        #expect(restored.agentFlameWaveSparkNoise == 1.9)
        #expect(restored.agentFlameWaveSparkDistribution == 2.7)
        #expect(restored.agentFlameWaveSparkHorizontalCenter == 0.44)
        #expect(restored.agentFlameWaveSparkHorizontalSpread == 0.22)
        #expect(restored.agentFlameWaveSparkSpeed == 2.8)
        #expect(restored.agentFlameWaveExpansionSpeed == 1.7)
        #expect(restored.agentFlameWaveHorizontalDrift == 0.055)
        #expect(restored.agentFlameWaveHorizontalDriftSpeed == 2.2)
        #expect(restored.agentFlameWaveFadeDepth == 0.48)
        #expect(restored.agentFlameWaveFadeSpeed == 1.6)
        #expect(restored.hasSavedAgentFlameWavePreset)
        #expect(
            restored.agentNotchSizeAdjustment(isAttention: true, mode: .simple)
                == AgentNotchSizeAdjustment(widthAdjustment: -24, heightAdjustment: 10)
        )
    }

    @Test("agent activity icon styles include pixel symbols and system presets")
    func agentActivityIconStylesIncludePixelSymbolsAndSystemPresets() {
        let styles = Set(AgentActivityIconStyle.allCases)

        #expect(styles.contains(.none))
        #expect(styles.contains(.symbol))
        #expect(styles.contains(.cascadeSymbol))
        #expect(styles.contains(.command))
        #expect(styles.contains(.braces))
        #expect(styles.contains(.cpu))
        #expect(styles.contains(.network))
        #expect(styles.contains(.wand))
        #expect(styles.contains(.paperplane))
        #expect(styles.contains(.lifeGrid))
        #expect(styles.contains(.asciiPrompt))
        #expect(styles.contains(.asciiScan))
        #expect(styles.contains(.asciiPulse))
        #expect(AgentActivityIconStyle.lifeGrid.isPixelSymbol)
        #expect(AgentActivityIconStyle.asciiPrompt.isASCII)
        #expect(!AgentActivityIconStyle.none.isASCII)
        #expect(!AgentActivityIconStyle.none.isPixelSymbol)
        #expect(!AgentActivityIconStyle.lifeGrid.isASCII)

        for style in AgentActivityIconStyle.allCases {
            #expect(!style.title.isEmpty)
            #expect(!style.systemImageName.isEmpty)
            if style.isASCII {
                #expect(!style.asciiFrames.isEmpty)
            }
        }
    }

    @Test("agent life grid icon produces deterministic 6 by 6 animation cells")
    func agentLifeGridIconProducesDeterministic6By6AnimationCells() {
        let firstFrame = AgentLifeGridIcon.cells(for: 0)
        let animationFrames = Set((0..<8).map { AgentLifeGridIcon.cells(for: $0) })
        let renderedFrame = AgentLifeGridFrame.make(elapsed: 0.12)

        #expect(firstFrame.count == AgentLifeGridIcon.cellCount)
        #expect(firstFrame.contains(true))
        #expect(firstFrame == AgentLifeGridIcon.cells(for: 0))
        #expect(animationFrames.count > 1)
        #expect(renderedFrame.cells.count == AgentLifeGridIcon.cellCount)
        #expect(renderedFrame.cells.contains { $0.alive })
        #expect(renderedFrame.pulse >= 0)
        #expect(renderedFrame.pulse <= 1)
    }

    @Test("agent life grid animation targets display refresh rate")
    func agentLifeGridAnimationTargetsDisplayRefreshRate() {
        #expect(AgentAnimationFrameRatePolicy.targetFramesPerSecond(forDisplayRefreshRate: 60) == 60)
        #expect(AgentAnimationFrameRatePolicy.targetFramesPerSecond(forDisplayRefreshRate: 75) == 60)
        #expect(AgentAnimationFrameRatePolicy.targetFramesPerSecond(forDisplayRefreshRate: 120) == 120)
        #expect(AgentAnimationFrameRatePolicy.targetFramesPerSecond(forDisplayRefreshRate: nil) == 120)
    }

    @Test("agent activity icon effects include animation presets")
    func agentActivityIconEffectsIncludeAnimationPresets() {
        let effects = Set(AgentActivityIconEffect.allCases)

        #expect(effects.contains(.none))
        #expect(effects.contains(.glow))
        #expect(effects.contains(.breathe))
        #expect(effects.contains(.spin))
        #expect(effects.contains(.bounce))
        #expect(effects.contains(.edgeBloom))
        #expect(effects.contains(.flameWave))

        for effect in AgentActivityIconEffect.allCases {
            #expect(!effect.title.isEmpty)
            #expect(!effect.systemImageName.isEmpty)
        }
    }

    @Test("agent flame wave frame expands right with purple and white cells")
    func agentFlameWaveFrameExpandsRightWithPurpleAndWhiteCells() {
        let frame = AgentFlameWaveFrame.make(elapsed: 0.24)
        let nextSparkFrame = AgentFlameWaveFrame.make(elapsed: 0.36)
        let settledFrame = AgentFlameWaveFrame.make(elapsed: 2.0)
        let narrowFrame = AgentFlameWaveFrame.make(
            elapsed: 0.24,
            renderWidth: AgentFlameWaveFrame.columnPitch * 20
        )
        let wideFrame = AgentFlameWaveFrame.make(
            elapsed: 0.24,
            renderWidth: AgentFlameWaveFrame.columnPitch * 40
        )
        let leftOpacity = averageOpacity(in: frame.cells.filter { $0.centerX < 0.24 })
        let rightOpacity = averageOpacity(in: frame.cells.filter { $0.centerX > 0.74 })
        let tailWhiteCount = frame.cells.filter { $0.centerX > 0.62 && $0.colorRole == .white }.count
        let nextTailWhiteCount = nextSparkFrame.cells.filter { $0.centerX > 0.62 && $0.colorRole == .white }.count
        let tuning = AgentFlameWaveTuning(
            cellSize: 2.6,
            glowScale: 2.45,
            glowOpacity: 1,
            leadingBlur: 1,
            brightnessPower: 1.35,
            bloomStrength: 1
        )
        let oversizedTuning = AgentFlameWaveTuning(
            cellSize: 8,
            glowScale: 9,
            glowOpacity: 4,
            leadingBlur: 6,
            brightnessPower: 0.1,
            bloomStrength: 4,
            purpleColor: AgentFlameWaveSparkColor(red: -1, green: 2, blue: 0.25),
            sparkColor: AgentFlameWaveSparkColor(red: 2, green: -1, blue: 0.5),
            columnPitch: 50,
            horizontalOffset: 999,
            waveNoise: 8,
            sparkNoise: 8,
            sparkDistribution: 0.1,
            sparkHorizontalCenter: 2,
            sparkHorizontalSpread: 0.01,
            sparkSpeed: 9,
            expansionSpeed: 9,
            widthScale: 9,
            horizontalDrift: 0.2,
            horizontalDriftSpeed: 9,
            fadeDepth: 2,
            fadeSpeed: 9
        )
        let zeroTuning = AgentFlameWaveTuning(
            cellSize: 0,
            glowScale: 0,
            glowOpacity: 0,
            leadingBlur: 0,
            brightnessPower: 0,
            bloomStrength: 0,
            columnPitch: 0,
            horizontalOffset: 0,
            waveNoise: 0,
            sparkNoise: 0,
            sparkDistribution: 0,
            sparkHorizontalSpread: 0,
            sparkSpeed: 0,
            expansionSpeed: 0,
            widthScale: 0,
            horizontalDrift: 0,
            horizontalDriftSpeed: 0,
            fadeDepth: 0,
            fadeSpeed: 0
        )
        let concentratedSparkFrame = AgentFlameWaveFrame.make(
            elapsed: 0.36,
            tuning: AgentFlameWaveTuning(sparkDistribution: 3.6)
        )
        let slowGrowthFrame = AgentFlameWaveFrame.make(
            elapsed: 0.8,
            tuning: AgentFlameWaveTuning(expansionSpeed: 0.25)
        )
        let fastGrowthFrame = AgentFlameWaveFrame.make(
            elapsed: 0.8,
            tuning: AgentFlameWaveTuning(expansionSpeed: 2.0)
        )
        let driftedFrame = AgentFlameWaveFrame.make(
            elapsed: 0.8,
            tuning: AgentFlameWaveTuning(horizontalDrift: 0.06)
        )
        let fadedFrame = AgentFlameWaveFrame.make(
            elapsed: 0.8,
            tuning: AgentFlameWaveTuning(fadeDepth: 0.9)
        )
        let tightPitchFrame = AgentFlameWaveFrame.make(
            elapsed: 0.24,
            tuning: AgentFlameWaveTuning(columnPitch: 4.0),
            renderWidth: 80
        )
        let loosePitchFrame = AgentFlameWaveFrame.make(
            elapsed: 0.24,
            tuning: AgentFlameWaveTuning(columnPitch: 8.0),
            renderWidth: 80
        )
        let zeroControlFrame = AgentFlameWaveFrame.make(
            elapsed: 0.24,
            tuning: zeroTuning,
            renderWidth: 80
        )
        let stillVerticalFrame = AgentFlameWaveFrame.make(
            elapsed: 0.1,
            tuning: AgentFlameWaveTuning(waveNoise: 0)
        )
        let laterStillVerticalFrame = AgentFlameWaveFrame.make(
            elapsed: 1.4,
            tuning: AgentFlameWaveTuning(waveNoise: 0)
        )
        let movingVerticalFrame = AgentFlameWaveFrame.make(
            elapsed: 1.4,
            tuning: AgentFlameWaveTuning(waveNoise: 1)
        )
        let capBrightness = AgentFlameWaveDrawingPolicy.cellBrightness(displayProgress: 0, opacity: 0.4, tuning: tuning)
        let tailBrightness = AgentFlameWaveDrawingPolicy.cellBrightness(displayProgress: 1, opacity: 0.4, tuning: tuning)

        #expect(frame.cells.count == AgentFlameWaveFrame.cellCount)
        #expect(frame.columnCount == AgentFlameWaveFrame.columns)
        #expect(narrowFrame.columnCount == 21)
        #expect(wideFrame.columnCount == 41)
        #expect(wideFrame.cells.count > narrowFrame.cells.count)
        #expect(abs((AgentFlameWaveFrame.columnPitch * 20) / CGFloat(narrowFrame.columnCount - 1) - AgentFlameWaveFrame.columnPitch) < 0.001)
        #expect(abs((AgentFlameWaveFrame.columnPitch * 40) / CGFloat(wideFrame.columnCount - 1) - AgentFlameWaveFrame.columnPitch) < 0.001)
        #expect(AgentFlameWaveFrame.columns >= 100)
        #expect(AgentFlameWaveFrame.rows >= 7)
        #expect(frame.growthProgress > 0)
        #expect(frame.growthProgress < 1)
        #expect(settledFrame.growthProgress == 1)
        #expect(frame.cells.first?.centerX ?? 1 < frame.cells.last?.centerX ?? 0)
        #expect(frame.cells.contains { $0.colorRole == .purple })
        #expect(frame.cells.contains { $0.colorRole == .white })
        #expect(frame.cells.allSatisfy { $0.centerX >= 0 && $0.centerX <= 1 })
        #expect(rightOpacity > leftOpacity)
        #expect(tailWhiteCount != nextTailWhiteCount)
        #expect(capBrightness > tailBrightness)
        #expect(AgentFlameWaveDrawingPolicy.cellSide(tuning: oversizedTuning) == 5.2)
        #expect(oversizedTuning.glowScale == 8.0)
        #expect(oversizedTuning.glowOpacity == 3.0)
        #expect(oversizedTuning.leadingBlur == 4.0)
        #expect(oversizedTuning.brightnessPower == 0.1)
        #expect(oversizedTuning.bloomStrength == 3.0)
        #expect(oversizedTuning.purpleColor == AgentFlameWaveSparkColor(red: 0, green: 1, blue: 0.25))
        #expect(oversizedTuning.sparkColor == AgentFlameWaveSparkColor(red: 1, green: 0, blue: 0.5))
        #expect(oversizedTuning.columnPitch == 12.0)
        #expect(oversizedTuning.widthScale == 4.0)
        #expect(oversizedTuning.horizontalOffset == 240.0)
        #expect(oversizedTuning.waveNoise == 3.0)
        #expect(oversizedTuning.sparkNoise == 3.0)
        #expect(oversizedTuning.sparkDistribution == 0.1)
        #expect(oversizedTuning.sparkHorizontalCenter == 1.0)
        #expect(oversizedTuning.sparkHorizontalSpread == 0.01)
        #expect(oversizedTuning.sparkSpeed == 4.0)
        #expect(oversizedTuning.expansionSpeed == 4.0)
        #expect(oversizedTuning.horizontalDrift == 0.08)
        #expect(oversizedTuning.horizontalDriftSpeed == 4.0)
        #expect(oversizedTuning.fadeDepth == 0.95)
        #expect(oversizedTuning.fadeSpeed == 4.0)
        #expect(zeroTuning.cellSize == 0)
        #expect(zeroTuning.glowScale == 0)
        #expect(zeroTuning.glowOpacity == 0)
        #expect(zeroTuning.leadingBlur == 0)
        #expect(zeroTuning.brightnessPower == 0)
        #expect(zeroTuning.bloomStrength == 0)
        #expect(zeroTuning.columnPitch == 0)
        #expect(zeroTuning.horizontalOffset == 0)
        #expect(zeroTuning.waveNoise == 0)
        #expect(zeroTuning.sparkNoise == 0)
        #expect(zeroTuning.sparkDistribution == 0)
        #expect(zeroTuning.sparkHorizontalSpread == 0)
        #expect(zeroTuning.sparkSpeed == 0)
        #expect(zeroTuning.expansionSpeed == 0)
        #expect(zeroTuning.horizontalDrift == 0)
        #expect(zeroTuning.horizontalDriftSpeed == 0)
        #expect(zeroTuning.fadeDepth == 0)
        #expect(zeroTuning.fadeSpeed == 0)
        #expect(concentratedSparkFrame.cells.filter { $0.colorRole == .white }.count != frame.cells.filter { $0.colorRole == .white }.count)
        #expect(slowGrowthFrame.growthProgress < fastGrowthFrame.growthProgress)
        #expect(tightPitchFrame.columnCount == 21)
        #expect(loosePitchFrame.columnCount == 11)
        #expect(tightPitchFrame.cells.count > loosePitchFrame.cells.count)
        #expect(zeroControlFrame.columnCount > tightPitchFrame.columnCount)
        #expect(zeroControlFrame.cells.allSatisfy { $0.centerX >= 0 && $0.centerX <= 1 })
        #expect(zip(driftedFrame.cells, frame.cells).contains { abs($0.centerX - $1.centerX) > 0.001 })
        #expect(averageOpacity(in: fadedFrame.cells) < averageOpacity(in: frame.cells))
        #expect(zip(stillVerticalFrame.cells, laterStillVerticalFrame.cells).allSatisfy { abs($0.centerY - $1.centerY) < 0.0001 })
        #expect(zip(stillVerticalFrame.cells, movingVerticalFrame.cells).contains { abs($0.centerY - $1.centerY) > 0.001 })
    }

    private func averageOpacity(in cells: [AgentFlameWaveCellFrame]) -> Double {
        guard !cells.isEmpty else { return 0 }
        return cells.reduce(0) { $0 + $1.opacity } / Double(cells.count)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "PreferencesStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

private final class SpyClipboardChangeIgnorer: ClipboardChangeIgnoring {
    var ignoreCallCount = 0
    var ignoredItems: [ClipboardItem] = []

    func ignoreNextChange(matching item: ClipboardItem) {
        ignoreCallCount += 1
        ignoredItems.append(item)
    }
}
