import Foundation

struct JSONSourceConfig: Codable, Identifiable, Sendable {
    var id = UUID().uuidString
    var name = ""
    var endpoint = ""
    var randomImage: Bool? // 旧配置没有这个字段，仍使用 JSON 列表。
    var listPath = "" // 空字符串表示根数组；例如 data.items 表示嵌套数组。
    var imagePath = "url"
    var thumbPath = ""
    var widthPath = ""
    var heightPath = ""
    var searchParam = ""
    var pageParam = ""
    /// 用户自定义的筛选项；旧配置没有这个字段，视为没有筛选。
    var customFilters: [CustomFilter]?

    init() {}
}

private func httpsURL(_ text: String, relativeTo base: URL? = nil) -> URL? {
    let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty, let url = URL(string: text, relativeTo: base)?.absoluteURL,
          url.scheme?.lowercased() == "https", !(url.host ?? "").isEmpty,
          url.user == nil, url.password == nil else { return nil }
    return url
}

private final class HTTPSRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        let allowed = request.url.flatMap { httpsURL($0.absoluteString) } != nil
        completionHandler(allowed ? request : nil)
    }
}

struct JSONWallpaperSource: WallpaperSource {
    let config: JSONSourceConfig
    var id: String { config.id }
    var name: String { config.name.isEmpty ? "JSON 图源" : config.name }
    let summary = "公开 HTTPS JSON 图片列表"
    let symbol = "curlybraces"
    var homepage: URL { httpsURL(config.endpoint) ?? URL(string: "about:blank")! }
    var filterFields: [FilterField] { config.usableFilters.map(\.field) }
    private var searchKey: String { config.searchParam.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var pageKey: String { config.pageParam.trimmingCharacters(in: .whitespacesAndNewlines) }
    var capabilities: SourceCapabilities {
        var flags: SourceCapabilities = []
        if !searchKey.isEmpty { flags.insert(.search) }
        if !pageKey.isEmpty { flags.insert(.paging) }
        return flags
    }

    private static let session: URLSession = {
        let settings = URLSessionConfiguration.ephemeral
        settings.urlCredentialStorage = nil
        settings.httpCookieStorage = nil
        settings.httpShouldSetCookies = false
        return URLSession(configuration: settings, delegate: HTTPSRedirects(), delegateQueue: nil)
    }()

    func page(_ number: Int, query: Query, credential _: String?) async throws -> SourcePage {
        try Task.checkCancellation()
        if pageKey.isEmpty && number > 1 { return SourcePage(items: [], hasMore: false) }
        guard let endpoint = httpsURL(config.endpoint),
              var parts = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw SourceError.network("请输入不含账号密码的 HTTPS 接口地址。")
        }
        guard searchKey.isEmpty || searchKey != pageKey else {
            throw SourceError.network("关键词和页码不能使用相同的参数名。")
        }
        let extra = config.filterItems(for: query.filters, excluding: Set([searchKey, pageKey].filter { !$0.isEmpty }))
        let extraNames = Set(extra.map(\.name))
        // 用户选过的筛选参数覆盖地址里原有的同名参数。
        var params = (parts.queryItems ?? []).filter { $0.name != searchKey && $0.name != pageKey && !extraNames.contains($0.name) }
        params.append(contentsOf: extra)
        let keyword = query.keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        if !searchKey.isEmpty && !keyword.isEmpty { params.append(.init(name: searchKey, value: keyword)) }
        if !pageKey.isEmpty { params.append(.init(name: pageKey, value: String(max(1, number)))) }
        parts.queryItems = params.isEmpty ? nil : params
        // 表单式服务会把未转义的加号读成空格。
        parts.percentEncodedQuery = parts.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let url = parts.url else { throw SourceError.network("接口参数无效。") }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data: Data, response: URLResponse
        do {
            (data, response) = try await Self.session.data(for: request)
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { throw CancellationError() }
            throw SourceError.network("无法连接到 JSON 图源，请检查接口地址和网络。")
        }
        guard let http = response as? HTTPURLResponse else { throw SourceError.network("响应不是 HTTP 响应。") }
        switch http.statusCode {
        case 200..<300: break
        case 401, 403: throw SourceError.unauthorized
        case 429: throw SourceError.rateLimited
        default: throw SourceError.badResponse(http.statusCode)
        }
        guard let root = try? JSONSerialization.jsonObject(with: data),
              let rows = value(config.listPath, in: root) as? [Any] else {
            throw SourceError.network("列表路径未指向 JSON 数组，请检查接口和字段映射。")
        }
        let base = http.url ?? url
        var seen = Set<URL>(), items = [Wallpaper]()
        for row in rows {
            try Task.checkCancellation()
            guard let image = imageURL(config.imagePath, in: row, base: base), seen.insert(image).inserted else { continue }
            let thumb = imageURL(config.thumbPath, in: row, base: base) ?? image
            let w = dimension(config.widthPath, in: row), h = dimension(config.heightPath, in: row)
            items.append(Wallpaper(id: "\(id):\(image.absoluteString)", url: image, path: image,
                                   thumbLarge: thumb, thumbSmall: thumb, width: h > 0 ? w : 0, height: w > 0 ? h : 0,
                                   fileSize: 0, fileType: "", category: "", views: 0, favorites: 0,
                                   colors: [], source: nil, sourceID: id))
        }
        if !rows.isEmpty && items.isEmpty { throw SourceError.network("列表中没有有效的 HTTPS 图片，请检查原图路径。") }
        return SourcePage(items: items, hasMore: !pageKey.isEmpty && !items.isEmpty)
    }

