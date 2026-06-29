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

    @Test("extractItem returns image item for raw PNG data")
    func extractRawPNGImage() throws {
        let pb = NSPasteboard(name: NSPasteboard.Name("NotchPasteTest-rawpng"))
        pb.clearContents()
        let png = try makeImageData(type: .png)
        pb.setData(png, forType: .png)

        let item = ClipboardMonitor.extractItem(from: pb, sourceAppBundleID: nil)

        if case .image(let data) = item?.type {
            #expect(NSImage(data: data) != nil)
        } else {
            Issue.record("Expected .image")
        }
    }

    @Test("extractItem returns image item for raw JPEG data")
    func extractRawJPEGImage() throws {
        let pb = NSPasteboard(name: NSPasteboard.Name("NotchPasteTest-rawjpeg"))
        pb.clearContents()
        let jpeg = try makeImageData(type: .jpeg)
        pb.setData(jpeg, forType: NSPasteboard.PasteboardType("public.jpeg"))

        let item = ClipboardMonitor.extractItem(from: pb, sourceAppBundleID: nil)

        if case .image(let data) = item?.type {
            #expect(NSImage(data: data) != nil)
        } else {
            Issue.record("Expected .image")
        }
    }

    @Test("extractItem returns text item for RTF data")
    func extractRTFText() throws {
        let pb = NSPasteboard(name: NSPasteboard.Name("NotchPasteTest-rtf"))
        pb.clearContents()
        let attributed = NSAttributedString(string: "rich copied text")
        let rtf = try attributed.data(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        pb.setData(rtf, forType: .rtf)

        let item = ClipboardMonitor.extractItem(from: pb, sourceAppBundleID: nil)

        if case .text(let text) = item?.type {
            #expect(text == "rich copied text")
        } else {
            Issue.record("Expected .text")
        }
    }

    @Test("extractItem returns text item for HTML data")
    func extractHTMLText() {
        let pb = NSPasteboard(name: NSPasteboard.Name("NotchPasteTest-html"))
        pb.clearContents()
        pb.setString("<p>Copied <strong>HTML</strong> text</p>", forType: .html)

        let item = ClipboardMonitor.extractItem(from: pb, sourceAppBundleID: nil)

        if case .text(let text) = item?.type {
            #expect(text == "Copied HTML text")
        } else {
            Issue.record("Expected .text")
        }
    }

    @Test("extractItem returns url item for browser public url")
    func extractBrowserPublicURL() {
        let pb = NSPasteboard(name: NSPasteboard.Name("NotchPasteTest-public-url"))
        pb.clearContents()
        pb.setString("https://example.com/copied", forType: NSPasteboard.PasteboardType("public.url"))

        let item = ClipboardMonitor.extractItem(from: pb, sourceAppBundleID: "com.google.Chrome")

        if case .url(let raw, let url) = item?.type {
            #expect(raw == "https://example.com/copied")
            #expect(url.absoluteString == "https://example.com/copied")
        } else {
            Issue.record("Expected .url")
        }
    }

    @Test("extractItem returns url item for browser NSURL object")
    func extractBrowserNSURLObject() {
        let pb = NSPasteboard(name: NSPasteboard.Name("NotchPasteTest-nsurl"))
        pb.clearContents()
        pb.writeObjects([NSURL(string: "https://example.com/object")!])

        let item = ClipboardMonitor.extractItem(from: pb, sourceAppBundleID: "com.apple.Safari")

        if case .url(let raw, let url) = item?.type {
            #expect(raw == "https://example.com/object")
            #expect(url.absoluteString == "https://example.com/object")
        } else {
            Issue.record("Expected .url")
        }
    }

    @Test("extractItem returns text item for browser utf8 plain text")
    func extractBrowserUTF8PlainText() {
        let pb = NSPasteboard(name: NSPasteboard.Name("NotchPasteTest-utf8-text"))
        pb.clearContents()
        pb.setString("browser right click text", forType: NSPasteboard.PasteboardType("public.utf8-plain-text"))

        let item = ClipboardMonitor.extractItem(from: pb, sourceAppBundleID: "com.google.Chrome")

        if case .text(let text) = item?.type {
            #expect(text == "browser right click text")
        } else {
            Issue.record("Expected .text")
        }
    }

    @Test("pending self-write ignore does not swallow later different clipboard content")
    func pendingSelfWriteIgnoreDoesNotSwallowLaterDifferentClipboardContent() {
        let pb = NSPasteboard(name: NSPasteboard.Name("NotchPasteTest-ignore-matching"))
        pb.clearContents()
        let monitor = ClipboardMonitor(pasteboard: pb)

        monitor.ignoreNextChange(matching: ClipboardItem.text("self write"))
        pb.clearContents()
        pb.setString("external right click copy", forType: .string)
        let item = monitor.tick()

        if case .text(let text) = item?.type {
            #expect(text == "external right click copy")
        } else {
            Issue.record("Expected .text")
        }
    }

    private func makeImageData(type: NSBitmapImageRep.FileType) throws -> Data {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 1,
            pixelsHigh: 1,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 4,
            bitsPerPixel: 32
        )!
        rep.setColor(.red, atX: 0, y: 0)
        return try #require(rep.representation(using: type, properties: [:]))
    }
}
