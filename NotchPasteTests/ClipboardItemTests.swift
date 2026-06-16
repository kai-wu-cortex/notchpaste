import Testing
import Foundation
@testable import NotchPaste

@Suite("ClipboardItem")
struct ClipboardItemTests {

    @Test("text item fields populate as constructed")
    func textItemFields() {
        let id = UUID()
        let date = Date(timeIntervalSince1970: 1_000_000)
        let item = ClipboardItem(
            id: id,
            type: .text("hello"),
            createdAt: date,
            pinned: false,
            sourceAppBundleID: "com.apple.Safari"
        )
        #expect(item.id == id)
        #expect(item.createdAt == date)
        #expect(item.pinned == false)
        #expect(item.sourceAppBundleID == "com.apple.Safari")
        if case .text(let s) = item.type {
            #expect(s == "hello")
        } else {
            Issue.record("Expected .text type")
        }
    }

    @Test("preview returns first 100 chars for long text")
    func previewLongText() {
        let long = String(repeating: "a", count: 500)
        let item = ClipboardItem.text(long)
        #expect(item.preview == String(long.prefix(100)))
    }

    @Test("preview returns whole text for short text")
    func previewShortText() {
        let item = ClipboardItem.text("short")
        #expect(item.preview == "short")
    }

    @Test("convenience text constructor sets fields")
    func textConvenience() {
        let item = ClipboardItem.text("hi")
        #expect(item.pinned == false)
        if case .text(let s) = item.type { #expect(s == "hi") }
        else { Issue.record("Expected .text") }
    }
}
