import Foundation

/// 粘贴即用的图源规则。一段 JSON 就能描述一个图源及其筛选项，
/// 不依赖网络探测，也不内置任何站点。
///
///     {
///       "name": "示例",
///       "type": "random",              // random 随机直链；list JSON 列表（默认）
///       "url": "https://example.com/api",
///       "filters": [
///         {"title": "方向", "param": "orient", "options": [["竖屏", "portrait"], ["横屏", "landscape"]]},
///         {"title": "成人内容", "param": "adult", "toggle": "1"},
///         {"title": "关键词", "param": "q", "text": true}
///       ]
///     }
///
/// list 类型另可写 listPath、image、thumb、width、height、search、page。
enum SourceRule {
    struct Failure: LocalizedError {
        let errorDescription: String?
        init(_ text: String) { errorDescription = text }
    }

    /// 文本是否看起来像规则（以花括号开头）。
    static func looksLikeRule(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{")
    }

    static func parse(_ text: String) throws -> JSONSourceConfig {
        // 粘贴时常带智能引号，先还原成直引号。
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{201C}", with: "\"").replacingOccurrences(of: "\u{201D}", with: "\"")
        guard let data = cleaned.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure("规则不是有效的 JSON 对象，请检查括号、逗号和引号。")
        }

        func string(_ key: String) -> String {
            (root[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }

        var config = JSONSourceConfig()
        config.name = string("name")
        config.endpoint = string("url")
        guard !config.name.isEmpty else { throw Failure("规则缺少 name（图源名称）。") }
        guard let url = URL(string: config.endpoint), url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else {
            throw Failure("规则的 url 必须是不含账号密码的 HTTPS 地址。")
        }

        switch string("type").lowercased() {
        case "random": config.randomImage = true
        case "", "list": break
        default: throw Failure("type 只能是 random 或 list。")
        }

        if config.randomImage != true {
            if !string("image").isEmpty { config.imagePath = string("image") }
            config.listPath = string("listPath")
            config.thumbPath = string("thumb")
            config.widthPath = string("width")
            config.heightPath = string("height")
            config.searchParam = string("search")
            config.pageParam = string("page")
        }

        let rawFilters = root["filters"] as? [[String: Any]] ?? []
        var seen = Set<String>()
        var filters: [CustomFilter] = []
        for (index, raw) in rawFilters.enumerated() {
            let label = "第 \(index + 1) 个筛选项"
            let title = (raw["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let param = (raw["param"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !title.isEmpty else { throw Failure("\(label)缺少 title。") }
            guard !param.isEmpty else { throw Failure("\(label)缺少 param（参数名）。") }
            guard seen.insert(param).inserted else { throw Failure("参数名 \(param) 重复。") }

            var filter = CustomFilter()
            filter.title = title
            filter.param = param
            if let options = raw["options"] as? [Any] {
                filter.kind = .choice
                for option in options {
                    guard let pair = option as? [Any], pair.count == 2,
                          let name = pair[0] as? String, let value = pair[1] as? String,
                          !name.trimmingCharacters(in: .whitespaces).isEmpty else {
                        throw Failure("\(label)的选项必须写成 [\"显示名\",\"参数值\"]。")
                    }
                    var choice = CustomFilter.Choice()
                    choice.title = name
                    choice.value = value
                    filter.choices.append(choice)
                }
                guard !filter.choices.isEmpty else { throw Failure("\(label)的 options 不能为空。") }
            } else if let on = raw["toggle"] as? String {
                filter.kind = .toggle
                filter.onValue = on
            } else if raw["text"] as? Bool == true {
                filter.kind = .text
            } else {
                throw Failure("\(label)需要 options、toggle 或 text 之一。")
            }
            filters.append(filter)
        }
        config.customFilters = filters.isEmpty ? nil : filters
        return config
    }
}
