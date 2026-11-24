import Foundation
import Observation

/// 一个可分页、可刷新的壁纸流。发现页和搜索页各持有一个实例。
@MainActor
@Observable
final class FeedStore {
    enum Phase: Equatable {
        case idle
        case loading
        case failed(String)
    }

    private(set) var items: [Wallpaper] = []
    private(set) var phase: Phase = .idle
    private(set) var hasMore = true

    var query: Query
    private(set) var source: any WallpaperSource
    private let credentials: CredentialStore
    private var nextPage = 1
    private var seen = Set<String>()
    private var task: Task<Void, Never>?
    /// 每次重置自增，用于丢弃过期请求的结果。
    private var generation = 0
    /// 筛选的保存范围，如 "discover" / "search"。
    private let scope: String

    init(source: any WallpaperSource, credentials: CredentialStore, scope: String) {
        self.source = source
        self.credentials = credentials
        self.scope = scope
        self.query = Query(filters: FilterPersistence.restored(scope: scope, source: source))
    }

    /// 应用并保存新的筛选条件。
    func applyFilters(_ filters: FilterState) {
        query.filters = filters
        FilterPersistence.save(filters, scope: scope, sourceID: source.id)
    }

    var isLoading: Bool { phase == .loading }

    /// 切换图源：筛选恢复该图源的默认值，并重新加载。
    func switchSource(_ newSource: any WallpaperSource) async {
        source = newSource
        // 切换图源：恢复该图源上次保存的筛选，没有就用默认值。
        query = Query(keyword: query.keyword,
                      filters: FilterPersistence.restored(scope: scope, source: newSource))
        await reset()
    }

    /// 首次进入时加载；已有内容则不重复请求。
    func loadIfNeeded() {
        guard items.isEmpty, phase == .idle else { return }
        loadMore()
    }

    /// 条件变化或下拉刷新：清空并重新开始。
    func reset() async {
        task?.cancel()
        generation += 1
        items = []
        seen = []
        nextPage = 1
        hasMore = true
        phase = .idle
        let work = startLoad()
        await work?.value
    }

    /// 滚动到底部时调用。
    func loadMore() {
        _ = startLoad()
    }

    /// 接近列表末尾时触发预加载。
    func loadMoreIfNeeded(current item: Wallpaper) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        if index >= items.count - 6 { loadMore() }
    }

    @discardableResult
    private func startLoad() -> Task<Void, Never>? {
        guard hasMore, phase != .loading else { return nil }

        if scope == "search", query.keyword.isEmpty || !source.capabilities.contains(.search) { return nil }
        if let spec = source.credential, !spec.optional,
           credentials.value(for: source.id) == nil {
            phase = .failed(SourceError.missingCredential.localizedDescription)
            return nil
        }

        phase = .loading
        let page = nextPage
        let query = query
        let token = generation
        let source = source
        let key = credentials.value(for: source.id)

        let work = Task {
            do {
                let result = try await source.page(page, query: query, credential: key)
                guard token == generation else { return }
                let fresh = result.items.filter { seen.insert($0.id).inserted }
                items.append(contentsOf: fresh)
                hasMore = result.hasMore && !fresh.isEmpty
                nextPage = page + 1
                phase = .idle
            } catch is CancellationError {
                if token == generation { phase = .idle }
            } catch {
                guard token == generation else { return }
                phase = .failed(error.localizedDescription)
            }
        }
        task = work
        return work
    }
}
