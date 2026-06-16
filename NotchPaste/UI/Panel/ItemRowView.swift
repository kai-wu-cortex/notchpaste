import SwiftUI

struct ItemRowView: View {

    let item: ClipboardItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            iconView
                .frame(width: 16, alignment: .center)
                .foregroundStyle(.cyan)
            Text(item.preview)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(relativeTime(for: item.createdAt))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.white.opacity(0.12) : .clear)
        )
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var iconView: some View {
        switch item.type {
        case .text:
            Image(systemName: "doc.plaintext")
        }
    }

    private func relativeTime(for date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }
}
