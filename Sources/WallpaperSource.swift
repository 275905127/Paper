import Foundation

/// 一页结果。
struct SourcePage: Sendable {
    let items: [Wallpaper]
    let hasMore: Bool
}

enum SourceError: LocalizedError {
    case badResponse(Int)
    case rateLimited
    case unauthorized
    case network(String)
    case missingCredential

    var errorDescription: String? {
        switch self {
        case .badResponse(let code): "服务器返回异常（\(code)）"
        case .rateLimited: "请求过于频繁（每分钟有上限），请稍后再试"
        case .unauthorized: "密钥无效，或当前内容需要有效密钥。请到“图源”页检查。"
        case .network(let message): message
        case .missingCredential: "该图源需要先填写密钥"
        }
    }
}

/// 图源抽象。界面只依赖它，不关心具体网站。
///
/// 适配新图源只需实现这个协议：
/// 1. 填 `id / name / summary / symbol`；
/// 2. 用 `filterFields` 声明支持的筛选，界面自动生成菜单；
/// 3. 在 `page(_:query:credential:)` 里把 `Query` 翻译成请求，并返回 `SourcePage`；
/// 4. 需要密钥时填 `credential`，不需要则返回 nil；
/// 5. 在 `SourceCatalog.all` 里追加一行。
protocol WallpaperSource: Sendable {
    var id: String { get }
    var name: String { get }
    var summary: String { get }
    var symbol: String { get }
    var homepage: URL { get }
    var capabilities: SourceCapabilities { get }
    var filterFields: [FilterField] { get }
    var credential: CredentialSpec? { get }

    func page(_ number: Int, query: Query, credential: String?) async throws -> SourcePage

    /// 校验密钥是否有效。默认视为有效。
    func validate(credential: String) async throws -> Bool
}

extension WallpaperSource {
    var capabilities: SourceCapabilities { [.search, .paging] }
    var credential: CredentialSpec? { nil }
    func validate(credential: String) async throws -> Bool { true }

    /// 默认筛选值。
    var defaultFilters: FilterState { .defaults(for: filterFields) }
}

// MARK: - Wallhaven

/// Wallhaven 公开接口。
///
/// - 不填密钥：可浏览 SFW 与 Sketchy，每分钟 45 次请求。
/// - 填密钥：解锁 NSFW，并沿用账号设置。密钥通过请求头 `X-API-Key` 发送，
///   不拼进 URL，避免进入日志或缓存键。
struct WallhavenSource: WallpaperSource {
    let id = "wallhaven"
    let name = "Wallhaven"
    let summary = "高质量壁纸社区"
    let symbol = "photo.stack"
    let homepage = URL(string: "https://wallhaven.cc")!

    let credential: CredentialSpec? = CredentialSpec(
        label: "API 密钥",
        help: "可选。填写后可浏览 NSFW 内容，并使用你账号的浏览设置。在 Wallhaven 网站“Account > API Key”里获取。",
        applyURL: URL(string: "https://wallhaven.cc/settings/account"),
        optional: true
    )

    private let session: URLSession
    init(session: URLSession = .shared) { self.session = session }

    // MARK: 筛选声明

