import Foundation

/// 把每个图源的筛选条件存到本机。按「用途 + 图源」分别保存，
/// 发现页与搜索页互不影响，切换图源也不会串用别家的参数。
enum FilterPersistence {
    private static func key(scope: String, sourceID: String) -> String {
        "filters.\(scope).\(sourceID)"
    }

    static func load(scope: String, sourceID: String) -> FilterState? {
        guard let data = UserDefaults.standard.data(forKey: key(scope: scope, sourceID: sourceID)),
              let state = try? JSONDecoder().decode(FilterState.self, from: data)
        else { return nil }
        return state
    }

    static func save(_ state: FilterState, scope: String, sourceID: String) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: key(scope: scope, sourceID: sourceID))
    }

    static func clear(scope: String, sourceID: String) {
        UserDefaults.standard.removeObject(forKey: key(scope: scope, sourceID: sourceID))
    }

    /// 读取已保存的筛选，并用图源当前的声明补全缺失字段、剔除已不存在的字段。
    /// 这样图源以后增删筛选项，旧数据也不会出错。
    static func restored(scope: String, source: any WallpaperSource) -> FilterState {
        let defaults = source.defaultFilters
        guard let saved = load(scope: scope, sourceID: source.id) else { return defaults }
        var merged = defaults
        for (id, value) in saved.values where defaults.values[id] != nil {
            // 类型必须与声明一致，否则丢弃，避免旧数据把界面带崩。
            if sameKind(value, defaults.values[id]!) { merged.values[id] = value }
        }
        return merged
    }

    private static func sameKind(_ a: FilterValue, _ b: FilterValue) -> Bool {
        switch (a, b) {
        case (.text, .text), (.flag, .flag), (.choice, .choice), (.multi, .multi): true
        default: false
        }
    }
}
