import SwiftUI
import Combine

/// 剪贴板列表视图：左侧分类 + 右侧搜索框 + 行列表。供 NotchView 在打开态嵌入。
struct ClipboardListView: View {

    @ObservedObject var viewModel: PanelViewModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            sidebar
                .frame(width: 92)

            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 1)

            VStack(spacing: 0) {
                searchBar
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
                    .padding(.bottom, 6)

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(viewModel.filteredItems.enumerated()), id: \.element.id) { idx, item in
                                ItemRowView(
                                    item: item,
                                    isSelected: idx == viewModel.selectedIndex,
                                    onToggleStar: { viewModel.toggleStar(item) }
                                )
                                .id(item.id)
                                .onTapGesture {
                                    viewModel.selectedIndex = idx
                                    viewModel.commitSelection()
                                }
                            }
                            if viewModel.filteredItems.isEmpty {
                                emptyState
                            }
                        }
                        .padding(.horizontal, 4)
                        .padding(.bottom, 6)
                    }
                    .onChange(of: viewModel.selectedIndex) { _, new in
                        if let item = viewModel.filteredItems[safe: new] {
                            proxy.scrollTo(item.id, anchor: .center)
                        }
                    }
                }
            }
        }
        .onAppear {
            viewModel.refresh()
            // 由快捷键打开 → 自动聚焦搜索框
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                searchFocused = true
            }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(ClipboardStore.Category.allCases, id: \.self) { c in
                CategoryRow(
                    category: c,
                    isSelected: viewModel.category == c
                ) {
                    viewModel.category = c
                }
            }
            Spacer()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.45))
            TextField("搜索", text: $viewModel.searchTerm)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.white)
                .focused($searchFocused)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.white.opacity(0.08))
        )
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 26))
                .foregroundStyle(.white.opacity(0.18))
            Text(viewModel.searchTerm.isEmpty ? emptyHint : "未找到匹配项")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 50)
    }

    private var emptyHint: String {
        switch viewModel.category {
        case .all: return "暂无剪贴板内容"
        case .favorite: return "暂无常用项"
        case .text: return "暂无文本"
        case .image: return "暂无图片"
        case .url: return "暂无链接"
        case .file: return "暂无文件"
        }
    }
}

// MARK: - Category row

private struct CategoryRow: View {
    let category: ClipboardStore.Category
    let isSelected: Bool
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: category.iconName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(textColor)
                    .frame(width: 14)
                Text(category.localizedTitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(textColor)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(background)
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
    }

    private var textColor: Color {
        if isSelected { return .white }
        return .white.opacity(hovered ? 0.9 : 0.55)
    }

    private var background: Color {
        if isSelected { return Color.white.opacity(0.14) }
        if hovered { return Color.white.opacity(0.06) }
        return .clear
    }
}

private extension ClipboardStore.Category {
    var localizedTitle: String {
        switch self {
        case .all: return "最近"
        case .favorite: return "常用"
        case .text: return "文本"
        case .image: return "图片"
        case .url: return "链接"
        case .file: return "文件"
        }
    }
    var iconName: String {
        switch self {
        case .all: return "clock"
        case .favorite: return "star"
        case .text: return "doc.plaintext"
        case .image: return "photo"
        case .url: return "link"
        case .file: return "doc"
        }
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
