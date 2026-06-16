import SwiftUI
import Combine

/// PanelViewModel 承载剪贴板列表的状态：分类 + 搜索 + 选中 + 粘贴。
/// 视图层（NotchView 内嵌的 ClipboardListView）订阅它。
@MainActor
final class PanelViewModel: ObservableObject {

    @Published var items: [ClipboardItem] = []
    @Published var searchTerm: String = ""
    @Published var selectedIndex: Int = 0
    /// 当前分类。改变时会重置选中索引。
    @Published var category: ClipboardStore.Category = .all {
        didSet { selectedIndex = 0 }
    }

    /// 经分类 + 搜索过滤后的展示列表。
    var filteredItems: [ClipboardItem] {
        (try? store.query(category: category, search: searchTerm)) ?? []
    }

    private let store: ClipboardStore
    private let paster: PasteService
    private let preferences: PreferencesStore
    /// 关闭面板回调，返回打开面板时记录的粘贴目标，供粘贴时恢复焦点。
    private let onCommit: () -> PasteTarget?
    private var cancellables = Set<AnyCancellable>()

    init(
        store: ClipboardStore,
        paster: PasteService,
        preferences: PreferencesStore = .shared,
        onCommit: @escaping () -> PasteTarget?
    ) {
        self.store = store
        self.paster = paster
        self.preferences = preferences
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
        let count = filteredItems.count
        guard count > 0 else { return }
        selectedIndex = max(0, selectedIndex - 1)
    }

    func selectionDown() {
        let count = filteredItems.count
        guard count > 0 else { return }
        selectedIndex = min(count - 1, selectedIndex + 1)
    }

    /// Tab / Shift+Tab 在分类间循环。
    func nextCategory() {
        let all = ClipboardStore.Category.allCases
        guard let i = all.firstIndex(of: category) else { return }
        category = all[(i + 1) % all.count]
    }

    func previousCategory() {
        let all = ClipboardStore.Category.allCases
        guard let i = all.firstIndex(of: category) else { return }
        category = all[(i - 1 + all.count) % all.count]
    }

    func commitSelection() {
        guard let item = filteredItems[safe: selectedIndex] else { return }
        // 标记使用：常用分类排序依据
        try? store.markUsed(id: item.id)

        let shouldClose = preferences.closeAfterCopy || preferences.autoPasteEnabled
        if shouldClose {
            let target = onCommit()
            paster.paste(item, activating: target)
        } else {
            // 不关面板：仅写剪贴板，不注入 ⌘V（注入了焦点也不在用户的 app 上）
            paster.paste(item, activating: nil)
        }
    }

    /// 切换星标 = togglePin。pinned 项纳入"常用"分类。
    func toggleStar(_ item: ClipboardItem) {
        try? store.togglePin(id: item.id)
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
