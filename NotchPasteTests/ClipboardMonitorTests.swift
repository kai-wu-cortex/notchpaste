import Testing
import AppKit
@testable import NotchPaste

@Suite("ClipboardMonitor")
struct ClipboardMonitorTests {

    @Test("extractItem returns nil if no usable types")
    func extractEmpty() {
        let pb = NSPasteboard(name: NSPasteboard.Name("NotchPasteTest-empty"))
        pb.clearContents()
        let item = ClipboardMonitor.extractItem(from: pb, sourceAppBundleID: nil)
        #expect(item == nil)
    }

    @Test("extractItem returns text item for plain string")
    func extractText() {
        let pb = NSPasteboard(name: NSPasteboard.Name("NotchPasteTest-text"))
        pb.clearContents()
        pb.setString("clipboard text", forType: .string)
        let item = ClipboardMonitor.extractItem(from: pb, sourceAppBundleID: "com.test.app")
        #expect(item != nil)
        if case .text(let s) = item?.type {
            #expect(s == "clipboard text")
        } else {
            Issue.record("Expected .text")
        }
        #expect(item?.sourceAppBundleID == "com.test.app")
    }

    @Test("extractItem ignores empty string")
    func extractEmptyString() {
        let pb = NSPasteboard(name: NSPasteboard.Name("NotchPasteTest-emptystr"))
        pb.clearContents()
        pb.setString("", forType: .string)
        let item = ClipboardMonitor.extractItem(from: pb, sourceAppBundleID: nil)
        #expect(item == nil)
    }
}
