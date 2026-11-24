import SwiftUI

/// 搜索页：作为 TabView 的搜索角色，由系统呈现为独立的玻璃搜索入口。
/// 沿用当前图源；筛选条件与发现页各自独立，搜索时可单独调整。
struct SearchView: View {
    @Environment(CredentialStore.self) private var credentials
    @Environment(AppSettings.self) private var settings
    @State private var store: FeedStore
    @AppStorage("paper.recentSearchTerms") private var historyData = Data()
    @State private var confirmClear = false
    private var history: [String] { (try? JSONDecoder().decode([String].self, from: historyData)) ?? [] }
    private func saveHistory(_ terms: [String]) {
        if let data = try? JSONEncoder().encode(Array(terms.prefix(12))) { historyData = data }
    }
    @State private var text = ""
    @State private var showFilter = false

    init(credentials: CredentialStore, source: any WallpaperSource) {
        _store = State(initialValue: FeedStore(source: source, credentials: credentials, scope: "search"))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if store.query.keyword.isEmpty {
                    suggestions
                } else if store.items.isEmpty, case .failed(let message) = store.phase {
                    ContentUnavailableView("搜索失败", systemImage: "wifi.exclamationmark", description: Text(message))
                } else if store.items.isEmpty && store.phase == .idle {
                    ContentUnavailableView.search(text: store.query.keyword)
                } else if store.items.isEmpty {
                    ProgressView().padding(.top, 80)
                } else {
                    WallpaperGrid(
                        items: store.items,
                        onReachEnd: { store.loadMoreIfNeeded(current: $0) }
                    )
                    FeedFooter(store: store)
                }
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .navigationTitle("搜索")
            .toolbar {
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
                    if !store.query.keyword.isEmpty { Task { await store.reset() } }
                }
                .presentationDetents([.large])
            }
            .searchable(text: $text, prompt: "搜索壁纸，如 city、forest")
            .onSubmit(of: .search) { run(text) }
            .onChange(of: text) { _, newValue in
                if newValue.isEmpty, !store.query.keyword.isEmpty { run("") }
            }
            .onChange(of: settings.selectedSourceID) {
                if let source = SourceCatalog.source(id: settings.selectedSourceID) {
                    Task { await store.switchSource(source) }
                }
            }
            .onChange(of: credentials.revision) {
                if !store.query.keyword.isEmpty { Task { await store.reset() } }
            }
        }
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !history.isEmpty {
                HStack {
                    Text("最近搜索").font(.headline)
                    Spacer()
                    Button("清空") { confirmClear = true }
                        .confirmationDialog("清空最近搜索？", isPresented: $confirmClear, titleVisibility: .visible) {
                            Button("清空", role: .destructive) { saveHistory([]) }
                        }
                }.padding(.horizontal)
                ForEach(history, id: \.self) { term in
                    Button { text = term; run(term) } label: {
                        Label(term, systemImage: "clock").frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contextMenu {
                        Button("移除此记录", systemImage: "trash", role: .destructive) { saveHistory(history.filter { $0 != term }) }
                    }.padding(.horizontal)
                }
            }
            Text("推荐搜索")
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
        let term = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        store.query.keyword = term
        guard !term.isEmpty else { return }
        saveHistory([term] + history.filter { $0.caseInsensitiveCompare(term) != .orderedSame })
        Task { await store.reset() }
    }
}
