import Foundation

/// 一张壁纸。同时用于网络解码和本地收藏持久化。
struct Wallpaper: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let url: URL            // 网页地址
    let path: URL           // 原图
    let thumbLarge: URL     // 列表缩略图
    let thumbSmall: URL
    let width: Int
    let height: Int
    let fileSize: Int
    let fileType: String
    let category: String
    let views: Int
    let favorites: Int
    let colors: [String]
    let source: String?

    /// 宽高比（宽 / 高），用于占位，避免图片加载时网格跳动。
    var aspectRatio: Double {
        height > 0 ? Double(width) / Double(height) : 0.5625
    }

    var resolution: String { "\(width) × \(height)" }
}

extension Wallpaper {
    /// Wallhaven 接口的原始字段 → 本地模型。
    struct Remote: Decodable, Sendable {
        struct Thumbs: Decodable, Sendable {
            let large: URL
            let small: URL
        }
        let id: String
        let url: URL
        let path: URL
        let thumbs: Thumbs
        let dimension_x: Int
        let dimension_y: Int
        let file_size: Int
        let file_type: String?
        let category: String
        let views: Int
        let favorites: Int
        let colors: [String]
        let source: String?

        var model: Wallpaper {
            Wallpaper(
                id: id, url: url, path: path,
                thumbLarge: thumbs.large, thumbSmall: thumbs.small,
                width: dimension_x, height: dimension_y,
                fileSize: file_size, fileType: file_type ?? "image/jpeg",
                category: category, views: views, favorites: favorites,
                colors: colors,
                source: (source?.isEmpty ?? true) ? nil : source
            )
        }
    }

    struct Page: Decodable, Sendable {
        struct Meta: Decodable, Sendable {
            let current_page: Int
            let last_page: Int
        }
        let data: [Remote]
        let meta: Meta
    }
}

/// 浏览排序，对应 Wallhaven 的 sorting 参数。
enum Sorting: String, CaseIterable, Identifiable, Sendable {
    case toplist, latest, random, views, favorites
    var id: String { rawValue }

    var title: String {
        switch self {
        case .toplist: "热门"
        case .latest: "最新"
        case .random: "随机"
        case .views: "最多浏览"
        case .favorites: "最多收藏"
        }
    }
}

/// 分类开关，对应 Wallhaven 的 categories 三位掩码（general / anime / people）。
struct CategoryFilter: Hashable, Sendable {
    var general = true
    var anime = true
    var people = true

    var mask: String { "\(general ? 1 : 0)\(anime ? 1 : 0)\(people ? 1 : 0)" }
    var isEmpty: Bool { !general && !anime && !people }
}

/// 一次查询的完整条件。条件变化即视为新的列表。
struct Query: Hashable, Sendable {
    var keyword = ""
    var sorting: Sorting = .toplist
    var categories = CategoryFilter()
}
