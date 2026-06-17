import SwiftUI
import AppKit
import Combine

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
    private var menuBar: MenuBarController!
    private var notchDetector: NotchAppDetector!

    private var notchController: NotchWindowController!
    private var panelVM: PanelViewModel!

    private var cancellables = Set<AnyCancellable>()
    private var copyHintTimer: Timer?
    private var screenChangeObserver: NSObjectProtocol?
    private var hasPromptedAccessibility = false

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
        // 让 paster 能在写剪贴板前通知 monitor 忽略下一次回流
        paster.monitor = monitor
        // 隐私模式：根据 prefs 实时切监听开关
        monitor.isMonitoringEnabled = prefs.monitoringEnabled
        hotkey = HotkeyService()
        notchDetector = NotchAppDetector()

        panelVM = PanelViewModel(store: store, paster: paster) { [weak self] () -> PasteTarget? in
            // 关闭面板，返回打开时记录的目标 app 和焦点元素，供粘贴时恢复回去
            let target = self?.notchController?.viewModel.previousPasteTarget
            self?.notchController?.viewModel.notchClose()
            return target
        }

        setupMenuBar()
        setupNotchWindow()
        wireMonitorToStore()
        wireStoreToPanel()
        wirePrefsToMonitor()
        wireDetectorToViewModel()
        wireHotkey()

        monitor.start()
        VibeAgentBridge.shared.start()

        if !paster.isAccessibilityTrusted() && !hasPromptedAccessibility {
            hasPromptedAccessibility = true
            _ = paster.isAccessibilityTrusted(promptIfNeeded: true)
        }

        // 屏幕配置变化（连接显示器、分辨率改变）：重建窗口
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.setupNotchWindow() }
        }

        AppLogger.app.info("NotchPaste launched")
    }

    // MARK: - Setup

    private func setupMenuBar() {
        menuBar = MenuBarController(
            onShowPanel: { [weak self] in self?.notchController?.viewModel.notchOpen(reason: .click) },
            onRequestPermission: { [weak self] in self?.forceRequestAccessibility() }
        )
    }

    private func setupNotchWindow() {
        guard let screen = NSScreen.builtin else {
            AppLogger.app.error("No builtin screen")
            return
        }
        // 销毁旧窗口
        notchController?.close()

        notchController = NotchWindowController(
            screen: screen,
            panelVM: panelVM,
            onRequestPermission: { [weak self] in self?.forceRequestAccessibility() },
            onQuit: { NSApp.terminate(nil) }
        )
        notchController.showWindow(nil)
        AppLogger.app.info("Notch window set up on screen \(screen.localizedName, privacy: .public)")
    }

    // MARK: - Wiring

    private func wireMonitorToStore() {
        Task { [weak self] in
            guard let self else { return }
            for await item in self.monitor.stream {
                do {
                    try self.store.add(item)
                    await MainActor.run { self.flashCopyHint(for: item) }
                } catch {
                    AppLogger.store.error("add failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    private func wireStoreToPanel() {
        store.itemsPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] items in
                self?.notchController?.viewModel.itemCount = items.count
            }
            .store(in: &cancellables)
    }

    private func wireDetectorToViewModel() {
        notchDetector.$isOtherNotchAppRunning
            .receive(on: RunLoop.main)
            .sink { [weak self] occupied in
                self?.notchController?.viewModel.avoidanceMode = occupied
            }
            .store(in: &cancellables)
    }

    /// 把偏好里的隐私开关接到 monitor，并把状态同步给 ViewModel 显示。
    private func wirePrefsToMonitor() {
        prefs.$monitoringEnabled
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                self?.monitor.isMonitoringEnabled = enabled
                self?.notchController?.viewModel.monitoringEnabled = enabled
                AppLogger.app.info("monitoring \(enabled ? "enabled" : "disabled", privacy: .public)")
            }
            .store(in: &cancellables)
    }

    private func wireHotkey() {
        hotkey.register(shortcut: prefs.shortcut) { [weak self] in
            self?.notchController?.viewModel.toggle()
        }
        // 偏好里换快捷键 → 实时重注册
        prefs.$shortcut
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] new in
                self?.hotkey.updateShortcut(new)
            }
            .store(in: &cancellables)
    }

    // MARK: - Helpers

    private func flashCopyHint(for item: ClipboardItem) {
        let hint: NotchViewModel.CopyHint
        let duration: TimeInterval
        switch item.type {
        case .text(let s):
            hint = .text(String(s.prefix(100)))
            duration = 1.2
        case .url(let raw, _):
            hint = .text(String(raw.prefix(100)))
            duration = 1.5
        case .file(let urls):
            hint = .file(urls: urls)
            duration = 2.0
        case .image(let data):
            hint = .image(data)
            duration = 2.0
        }
        notchController?.viewModel.copyHint = hint
        copyHintTimer?.invalidate()
        copyHintTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.notchController?.viewModel.copyHint = nil
            }
        }
    }

    private func forceRequestAccessibility() {
        paster.requestAccessibilityAndOpenPreferences()
    }
}
