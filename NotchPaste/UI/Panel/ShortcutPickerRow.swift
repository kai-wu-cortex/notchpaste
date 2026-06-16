import SwiftUI
import AppKit

/// 设置面板里的快捷键选择行：一行展示当前快捷键 + "更改"按钮；展开后列出预设 + 录制自定义。
struct ShortcutPickerRow: View {
    @ObservedObject var prefs: PreferencesStore

    @State private var isExpanded = false
    @State private var isRecording = false
    @State private var recordError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            mainRow
            if isExpanded {
                expandedContent
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Main row

    @State private var hovered = false

    private var mainRow: some View {
        Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                isExpanded.toggle()
                if !isExpanded { isRecording = false }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "keyboard")
                    .font(.system(size: 12))
                    .foregroundColor(textColor)
                    .frame(width: 16)
                Text("召唤快捷键")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(textColor)
                Spacer()
                Text(prefs.shortcut.displayName)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.55))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.white.opacity(0.4))
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(hovered ? Color.white.opacity(0.08) : .clear)
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
    }

    private var textColor: Color {
        .white.opacity(hovered ? 1.0 : 0.75)
    }

    // MARK: - Expanded

    @ViewBuilder
    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(GlobalShortcut.presets) { preset in
                PresetRow(
                    preset: preset,
                    isSelected: prefs.shortcut.id == preset.id
                ) {
                    prefs.shortcut = preset
                    isRecording = false
                    recordError = nil
                }
            }

            // 录制自定义快捷键
            CustomRecordRow(
                isRecording: $isRecording,
                isSelected: prefs.shortcut.id.hasPrefix("custom:"),
                currentDisplay: prefs.shortcut.id.hasPrefix("custom:") ? prefs.shortcut.displayName : nil,
                errorMessage: recordError,
                onCaptured: { result in
                    switch result {
                    case .success(let s):
                        prefs.shortcut = s
                        recordError = nil
                        isRecording = false
                    case .failure(let e):
                        recordError = e.errorDescription
                    }
                }
            )
        }
        .padding(.leading, 30)
        .padding(.trailing, 12)
        .padding(.bottom, 6)
    }
}

// MARK: - Preset row

private struct PresetRow: View {
    let preset: GlobalShortcut
    let isSelected: Bool
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 11))
                    .foregroundColor(isSelected ? .cyan : .white.opacity(0.4))
                Text(preset.displayName)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(hovered ? 1.0 : 0.7))
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(hovered ? Color.white.opacity(0.06) : .clear)
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
    }
}

// MARK: - Custom record row

private struct CustomRecordRow: View {
    @Binding var isRecording: Bool
    let isSelected: Bool
    let currentDisplay: String?
    let errorMessage: String?
    let onCaptured: (Result<GlobalShortcut, GlobalShortcut.CaptureError>) -> Void

    @State private var hovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 11))
                    .foregroundColor(isSelected ? .cyan : .white.opacity(0.4))

                if isRecording {
                    KeyCaptureView { result in
                        onCaptured(result)
                    }
                    .frame(height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.cyan.opacity(0.15))
                    )
                    .overlay(
                        Text("按下任意组合键…按 Esc 取消")
                            .font(.system(size: 11))
                            .foregroundColor(.cyan)
                    )
                } else {
                    Text(currentDisplay ?? "录制自定义")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(hovered ? 1.0 : 0.7))
                    Spacer()
                    Button("录制") {
                        isRecording = true
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 5).fill(Color.white)
                    )
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(hovered && !isRecording ? Color.white.opacity(0.06) : .clear)
            )
            .onHover { if !isRecording { hovered = $0 } }

            if let err = errorMessage {
                Text(err)
                    .font(.system(size: 10))
                    .foregroundColor(.red.opacity(0.85))
                    .padding(.leading, 30)
            }
        }
    }
}

// MARK: - NSEvent capture view

/// 一个 NSView 包装：成为 firstResponder 监听 keyDown，把 NSEvent 解析成 GlobalShortcut。
struct KeyCaptureView: NSViewRepresentable {
    let onCaptured: (Result<GlobalShortcut, GlobalShortcut.CaptureError>) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = CaptureNSView()
        view.onCaptured = onCaptured
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }
    }

    final class CaptureNSView: NSView {
        var onCaptured: ((Result<GlobalShortcut, GlobalShortcut.CaptureError>) -> Void)?
        override var acceptsFirstResponder: Bool { true }
        override func becomeFirstResponder() -> Bool { true }
        override func keyDown(with event: NSEvent) {
            // Esc 取消（用 reservedKey 错误意外占用，这里直接吞掉）
            if event.keyCode == 53 { return }
            onCaptured?(GlobalShortcut.capture(from: event))
        }
    }
}
