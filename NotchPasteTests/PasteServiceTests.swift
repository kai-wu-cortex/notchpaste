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

        #expect(store.agentRunningIconStyle == .spinner)
        #expect(store.agentAttentionIconStyle == .spinner)
        #expect(store.agentActivityIconPosition == .leading)
        #expect(store.agentActivityIconSize == 18)
        #expect(store.agentActivityIconOffsetX == 0)
        #expect(store.agentActivityIconOffsetY == 0)
        #expect(store.agentActivityIconEffect == .glow)
        #expect(store.agentRunningCustomIconPath == nil)
        #expect(store.agentAttentionCustomIconPath == nil)
        #expect(store.agentRunningNotchWidthAdjustment == 0)
        #expect(store.agentRunningNotchHeightAdjustment == 0)
        #expect(store.agentAttentionNotchWidthAdjustment == 0)
        #expect(store.agentAttentionNotchHeightAdjustment == 0)
    }

    @Test("agent activity icon preferences persist selected styles and position")
    func agentActivityIconPreferencesPersistSelectedStylesAndPosition() {
        let defaults = makeDefaults()
        let store = PreferencesStore(defaults: defaults)

        store.agentRunningIconStyle = .cascadeSymbol
        store.agentAttentionIconStyle = .bolt
        store.agentActivityIconPosition = .trailing
        store.agentActivityIconSize = 24
        store.agentActivityIconOffsetX = -7
        store.agentActivityIconOffsetY = 3
        store.agentActivityIconEffect = .bounce
        store.agentRunningCustomIconPath = "/tmp/running.png"
        store.agentAttentionCustomIconPath = "/tmp/attention.svg"
        store.agentRunningNotchWidthAdjustment = 18
        store.agentRunningNotchHeightAdjustment = 4
        store.agentAttentionNotchWidthAdjustment = -12
        store.agentAttentionNotchHeightAdjustment = 8

        let restored = PreferencesStore(defaults: defaults)

        #expect(restored.agentRunningIconStyle == .cascadeSymbol)
        #expect(restored.agentAttentionIconStyle == .bolt)
        #expect(restored.agentActivityIconPosition == .trailing)
        #expect(restored.agentActivityIconSize == 24)
        #expect(restored.agentActivityIconOffsetX == -7)
        #expect(restored.agentActivityIconOffsetY == 3)
        #expect(restored.agentActivityIconEffect == .bounce)
        #expect(restored.agentRunningCustomIconPath == "/tmp/running.png")
        #expect(restored.agentAttentionCustomIconPath == "/tmp/attention.svg")
        #expect(restored.agentRunningNotchWidthAdjustment == 18)
        #expect(restored.agentRunningNotchHeightAdjustment == 4)
        #expect(restored.agentAttentionNotchWidthAdjustment == 18)
        #expect(restored.agentAttentionNotchHeightAdjustment == 8)
    }

    @Test("agent activity icon styles include pixel symbols and system presets")
    func agentActivityIconStylesIncludePixelSymbolsAndSystemPresets() {
        let styles = Set(AgentActivityIconStyle.allCases)

        #expect(styles.contains(.symbol))
        #expect(styles.contains(.cascadeSymbol))
        #expect(styles.contains(.command))
        #expect(styles.contains(.braces))
        #expect(styles.contains(.cpu))
        #expect(styles.contains(.network))
        #expect(styles.contains(.wand))
        #expect(styles.contains(.paperplane))

        for style in AgentActivityIconStyle.allCases {
            #expect(!style.title.isEmpty)
            #expect(!style.systemImageName.isEmpty)
        }
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

        for effect in AgentActivityIconEffect.allCases {
            #expect(!effect.title.isEmpty)
            #expect(!effect.systemImageName.isEmpty)
        }
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
