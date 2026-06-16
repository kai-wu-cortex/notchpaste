import SwiftUI

/// 常驻刘海右侧的 pill 视图。
/// 显示蓝色状态点 + 当前历史条数。复制事件触发时短暂膨胀并显示预览。
struct PillView: View {

    let itemCount: Int
    let copyHint: String?       // 非 nil 时显示预览文本（最近一次复制）；外部计时器控制清空
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.cyan)
                .frame(width: 6, height: 6)
            if let hint = copyHint {
                Text(hint)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 200, alignment: .leading)
                    .transition(.opacity)
            } else {
                Text("\(itemCount)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture { onTap() }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: copyHint)
    }
}

#Preview {
    PillView(itemCount: 42, copyHint: nil, onTap: {})
        .padding()
        .background(Color.gray)
}
