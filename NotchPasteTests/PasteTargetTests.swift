import Testing
@testable import NotchPaste

@Suite("PasteTarget")
struct PasteTargetTests {

    @Test("restoreFocus invokes captured focus restorer")
    func restoreFocusInvokesRestorer() {
        var restored = false
        let target = PasteTarget(app: nil, restoreFocusedElement: { restored = true })

        target.restoreFocus()

        #expect(restored)
    }
}
