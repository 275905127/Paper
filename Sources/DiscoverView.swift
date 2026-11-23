import SwiftUI

/// 发现页：当前图源的壁纸流，支持排序、分类、下拉刷新、无限滚动。
struct DiscoverView: View {
    @State private var store: FeedStore
    @State private var showFilter = false
    @Namespace private var namespace

    init(source: any WallpaperSource) {
        _store = State(initialValue: FeedStore(source: source))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if store.items.isEmpty {
                    emptyState
                } else {
                    WallpaperGrid(
                        items: store.items,
                        onReachEnd: { store.loadMoreIfNeeded(current: $0) },
                        namespace: namespace
                    )
                    FeedFooter(store: store)
                }
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .refreshable { await store.reset() }
            .navigationTitle("发现")
            .navigationDestination(for: Wallpaper.self) { wallpaper in
                WallpaperDetailView(wallpaper: wallpaper)
                    .navigationTransition(.zoom(sourceID: wallpaper.id, in: namespace))
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("筛选", systemImage: "line.3.horizontal.decrease") {
                        showFilter = true
                    }
                }
            }
            .sheet(isPresented: $showFilter) {
                FilterSheet(query: store.query) { newQuery in
                    store.query = newQuery
                    Task { await store.reset() }
                }
                .presentationDetents([.medium])
            }
            .task { store.loadIfNeeded() }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        switch store.phase {
        case .failed(let message):
            ContentUnavailableView {
                Label("加载失败", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("重试") { Task { await store.reset() } }
                    .buttonStyle(.glassProminent)
            }
            .containerRelativeFrame(.vertical) { height, _ in height * 0.7 }
        default:
            ProgressView()
                .containerRelativeFrame(.vertical) { height, _ in height * 0.7 }
        }
    }
}

/// 排序与分类筛选。
struct FilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query: Query
    let onApply: (Query) -> Void

    init(query: Query, onApply: @escaping (Query) -> Void) {
        _query = State(initialValue: query)
        self.onApply = onApply
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("排序") {
                    Picker("排序", selection: $query.sorting) {
                        ForEach(Sorting.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section("分类") {
                    Toggle("综合", isOn: $query.categories.general)
                    Toggle("动漫", isOn: $query.categories.anime)
                    Toggle("人物", isOn: $query.categories.people)
                }
            }
            .navigationTitle("筛选")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("应用") {
                        onApply(query)
                        dismiss()
                    }
                    .disabled(query.categories.isEmpty)
                }
            }
        }
    }
}
