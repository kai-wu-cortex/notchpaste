import CoreGraphics
import Testing
@testable import NotchPaste

@Suite("NotchViewModel")
@MainActor
struct NotchViewModelTests {

    @Test("opened panel exposes clipboard and vibe tabs")
    func openedPanelExposesClipboardAndVibeTabs() {
        #expect(NotchViewModel.ContentType.panelTabs == [.list, .vibe])
    }

    @Test("opened header controls reveal after animation critical path")
    func openedHeaderControlsRevealAfterAnimationCriticalPath() {
        #expect(NotchOpenedChromePolicy.contentRevealDelay(for: .vibe) >= NotchViewModel.openAnimationResponse)
        #expect(NotchOpenedChromePolicy.contentRevealDelay(for: .settings) >= NotchViewModel.openAnimationResponse)
        #expect(NotchOpenedChromePolicy.contentRevealDelay < NotchOpenedChromePolicy.controlsRevealDelay)
        #expect(NotchOpenedChromePolicy.controlsRevealDelay >= 0.42)
    }

    @Test("opened content reveal keeps a stable content slot height")
    func openedContentRevealKeepsStableContentSlotHeight() {
        #expect(NotchOpenedChromePolicy.contentSlotHeight(
            notchHeight: 420,
            headerHeight: 32,
            bottomInset: 12
        ) == 376)
        #expect(NotchOpenedChromePolicy.contentSlotHeight(
            notchHeight: 32,
            headerHeight: 40,
            bottomInset: 12
        ) == 0)
    }

    @Test("deferred opening work waits until animation critical path ends")
    func deferredOpeningWorkWaitsUntilAnimationCriticalPathEnds() {
        #expect(NotchOpenPerformancePolicy.deferredWorkDelay > NotchViewModel.openAnimationResponse)
    }

    @Test("clipboard list reveals with notch expansion")
    func clipboardListRevealsWithNotchExpansion() {
        #expect(NotchOpenedChromePolicy.contentRevealDelay(for: .list) == 0)
        #expect(NotchOpenedChromePolicy.contentRevealDelay(for: .vibe) == NotchOpenedChromePolicy.contentRevealDelay)
        #expect(NotchOpenedChromePolicy.contentRevealDelay(for: .settings) == NotchOpenedChromePolicy.contentRevealDelay)
    }

    @Test("agent running expansion uses clipboard hint timing")
    func agentRunningExpansionUsesClipboardHintTiming() {
        #expect(NotchClosedExpansionAnimationPolicy.response == 0.32)
        #expect(NotchClosedExpansionAnimationPolicy.dampingFraction == 0.78)
    }

    @Test("agent closed status strip mirrors vibe island copy")
    func agentClosedStatusStripMirrorsVibeIslandCopy() {
        #expect(AgentClosedStatusStripPolicy.title(for: .running) == "Working...")
        #expect(AgentClosedStatusStripPolicy.title(for: .needsInteraction) == "Needs input")
        #expect(AgentClosedStatusStripPolicy.sessionsText(count: 1) == "1 session")
        #expect(AgentClosedStatusStripPolicy.sessionsText(count: 5) == "5 sessions")
    }

    @Test("agent closed status strip supports detailed and simple modes")
    func agentClosedStatusStripSupportsDetailedAndSimpleModes() {
        #expect(AgentClosedStatusStripPolicy.title(for: .running, mode: .detailed) == "Working...")
        #expect(AgentClosedStatusStripPolicy.sessionsText(count: 2, mode: .detailed) == "2 sessions")
        #expect(AgentClosedStatusStripPolicy.title(for: .running, mode: .simple).isEmpty)
        #expect(AgentClosedStatusStripPolicy.sessionsText(count: 2, mode: .simple).isEmpty)
        #expect(
            AgentClosedStatusStripPolicy.extraWidth(for: .running, mode: .simple)
                < AgentClosedStatusStripPolicy.extraWidth(for: .running, mode: .detailed)
        )
    }

    @Test("debug unlock counter triggers on fifth fast tap")
    func debugUnlockCounterTriggersOnFifthFastTap() {
        var counter = DebugUnlockTapCounter(resetInterval: 3)

        let first = counter.registerTap(at: 0.0)
        let second = counter.registerTap(at: 0.4)
        let third = counter.registerTap(at: 0.8)
        let fourth = counter.registerTap(at: 1.2)
        let fifth = counter.registerTap(at: 1.6)

        #expect(!first)
        #expect(!second)
        #expect(!third)
        #expect(!fourth)
        #expect(fifth)
        #expect(counter.tapCount == 0)
    }

    @Test("debug unlock counter resets stale click sequence")
    func debugUnlockCounterResetsStaleClickSequence() {
        var counter = DebugUnlockTapCounter(resetInterval: 3)

        let first = counter.registerTap(at: 0.0)
        let second = counter.registerTap(at: 0.4)
        let stale = counter.registerTap(at: 3.8)

        #expect(!first)
        #expect(!second)
        #expect(!stale)
        #expect(counter.tapCount == 1)

        let resumedSecond = counter.registerTap(at: 4.0)
        let resumedThird = counter.registerTap(at: 4.2)
        let resumedFourth = counter.registerTap(at: 4.4)
        let resumedFifth = counter.registerTap(at: 4.6)

        #expect(!resumedSecond)
        #expect(!resumedThird)
        #expect(!resumedFourth)
        #expect(resumedFifth)
    }

    @Test("agent activity notch size policy applies side width adjustment")
    func agentActivityNotchSizePolicyAppliesSideWidthAdjustment() {
        let base = CGSize(width: 180, height: 32)
        let normal = AgentActivityNotchSizePolicy.size(
            base: base,
            activity: .running,
            mode: .detailed,
            widthAdjustment: 0,
            heightAdjustment: 0
        )
        let wider = AgentActivityNotchSizePolicy.size(
            base: base,
            activity: .running,
            mode: .detailed,
            widthAdjustment: 86,
            heightAdjustment: 0
        )

        #expect(wider.width == normal.width + 172)
        #expect(
            AgentActivityNotchSizePolicy.size(
                base: base,
                activity: .running,
                mode: .simple,
                widthAdjustment: 0,
                heightAdjustment: 0
            ).width < normal.width
        )
    }

    @Test("notch width adjustment preview is centered and exposes yellow edge markers")
    func notchWidthAdjustmentPreviewIsCenteredAndExposesYellowEdgeMarkers() {
        let screenWidth: CGFloat = 1_200
        let size = CGSize(width: 640, height: 41)
        let metrics = NotchWidthAdjustmentPreviewPolicy.metrics(
            screenWidth: screenWidth,
            notchSize: size
        )

        #expect(metrics.width == 640)
        #expect(metrics.height == 41)
        #expect(metrics.leadingMarkerX == 280)
        #expect(metrics.trailingMarkerX == 920)
        #expect(metrics.markerColorName == "yellow")
    }

    @Test("agent running state changes animate only while notch is closed")
    func agentRunningStateChangesAnimateOnlyWhileNotchIsClosed() {
        #expect(NotchAgentActivityTransitionPolicy.shouldAnimateClosedExpansion(
            from: .idle,
            to: .running,
            status: .closed
        ))
        #expect(NotchAgentActivityTransitionPolicy.shouldAnimateClosedExpansion(
            from: .running,
            to: .idle,
            status: .closed
        ))
        #expect(!NotchAgentActivityTransitionPolicy.shouldAnimateClosedExpansion(
            from: .running,
            to: .needsInteraction,
            status: .closed
        ))
        #expect(!NotchAgentActivityTransitionPolicy.shouldAnimateClosedExpansion(
            from: .idle,
            to: .running,
            status: .opened
        ))
    }

    @Test("vibe tab uses native short title")
    func vibeTabUsesNativeShortTitle() {
        #expect(NotchViewModel.ContentType.vibe.headerTitle(itemCount: 12) == "Vibe")
        #expect(NotchViewModel.ContentType.vibe.helpTitle == "Vibe")
    }

    @Test("closing panel resets content to clipboard")
    func closingPanelResetsContentToClipboard() {
        let model = NotchViewModel(
            deviceNotchRect: .init(x: 0, y: 0, width: 180, height: 32),
            screenRect: .init(x: 0, y: 0, width: 1512, height: 982),
            windowHeight: 750,
            hasPhysicalNotch: true
        )
        model.notchOpen(reason: .click)
        model.contentType = .vibe

        model.notchClose()

        #expect(model.contentType == .list)
    }

    @Test("agent interaction opens vibe content")
    func agentInteractionOpensVibeContent() {
        let model = NotchViewModel(
            deviceNotchRect: .init(x: 0, y: 0, width: 180, height: 32),
            screenRect: .init(x: 0, y: 0, width: 1512, height: 982),
            windowHeight: 750,
            hasPhysicalNotch: true
        )

        model.presentAgentInteraction()

        #expect(model.status == .opened)
        #expect(model.contentType == .vibe)
    }

    @Test("agent attention opens only when interaction is needed")
    func agentAttentionOpensOnlyWhenInteractionIsNeeded() {
        let model = NotchViewModel(
            deviceNotchRect: .init(x: 0, y: 0, width: 180, height: 32),
            screenRect: .init(x: 0, y: 0, width: 1512, height: 982),
            windowHeight: 750,
            hasPhysicalNotch: true
        )

        model.presentAgentAttention(.running)
        #expect(model.status == .closed)
        #expect(model.contentType == .list)

        model.presentAgentAttention(.needsInteraction)
        #expect(model.status == .opened)
        #expect(model.contentType == .vibe)
    }
}
