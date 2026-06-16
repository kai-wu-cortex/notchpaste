import SwiftUI

/// MacBook 物理刘海形状的 SwiftUI Shape：顶部两个凹角 + 底部两个外凸圆角，
/// 看起来与刘海硬件无缝拼接。两个 radius 可动画过渡 —— 用于"展开/收起"形变。
///
/// 设计理念参考 farouqaldori/vibe-notch (Apache 2.0)，几何由我方独立实现。
struct NotchShape: Shape {
    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat

    init(topCornerRadius: CGFloat = 6, bottomCornerRadius: CGFloat = 14) {
        self.topCornerRadius = topCornerRadius
        self.bottomCornerRadius = bottomCornerRadius
    }

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let tr = topCornerRadius
        let br = bottomCornerRadius

        // 起点：左上角顶端（贴齐屏幕物理顶部）
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))

        // 顶左凹角（向内弯曲）
        p.addQuadCurve(
            to: CGPoint(x: rect.minX + tr, y: rect.minY + tr),
            control: CGPoint(x: rect.minX + tr, y: rect.minY)
        )

        // 左侧直边
        p.addLine(to: CGPoint(x: rect.minX + tr, y: rect.maxY - br))

        // 底左圆角（向外弯曲）
        p.addQuadCurve(
            to: CGPoint(x: rect.minX + tr + br, y: rect.maxY),
            control: CGPoint(x: rect.minX + tr, y: rect.maxY)
        )

        // 底边
        p.addLine(to: CGPoint(x: rect.maxX - tr - br, y: rect.maxY))

        // 底右圆角
        p.addQuadCurve(
            to: CGPoint(x: rect.maxX - tr, y: rect.maxY - br),
            control: CGPoint(x: rect.maxX - tr, y: rect.maxY)
        )

        // 右侧直边
        p.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY + tr))

        // 顶右凹角
        p.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - tr, y: rect.minY)
        )

        // 顶边回到起点
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        return p
    }
}

#Preview {
    VStack(spacing: 20) {
        NotchShape(topCornerRadius: 6, bottomCornerRadius: 14)
            .fill(.black).frame(width: 200, height: 32)
        NotchShape(topCornerRadius: 19, bottomCornerRadius: 24)
            .fill(.black).frame(width: 600, height: 200)
    }
    .padding(20)
    .background(.gray.opacity(0.3))
}