    var filterFields: [FilterField] {
        let colors = Self.palette.map { FilterField.Option(id: $0.hex, title: $0.name) }
        return [
            FilterField(
                id: "sorting", title: "排序",
                kind: .choice([
                    .init(id: "toplist", title: "热门"),
                    .init(id: "date_added", title: "最新"),
                    .init(id: "relevance", title: "相关度"),
                    .init(id: "random", title: "随机"),
                    .init(id: "views", title: "最多浏览"),
                    .init(id: "favorites", title: "最多收藏"),
                ]),
                defaultValue: .choice("toplist"),
                quickAccess: true
            ),
            FilterField(
                id: "order", title: "顺序",
                kind: .choice([.init(id: "desc", title: "从高到低"), .init(id: "asc", title: "从低到高")]),
                defaultValue: .choice("desc")
            ),
            FilterField(
                id: "topRange", title: "热门时间范围",
                kind: .choice([
                    .init(id: "1d", title: "1 天"), .init(id: "3d", title: "3 天"),
                    .init(id: "1w", title: "1 周"), .init(id: "1M", title: "1 个月"),
                    .init(id: "3M", title: "3 个月"), .init(id: "6M", title: "6 个月"),
                    .init(id: "1y", title: "1 年"),
                ]),
                defaultValue: .choice("1M"),
                visibleWhen: .init(fieldID: "sorting", equals: "toplist")
            ),
            FilterField(
                id: "categories", title: "分类",
                kind: .multi([
                    .init(id: "general", title: "综合"),
                    .init(id: "anime", title: "动漫"),
                    .init(id: "people", title: "人物"),
                ], minimum: 1),
                defaultValue: .multi(["general", "anime", "people"])
            ),
            FilterField(
                id: "purity", title: "内容分级",
                kind: .multi([
                    .init(id: "sfw", title: "SFW"),
                    .init(id: "sketchy", title: "Sketchy"),
                    .init(id: "nsfw", title: "NSFW", requiresKey: true),
                ], minimum: 1),
                defaultValue: .multi(["sfw"]),
                footer: "NSFW 需要在图源页填写 API 密钥；Sketchy 无需密钥。"
            ),
            FilterField(
                id: "ratios", title: "画面比例",
                kind: .choice([
                    .init(id: "", title: "不限"),
                    .init(id: "portrait", title: "竖屏"),
                    .init(id: "landscape", title: "横屏"),
                    .init(id: "9x16", title: "9:16"),
                    .init(id: "9x19.5", title: "9:19.5"),
                    .init(id: "9x20", title: "9:20"),
                    .init(id: "10x16", title: "10:16"),
                    .init(id: "3x4", title: "3:4"),
                    .init(id: "1x1", title: "1:1"),
                    .init(id: "16x9", title: "16:9"),
                ]),
                defaultValue: .choice("portrait"),
                quickAccess: true
            ),
            FilterField(
                id: "atleast", title: "最小分辨率",
                kind: .text(prompt: "如 1080x1920", keyboard: .resolution),
                defaultValue: .text(""),
                footer: "格式：宽x高，例如 1080x1920。留空表示不限。"
            ),
            FilterField(
                id: "colors", title: "主色",
                kind: .choice([.init(id: "", title: "不限")] + colors),
                defaultValue: .choice("")
            ),
        ]
    }

    // MARK: 请求

    func page(_ number: Int, query: Query, credential: String?) async throws -> SourcePage {
        let f = query.filters.filled(with: filterFields)
        let hasKey = !(credential ?? "").isEmpty

        var items: [URLQueryItem] = []

        let sorting = f.choice("sorting") ?? "toplist"
        items.append(.init(name: "sorting", value: sorting))
        items.append(.init(name: "order", value: f.choice("order") ?? "desc"))
        if sorting == "toplist" {
            items.append(.init(name: "topRange", value: f.choice("topRange") ?? "1M"))
        }

        items.append(.init(name: "categories", value: mask(f.multi("categories") ?? [], order: ["general", "anime", "people"])))

        // 实测：无密钥时 Sketchy 可公开浏览，NSFW 只会返回空结果。
        // 所以只在没有密钥时去掉 NSFW；若因此一个都不剩，回退到 SFW。
        var purity = f.multi("purity") ?? ["sfw"]
        if !hasKey { purity.remove("nsfw") }
        if purity.isEmpty { purity = ["sfw"] }
        items.append(.init(name: "purity", value: mask(purity, order: ["sfw", "sketchy", "nsfw"])))

        if let ratio = f.choice("ratios"), !ratio.isEmpty {
            items.append(.init(name: "ratios", value: ratio))
        }
        if let atleast = f.text("atleast")?.trimmingCharacters(in: .whitespaces), isResolution(atleast) {
            items.append(.init(name: "atleast", value: atleast))
        }
        if let color = f.choice("colors"), !color.isEmpty {
            items.append(.init(name: "colors", value: color))
        }
        let keyword = query.keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        if !keyword.isEmpty {
            items.append(.init(name: "q", value: keyword))
        }
        items.append(.init(name: "page", value: String(number)))

        var components = URLComponents(string: "https://wallhaven.cc/api/v1/search")!
        components.queryItems = items

        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 20
        request.setValue("Paper-iOS/0.2", forHTTPHeaderField: "User-Agent")
        if hasKey, let credential { request.setValue(credential, forHTTPHeaderField: "X-API-Key") }

        let (data, response) = try await send(request)
        try check(response)

        let decoded = try JSONDecoder().decode(Wallpaper.Page.self, from: data)
        return SourcePage(
            items: decoded.data.map { $0.model(sourceID: id) },
            hasMore: decoded.meta.current_page < decoded.meta.last_page
        )
    }

