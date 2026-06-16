import Foundation
import Carbon
import AppKit

/// 全局快捷键服务。用 Carbon RegisterEventHotKey 实现，支持运行时换绑。
/// 替代了之前依赖的 HotKey SPM 包 —— 我们要支持自定义快捷键，原包不够灵活。
@MainActor
final class HotkeyService {

    private static let signature: OSType = {
        // FourCharCode "NPST"
        let chars: [UInt8] = Array("NPST".utf8)
        return chars.reduce(0) { ($0 << 8) | OSType($1) }
    }()

    private var eventHandler: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private var current: GlobalShortcut = .default
    private var handler: (() -> Void)?

    /// 注册（或重新注册）快捷键并绑定回调。
    func register(shortcut: GlobalShortcut, handler: @escaping () -> Void) {
        self.current = shortcut
        self.handler = handler
        installEventHandlerIfNeeded()
        unregisterHotKey()
        registerHotKey()
        AppLogger.hotkey.info("Registered global shortcut \(shortcut.displayName, privacy: .public)")
    }

    /// 仅切换快捷键键位，不改回调。
    func updateShortcut(_ shortcut: GlobalShortcut) {
        self.current = shortcut
        guard eventHandler != nil else { return }
        unregisterHotKey()
        registerHotKey()
        AppLogger.hotkey.info("Updated shortcut to \(shortcut.displayName, privacy: .public)")
    }

    func unregister() {
        unregisterHotKey()
        if let eh = eventHandler {
            RemoveEventHandler(eh)
            eventHandler = nil
        }
        handler = nil
    }

    // MARK: - Internals

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }
                var id = EventHotKeyID()
                let st = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &id
                )
                guard st == noErr, id.signature == HotkeyService.signature else {
                    return noErr
                }
                let svc = Unmanaged<HotkeyService>.fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in svc.handler?() }
                return noErr
            },
            1,
            &spec,
            selfPtr,
            &eventHandler
        )
    }

    private func registerHotKey() {
        guard hotKeyRef == nil else { return }
        let id = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(
            current.keyCode,
            current.carbonModifiers,
            id,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if status != noErr {
            AppLogger.hotkey.error("RegisterEventHotKey failed: \(status, privacy: .public)")
        }
    }

    private func unregisterHotKey() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }
}
