import SwiftUI

/// 搜索页：作为 TabView 的搜索角色，由系统呈现为独立的玻璃搜索入口。
struct SearchView: View {
    @State private var store: FeedStore
    @State private var text = ""
    @Namespace private var namespace

    init(source: any WallpaperSource) {
        _store = State(initialValue: FeedStore(source: source))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if store.query.keyword.isEmpty {
                    suggestions
                } else if store.items.isEmpty && store.phase == .idle {
                    ContentUnavailableView.search(text: store.query.keyword)
                } else if store.items.isEmpty, case .failed(let message) = store.phase {
                    ContentUnavailableView("搜索失败", systemImage: "wifi.exclamationmark", description: Text(message))
                } else if store.items.isEmpty {
                    ProgressView().padding(.top, 80)
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
            .navigationTitle("搜索")
            .navigationDestination(for: Wallpaper.self) { wallpaper in
                WallpaperDetailView(wallpaper: wallpaper)
                    .navigationTransition(.zoom(sourceID: wallpaper.id, in: namespace))
            }
            .searchable(text: $text, prompt: "搜索壁纸，如 city、forest")
            .onSubmit(of: .search) { run(text) }
            .onChange(of: text) { _, newValue in
                // 清空搜索框时回到建议页
                if newValue.isEmpty, !store.query.keyword.isEmpty { run("") }
            }
        }
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("热门搜索")
                .font(.headline)
                .padding(.horizontal)
            ForEach(["nature", "city", "space", "minimal", "cyberpunk", "mountain", "ocean", "anime"], id: \.self) { word in
                Button {
                    text = word
                    run(word)
                } label: {
                    Label(word, systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal)
            }
        }
        .padding(.top)
    }

    private func run(_ keyword: String) {
        store.query.keyword = keyword
        Task { await store.reset() }
    }
}