    func validate(credential: String) async throws -> Bool {
        var request = URLRequest(url: URL(string: "https://wallhaven.cc/api/v1/settings")!)
        request.timeoutInterval = 15
        request.setValue(credential, forHTTPHeaderField: "X-API-Key")
        request.setValue("Paper-iOS/0.2", forHTTPHeaderField: "User-Agent")
        let (_, response) = try await send(request)
        guard let http = response as? HTTPURLResponse else { return false }
        switch http.statusCode {
        case 200..<300: return true
        // 实测：无密钥返回 401，无效密钥返回 404，都表示密钥不可用。
        case 401, 404: return false
        case 429: throw SourceError.rateLimited
        default: throw SourceError.badResponse(http.statusCode)
        }
    }

    // MARK: 辅助

    private func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw SourceError.network(error.localizedDescription)
        }
    }

    private func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        switch http.statusCode {
        case 200..<300: return
        case 401: throw SourceError.unauthorized
        case 429: throw SourceError.rateLimited
        default: throw SourceError.badResponse(http.statusCode)
        }
    }

    /// 把选中集合转成 Wallhaven 的 0/1 掩码，如 ["sfw","nsfw"] → "101"。
    private func mask(_ selected: Set<String>, order: [String]) -> String {
        order.map { selected.contains($0) ? "1" : "0" }.joined()
    }

    private func isResolution(_ text: String) -> Bool {
        text.range(of: #"^\d{3,5}x\d{3,5}$"#, options: .regularExpression) != nil
    }

    static let palette: [(hex: String, name: String)] = [
        ("660000", "深红"), ("990000", "暗红"), ("cc0000", "红"), ("cc3333", "浅红"),
        ("ea4c88", "粉"), ("993399", "紫"), ("663399", "深紫"), ("333399", "靛蓝"),
        ("0066cc", "蓝"), ("0099cc", "天蓝"), ("66cccc", "青"), ("77cc33", "草绿"),
        ("669900", "绿"), ("336600", "深绿"), ("666600", "橄榄"), ("999900", "黄绿"),
        ("cccc33", "柠檬"), ("ffff00", "黄"), ("ffcc33", "金"), ("ff9900", "橙"),
        ("ff6600", "深橙"), ("cc6633", "赭"), ("996633", "棕"), ("663300", "深棕"),
        ("000000", "黑"), ("999999", "灰"), ("cccccc", "浅灰"), ("ffffff", "白"),
        ("424153", "石板"),
    ]
}

// MARK: - 图源清单

/// 内置图源清单。以后新增图源只需在这里追加。
enum SourceCatalog {
    static let all: [any WallpaperSource] = [WallhavenSource()]
    static var `default`: any WallpaperSource { all[0] }

    static func source(id: String) -> (any WallpaperSource)? {
        all.first { $0.id == id }
    }
}
