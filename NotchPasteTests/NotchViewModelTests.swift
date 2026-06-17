import Testing
@testable import NotchPaste

@Suite("NotchViewModel")
@MainActor
struct NotchViewModelTests {

    @Test("opened panel exposes clipboard and vibe tabs")
    func openedPanelExposesClipboardAndVibeTabs() {
        #expect(NotchViewModel.ContentType.panelTabs == [.list, .vibe])
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
}
