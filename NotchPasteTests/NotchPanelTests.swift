import AppKit
import Testing
@testable import NotchPaste

@Suite("NotchPanel")
struct NotchPanelTests {

    @MainActor
    @Test("prepareForBackgroundPaste clears focused control")
    func prepareForBackgroundPasteClearsFocusedControl() {
        let panel = NotchPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 200))
        let content = NSView(frame: panel.contentView?.bounds ?? .zero)
        let field = NSTextField(frame: NSRect(x: 20, y: 20, width: 180, height: 24))
        content.addSubview(field)
        panel.contentView = content

        #expect(panel.makeFirstResponder(field))
        let focusedResponder = panel.firstResponder
        #expect(focusedResponder != nil)

        panel.prepareForBackgroundPaste()

        #expect(panel.firstResponder !== focusedResponder)
        #expect(panel.ignoresMouseEvents)
    }
}
