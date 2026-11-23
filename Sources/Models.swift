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
    /// 所属图源 id，用于收藏跨图源展示。旧数据缺省为 wallhaven。
    var sourceID: String = "wallhaven"

    /// 宽高比（宽 / 高）。网格按真实比例显示整图。
    var aspectRatio: Double {
        height > 0 ? Double(width) / Double(height) : 0.5625
    }

    var resolution: String { "\(width) × \(height)" }

    init(id: String, url: URL, path: URL, thumbLarge: URL, thumbSmall: URL,
         width: Int, height: Int, fileSize: Int, fileType: String, category: String,
         views: Int, favorites: Int, colors: [String], source: String?, sourceID: String) {
        self.id = id; self.url = url; self.path = path
        self.thumbLarge = thumbLarge; self.thumbSmall = thumbSmall
        self.width = width; self.height = height
        self.fileSize = fileSize; self.fileType = fileType; self.category = category
        self.views = views; self.favorites = favorites; self.colors = colors
        self.source = source; self.sourceID = sourceID
    }

    // 兼容旧版收藏文件：没有 sourceID 字段时回退到 wallhaven。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        url = try c.decode(URL.self, forKey: .url)
        path = try c.decode(URL.self, forKey: .path)
        thumbLarge = try c.decode(URL.self, forKey: .thumbLarge)
        thumbSmall = try c.decode(URL.self, forKey: .thumbSmall)
        width = try c.decode(Int.self, forKey: .width)
        height = try c.decode(Int.self, forKey: .height)
        fileSize = try c.decode(Int.self, forKey: .fileSize)
        fileType = try c.decode(String.self, forKey: .fileType)
        category = try c.decode(String.self, forKey: .category)
        views = try c.decode(Int.self, forKey: .views)
        favorites = try c.decode(Int.self, forKey: .favorites)
        colors = try c.decode([String].self, forKey: .colors)
        source = try c.decodeIfPresent(String.self, forKey: .source)
        sourceID = try c.decodeIfPresent(String.self, forKey: .sourceID) ?? "wallhaven"
    }
}

// MARK: - Wallhaven 原始响应

extension Wallpaper {
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

        func model(sourceID: String) -> Wallpaper {
            Wallpaper(
                id: id, url: url, path: path,
                thumbLarge: thumbs.large, thumbSmall: thumbs.small,
                width: dimension_x, height: dimension_y,
                fileSize: file_size, fileType: file_type ?? "image/jpeg",
                category: category, views: views, favorites: favorites,
                colors: colors,
                source: (source?.isEmpty ?? true) ? nil : source,
                sourceID: sourceID
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
