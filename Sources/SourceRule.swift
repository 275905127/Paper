import Foundation

/// 粘贴即用的图源规则。一段 JSON 描述一个完整图源：名称、类型、地址、
/// 字段映射、搜索、分页和筛选项；也可以写成数组一次导入多个。
/// 不依赖网络探测，不内置任何站点。
///
/// 通用字段
///   name      图源名称（必填）
///   url       HTTPS 接口地址（必填，不含账号密码）
///   type      "list" JSON 列表（默认）｜ "random" 随机直链
///   filters   筛选项数组，见下
///
/// list 类型专用
///   listPath  列表所在路径，顶层就是数组则不写，嵌套用点号，如 "data.items"
///   image     每条记录里原图地址的路径（默认 "url"）
///   thumb     缩略图路径
///   width / height   宽、高路径
///   search    关键词参数名（不写则不支持搜索）
///   page      页码参数名（不写则不支持翻页）
///
/// 筛选项（三种写法选一种）
///   {"title":"方向","param":"orient","options":[["竖屏","portrait"],["横屏","landscape"]]}
///   {"title":"成人内容","param":"adult","toggle":"1"}
///   {"title":"关键词","param":"q","text":true}
///   options 里值留空表示“选它时不发送该参数”，第一项为默认。
enum SourceRule {
    struct Failure: LocalizedError {
        let errorDescription: String?
        init(_ text: String) { errorDescription = text }
    }

    /// 文本是否看起来像规则（以花括号开头）。
    static func looksLikeRule(_ text: String) -> Bool {
        let head = text.trimmingCharacters(in: .whitespacesAndNewlines).first
        return head == "{" || head == "["
    }

    /// 解析一个对象或对象数组。
    static func parseAll(_ text: String) throws -> [JSONSourceConfig] {
        let cleaned = normalized(text)
        guard let data = cleaned.data(using: .utf8), let root = try? JSONSerialization.jsonObject(with: data) else {
            throw Failure("规则不是有效的 JSON，请检查括号、逗号和引号。")
        }
        let objects: [[String: Any]]
        if let one = root as? [String: Any] { objects = [one] }
        else if let many = root as? [[String: Any]], !many.isEmpty { objects = many }
        else { throw Failure("规则必须是一个对象，或由对象组成的数组。") }
        return try objects.enumerated().map { index, object in
            do { return try build(object) }
            catch let failure as Failure where objects.count > 1 { throw Failure("第 \(index + 1) 个图源：\(failure.localizedDescription)") }
        }
    }

    static func parse(_ text: String) throws -> JSONSourceConfig {
        guard let first = try parseAll(text).first else { throw Failure("规则为空。") }
        return first
    }

    /// 粘贴常带智能引号和不可见空格，先还原。
    private static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{201C}", with: "\"").replacingOccurrences(of: "\u{201D}", with: "\"")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    private static func build(_ root: [String: Any]) throws -> JSONSourceConfig {
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
            filter.id = "rule.\(param)"
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
                    // 稳定 ID：重新导入同一规则后，已保存的筛选选择仍然有效。
                    choice.id = "rule.\(param).\(filter.choices.count)"
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

    /// 把已有图源导出成可再次粘贴的规则文本。
    static func export(_ configs: [JSONSourceConfig]) -> String {
        let objects: [[String: Any]] = configs.map { c in
            var o: [String: Any] = ["name": c.name, "url": c.endpoint]
            if c.randomImage == true { o["type"] = "random" }
            else {
                if !c.listPath.isEmpty { o["listPath"] = c.listPath }
                o["image"] = c.imagePath
                for (key, value) in [("thumb", c.thumbPath), ("width", c.widthPath), ("height", c.heightPath),
                                     ("search", c.searchParam), ("page", c.pageParam)] where !value.isEmpty { o[key] = value }
            }
            let filters: [[String: Any]] = c.usableFilters.map { f in
                var item: [String: Any] = ["title": f.title, "param": f.cleanParam]
                switch f.kind {
                case .choice: item["options"] = f.choices.filter { !$0.title.isEmpty }.map { [$0.title, $0.value] }
                case .toggle: item["toggle"] = f.onValue
                case .text: item["text"] = true
                }
                return item
            }
            if !filters.isEmpty { o["filters"] = filters }
            return o
        }
        let root: Any = objects.count == 1 ? objects[0] : objects
        guard let data = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
              let text = String(data: data, encoding: .utf8) else { return "" }
        return text
    }
}
