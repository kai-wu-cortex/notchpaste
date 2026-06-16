import SwiftUI
import AppKit
import Combine

@MainActor
final class PillModel: ObservableObject {
    struct State: Equatable {
        var itemCount: Int = 0
        var copyHint: String? = nil
    }
    @Published var state = State()
}

@main
struct NotchPasteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var monitor: ClipboardMonitor!
    private var store: ClipboardStore!
    private var paster: PasteService!
    private var hotkey: HotkeyService!
    private var prefs: PreferencesStore!

    private var pillWindow: PillWindow!
    private var panelWindow: PanelWindow?
    private var panelVM: PanelViewModel!
    private let pillModel = PillModel()

    private var cancellables = Set<AnyCancellable>()
    private var copyHintTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        prefs = .shared
        do {
            store = try ClipboardStore(maxItems: prefs.maxItems)
        } catch {
            AppLogger.app.error("Failed to open ClipboardStore: \(error.localizedDescription, privacy: .public)")
            NSApp.terminate(nil)
            return
        }
        paster = PasteService(preferences: prefs)
        monitor = ClipboardMonitor()
        hotkey = HotkeyService()

        panelVM = PanelViewModel(store: store, paster: paster) { [weak self] in
            self?.panelWindow?.orderOut(nil)
        }

        setupPillWindow()
        wireMonitorToStore()
        wireStoreToPill()
        wireHotkey()

        monitor.start()
        AppLogger.app.info("NotchPaste launched")
    }

    // MARK: - Setup

    private func setupPillWindow() {
        let pillSize = NSSize(width: 60, height: 24)
        pillWindow = PillWindow(contentSize: pillSize)
        pillWindow.setContent(PillContainer(model: pillModel) { [weak self] in
            self?.togglePanel()
        })

        if let frame = ScreenGeometry.currentRightPillFrame(pillSize: pillSize) {
            pillWindow.setFrame(frame, display: true)
        } else if let screen = NSScreen.main {
            let f = NSRect(x: screen.frame.maxX - pillSize.width - 8,
                           y: screen.frame.maxY - pillSize.height - 4,
                           width: pillSize.width, height: pillSize.height)
            pillWindow.setFrame(f, display: true)
        }
        pillWindow.orderFrontRegardless()
    }

    private func wireMonitorToStore() {
        Task { [weak self] in
            guard let self else { return }
            for await item in self.monitor.stream {
                do {
                    try self.store.add(item)
                    await MainActor.run { self.flashCopyHint(item.preview) }
                } catch {
                    AppLogger.store.error("add failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    private func wireStoreToPill() {
        store.itemsPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] items in
                self?.pillModel.state.itemCount = items.count
            }
            .store(in: &cancellables)
    }

    private func wireHotkey() {
        hotkey.register { [weak self] in
            self?.togglePanel()
        }
    }

    private func flashCopyHint(_ text: String) {
        pillModel.state.copyHint = text
        copyHintTimer?.invalidate()
        copyHintTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.pillModel.state.copyHint = nil
            }
        }
    }

    private func togglePanel() {
        if let win = panelWindow, win.isVisible {
            win.orderOut(nil)
            return
        }
        showPanel()
    }

    private func showPanel() {
        let size = NSSize(width: 360, height: 480)
        let win = panelWindow ?? PanelWindow(contentSize: size, viewModel: panelVM)
        panelWindow = win
        if let screen = NSScreen.main {
            let notch = ScreenGeometry.notchFrame(
                screenFrame: screen.frame,
                auxiliaryTopLeftArea: screen.auxiliaryTopLeftArea,
                auxiliaryTopRightArea: screen.auxiliaryTopRightArea
            )
            let centerX: CGFloat = notch?.midX ?? screen.frame.midX
            let topY: CGFloat = (notch?.minY ?? screen.frame.maxY) - 4
            let frame = NSRect(
                x: centerX - size.width / 2,
                y: topY - size.height,
                width: size.width,
                height: size.height
            )
            win.setFrame(frame, display: true)
        }
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        panelVM.refresh()
    }
}

private struct PillContainer: View {
    @ObservedObject var model: PillModel
    let onTap: () -> Void
    var body: some View {
        PillView(itemCount: model.state.itemCount, copyHint: model.state.copyHint, onTap: onTap)
    }
}
