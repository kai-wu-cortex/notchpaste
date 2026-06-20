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
