import Foundation

/// 一页结果。
struct SourcePage: Sendable {
    let items: [Wallpaper]
    let hasMore: Bool
}

enum SourceError: LocalizedError {
    case badResponse(Int)
    case rateLimited
    case network(String)

    var errorDescription: String? {
        switch self {
        case .badResponse(let code): "服务器返回异常（\(code)）"
        case .rateLimited: "请求过于频繁，请稍后再试"
        case .network(let message): message
        }
    }
}

/// 图源抽象。界面只依赖它，不关心具体网站。
protocol WallpaperSource: Sendable {
    var id: String { get }
    var name: String { get }
    var summary: String { get }
    var symbol: String { get }
    func page(_ number: Int, query: Query) async throws -> SourcePage
}

/// Wallhaven 公开接口，仅 SFW，无需 Key。
struct WallhavenSource: WallpaperSource {
    let id = "wallhaven"
    let name = "Wallhaven"
    let summary = "高质量壁纸社区，仅显示 SFW 内容"
    let symbol = "photo.stack"

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func page(_ number: Int, query: Query) async throws -> SourcePage {
        var components = URLComponents(string: "https://wallhaven.cc/api/v1/search")!
        var items = [
            URLQueryItem(name: "categories", value: query.categories.mask),
            URLQueryItem(name: "purity", value: "100"),
            URLQueryItem(name: "sorting", value: query.sorting.rawValue),
            URLQueryItem(name: "page", value: String(number)),
            // 手机竖屏壁纸优先
            URLQueryItem(name: "ratios", value: "portrait"),
        ]
        if query.sorting == .toplist {
            items.append(URLQueryItem(name: "topRange", value: "1M"))
        }
        let keyword = query.keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        if !keyword.isEmpty {
            items.append(URLQueryItem(name: "q", value: keyword))
        }
        components.queryItems = items

        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 20
        request.setValue("Paper-iOS/0.1", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw SourceError.network(error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse {
            if http.statusCode == 429 { throw SourceError.rateLimited }
            guard (200..<300).contains(http.statusCode) else {
                throw SourceError.badResponse(http.statusCode)
            }
        }

        let decoded = try JSONDecoder().decode(Wallpaper.Page.self, from: data)
        return SourcePage(
            items: decoded.data.map(\.model),
            hasMore: decoded.meta.current_page < decoded.meta.last_page
        )
    }
}

/// 内置图源清单。以后新增图源只需在这里追加。
enum SourceCatalog {
    static let all: [any WallpaperSource] = [WallhavenSource()]
    static var `default`: any WallpaperSource { all[0] }
}
