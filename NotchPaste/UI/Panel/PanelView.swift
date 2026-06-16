import SwiftUI
import Combine

/// 展开面板的顶层视图。响应键盘 ↑↓ Enter Esc。
struct PanelView: View {

    @ObservedObject var viewModel: PanelViewModel

    var body: some View {
        VStack(spacing: 0) {
            searchBar
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 6)
            Divider().opacity(0.2)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(viewModel.filteredItems.enumerated()), id: \.element.id) { idx, item in
                            ItemRowView(item: item, isSelected: idx == viewModel.selectedIndex)
                                .id(item.id)
                                .onTapGesture {
                                    viewModel.selectedIndex = idx
                                    viewModel.commitSelection()
                                }
                        }
                    }
                    .padding(8)
                }
                .onChange(of: viewModel.selectedIndex) { _, new in
                    if let item = viewModel.filteredItems[safe: new] {
                        proxy.scrollTo(item.id, anchor: .center)
                    }
                }
            }
        }
        .frame(width: 360, height: 480)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.08))
        )
        .onAppear { viewModel.refresh() }
    }

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search", text: $viewModel.searchTerm)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.06)))
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

/// PanelView 的状态承载。把 store / paste 服务从 UI 解耦。
@MainActor
final class PanelViewModel: ObservableObject {

    @Published var items: [ClipboardItem] = []
    @Published var searchTerm: String = ""
    @Published var selectedIndex: Int = 0

    var filteredItems: [ClipboardItem] {
        let q = searchTerm.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return items }
        return items.filter {
            switch $0.type {
            case .text(let s): return s.lowercased().contains(q)
            }
        }
    }

    private let store: ClipboardStore
    private let paster: PasteService
    private let onCommit: () -> Void
    private var cancellables = Set<AnyCancellable>()

    init(store: ClipboardStore, paster: PasteService, onCommit: @escaping () -> Void) {
        self.store = store
        self.paster = paster
        self.onCommit = onCommit
        store.itemsPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] new in
                self?.items = new
                if (self?.selectedIndex ?? 0) >= new.count {
                    self?.selectedIndex = max(0, new.count - 1)
                }
            }
            .store(in: &cancellables)
    }

    func refresh() {
        items = (try? store.allItems()) ?? []
        selectedIndex = 0
    }

    func selectionUp() {
        guard !filteredItems.isEmpty else { return }
        selectedIndex = max(0, selectedIndex - 1)
    }

    func selectionDown() {
        guard !filteredItems.isEmpty else { return }
        selectedIndex = min(filteredItems.count - 1, selectedIndex + 1)
    }

    func commitSelection() {
        guard let item = filteredItems[safe: selectedIndex] else { return }
        paster.paste(item)
        onCommit()    // 关闭面板
    }
}