    private func value(_ path: String, in object: Any) -> Any? {
        if path.isEmpty { return object }
        var current: Any = object
        for key in path.components(separatedBy: ".") {
            guard let next = (current as? [String: Any])?[key] else { return nil }
            current = next
        }
        return current
    }

    private func imageURL(_ path: String, in row: Any, base: URL) -> URL? {
        guard let text = value(path, in: row) as? String else { return nil }
        return httpsURL(text, relativeTo: base)
    }

    private func dimension(_ path: String, in row: Any) -> Int {
        let raw = value(path, in: row)
        let text = (raw as? String) ?? (raw as? NSNumber)?.stringValue
        return max(0, text.flatMap { Int($0) } ?? 0)
    }
}

/// 用户为自定义图源声明的一个筛选项，对应请求里的一个查询参数。
struct CustomFilter: Codable, Identifiable, Hashable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable { case choice, toggle, text }
    struct Choice: Codable, Identifiable, Hashable, Sendable {
        var id = UUID().uuidString
        var title = ""
        var value = ""
    }

    var id = UUID().uuidString
    var title = ""
    var param = ""
    var kind = Kind.choice
    var choices: [Choice] = []
    /// 开关打开时发送的值；关闭时不发送。
    var onValue = "true"

    var cleanParam: String { param.trimmingCharacters(in: .whitespacesAndNewlines) }
    var isUsable: Bool {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !cleanParam.isEmpty else { return false }
        return kind != .choice || choices.contains { !$0.title.isEmpty }
    }

    /// 转成界面通用的筛选声明。
    var field: FilterField {
        switch kind {
        case .choice:
            let options = choices.filter { !$0.title.isEmpty }.map { FilterField.Option(id: $0.id, title: $0.title) }
            return FilterField(id: id, title: title, kind: .choice(options),
                               defaultValue: .choice(options.first?.id ?? ""))
        case .toggle:
            return FilterField(id: id, title: title, kind: .toggle, defaultValue: .flag(false))
        case .text:
            return FilterField(id: id, title: title, kind: .text(prompt: title, keyboard: .plain),
                               defaultValue: .text(""))
        }
    }

    /// 当前取值对应要附加的查询参数；空值不发送。
    func queryItem(for state: FilterState) -> URLQueryItem? {
        switch kind {
        case .choice:
            guard let picked = state.choice(id), let choice = choices.first(where: { $0.id == picked }),
                  !choice.value.isEmpty else { return nil }
            return URLQueryItem(name: cleanParam, value: choice.value)
        case .toggle:
            guard state.flag(id) == true else { return nil }
            return URLQueryItem(name: cleanParam, value: onValue)
        case .text:
            let text = (state.text(id) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : URLQueryItem(name: cleanParam, value: text)
        }
    }
}

extension JSONSourceConfig {
    var usableFilters: [CustomFilter] { (customFilters ?? []).filter(\.isUsable) }

    /// 把筛选值附加到请求参数；与关键词、页码同名的参数以它们为准。
    func filterItems(for state: FilterState, excluding reserved: Set<String>) -> [URLQueryItem] {
        let filters = usableFilters
        let filled = state.filled(with: filters.map(\.field))
        return filters.compactMap { reserved.contains($0.cleanParam) ? nil : $0.queryItem(for: filled) }
    }
}
