import Foundation
import Carbon
import AppKit

/// 全局快捷键描述：4 个预设 + 自定义。
/// 序列化形式：预设 id（如 "command+shift+v"）或 "custom:<keyCode>:<modifiers>"。
struct GlobalShortcut: Identifiable, Equatable, Codable {
    let id: String
    let displayName: String
    let keyCode: UInt32
    let carbonModifiers: UInt32

    /// 4 个预设，覆盖大多数用户偏好。
    static let presets: [GlobalShortcut] = [
        GlobalShortcut(
            id: "command+shift+v",
            displayName: "⇧ ⌘ V",
            keyCode: UInt32(kVK_ANSI_V),
            carbonModifiers: UInt32(cmdKey | shiftKey)
        ),
        GlobalShortcut(
            id: "option+space",
            displayName: "⌥ Space",
            keyCode: UInt32(kVK_Space),
            carbonModifiers: UInt32(optionKey)
        ),
        GlobalShortcut(
            id: "command+shift+space",
            displayName: "⇧ ⌘ Space",
            keyCode: UInt32(kVK_Space),
            carbonModifiers: UInt32(cmdKey | shiftKey)
        ),
        GlobalShortcut(
            id: "control+space",
            displayName: "⌃ Space",
            keyCode: UInt32(kVK_Space),
            carbonModifiers: UInt32(controlKey)
        )
    ]

    static let `default` = presets[0]

    // MARK: - Persistence

    static func fromConfig(_ value: String) -> GlobalShortcut {
        if let p = presets.first(where: { $0.id == value }) {
            return p
        }
        let parts = value.split(separator: ":")
        guard parts.count == 3, parts[0] == "custom",
              let keyCode = UInt32(parts[1]),
              let modifiers = UInt32(parts[2]) else {
            return .default
        }
        return GlobalShortcut(
            id: value,
            displayName: Self.displayName(keyCode: keyCode, modifiers: modifiers),
            keyCode: keyCode,
            carbonModifiers: modifiers
        )
    }

    // MARK: - Capture from NSEvent

    enum CaptureError: Error, LocalizedError {
        case noModifier
        case reservedKey

        var errorDescription: String? {
            switch self {
            case .noModifier:
                return "快捷键至少需要包含 Command、Control 或 Option。"
            case .reservedKey:
                return "这个按键不适合作为全局快捷键。"
            }
        }
    }

    /// 把 NSEvent.keyDown 解析为合法的 GlobalShortcut（用于设置里的"录制快捷键"按钮）。
    static func capture(from event: NSEvent) -> Result<GlobalShortcut, CaptureError> {
        let modifiers = carbonModifiers(from: event.modifierFlags)
        guard modifiers & UInt32(cmdKey | controlKey | optionKey) != 0 else {
            return .failure(.noModifier)
        }
        let keyCode = UInt32(event.keyCode)
        let reserved: Set<UInt32> = [
            UInt32(kVK_Escape),
            UInt32(kVK_Return),
            UInt32(kVK_ANSI_KeypadEnter),
            UInt32(kVK_Tab),
            UInt32(kVK_Delete),
            UInt32(kVK_ForwardDelete)
        ]
        if reserved.contains(keyCode) {
            return .failure(.reservedKey)
        }
        return .success(GlobalShortcut(
            id: "custom:\(keyCode):\(modifiers)",
            displayName: displayName(keyCode: keyCode, modifiers: modifiers),
            keyCode: keyCode,
            carbonModifiers: modifiers
        ))
    }

    // MARK: - Display

    private static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        let m = flags.intersection(.deviceIndependentFlagsMask)
        var r: UInt32 = 0
        if m.contains(.command) { r |= UInt32(cmdKey) }
        if m.contains(.shift)   { r |= UInt32(shiftKey) }
        if m.contains(.option)  { r |= UInt32(optionKey) }
        if m.contains(.control) { r |= UInt32(controlKey) }
        return r
    }

    private static func displayName(keyCode: UInt32, modifiers: UInt32) -> String {
        let mods = modifierString(modifiers)
        let key = keyDisplayName(keyCode)
        return [mods, key].filter { !$0.isEmpty }.joined(separator: " ")
    }

    private static func modifierString(_ m: UInt32) -> String {
        var parts: [String] = []
        if m & UInt32(controlKey) != 0 { parts.append("⌃") }
        if m & UInt32(optionKey)  != 0 { parts.append("⌥") }
        if m & UInt32(shiftKey)   != 0 { parts.append("⇧") }
        if m & UInt32(cmdKey)     != 0 { parts.append("⌘") }
        return parts.joined(separator: " ")
    }

    private static func keyDisplayName(_ keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_Space: return "Space"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_Home: return "Home"
        case kVK_End: return "End"
        case kVK_PageUp: return "Page Up"
        case kVK_PageDown: return "Page Down"
        case kVK_F1...kVK_F20: return "F\(Int(keyCode) - kVK_F1 + 1)"
        default: return keyNameFromLayout(keyCode) ?? "Key \(keyCode)"
        }
    }

    private static func keyNameFromLayout(_ keyCode: UInt32) -> String? {
        guard
            let inputSource = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
            let layoutPtr = TISGetInputSourceProperty(inputSource, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }

        let layoutData = unsafeBitCast(layoutPtr, to: CFData.self)
        let layout = unsafeBitCast(CFDataGetBytePtr(layoutData), to: UnsafePointer<UCKeyboardLayout>.self)
        var deadKeyState: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)

        let status = UCKeyTranslate(
            layout,
            UInt16(keyCode),
            UInt16(kUCKeyActionDisplay),
            0,
            UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            characters.count,
            &length,
            &characters
        )
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: characters, count: length).uppercased()
    }
}
