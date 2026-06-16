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

private final class SpyClipboardChangeIgnorer: ClipboardChangeIgnoring {
    var ignoreCallCount = 0
    var ignoredItems: [ClipboardItem] = []

    func ignoreNextChange(matching item: ClipboardItem) {
        ignoreCallCount += 1
        ignoredItems.append(item)
    }
}
