import SwiftUI

/// 发现页：当前图源的壁纸流，支持图源切换、全功能筛选、下拉刷新、无限滚动。
struct DiscoverView: View {
    @Environment(CredentialStore.self) private var credentials
    @Environment(AppSettings.self) private var settings
    @State private var store: FeedStore
    @State private var showFilter = false
    @Namespace private var namespace

    init(credentials: CredentialStore, source: any WallpaperSource) {
        _store = State(initialValue: FeedStore(source: source, credentials: credentials, scope: "discover"))
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
            .navigationTitle(store.source.name)
            .navigationDestination(for: Wallpaper.self) { wallpaper in
                WallpaperDetailView(wallpaper: wallpaper)
                    .navigationTransition(.zoom(sourceID: wallpaper.id, in: namespace))
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    sourceMenu
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("筛选", systemImage: "line.3.horizontal.decrease") {
                        showFilter = true
                    }
                }
            }
            .sheet(isPresented: $showFilter) {
                FilterSheet(
                    source: store.source,
                    current: store.query.filters,
                    hasCredential: credentials.isSet(store.source.id)
                ) { newFilters in
                    store.applyFilters(newFilters)
                    Task { await store.reset() }
                }
                .presentationDetents([.large])
            }
            .task { store.loadIfNeeded() }
            // 密钥变化后（例如刚填写 / 删除），按新权限重新加载
            .onChange(of: credentials.revision) {
                Task { await store.reset() }
            }
            .onChange(of: settings.selectedSourceID) {
                if let source = SourceCatalog.source(id: settings.selectedSourceID) {
                    Task { await store.switchSource(source) }
                }
            }
        }
    }

    /// 图源切换菜单。只有一个图源时也保留，让结构一致。
    private var sourceMenu: some View {
        @Bindable var settings = settings
        return Menu {
            Picker("图源", selection: $settings.selectedSourceID) {
                ForEach(SourceCatalog.all, id: \.id) { source in
                    Label(source.name, systemImage: source.symbol).tag(source.id)
                }
            }
        } label: {
            Label("图源", systemImage: "square.stack.3d.up")
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
        case .idle where store.items.isEmpty && !store.hasMore:
            ContentUnavailableView(
                "没有符合条件的壁纸",
                systemImage: "photo.on.rectangle.angled",
                description: Text("试试放宽筛选条件。")
            )
            .containerRelativeFrame(.vertical) { height, _ in height * 0.7 }
        default:
            ProgressView()
                .containerRelativeFrame(.vertical) { height, _ in height * 0.7 }
        }
    }
}
