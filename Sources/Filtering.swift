import Foundation

// MARK: - 筛选值

/// 一个筛选项当前的取值。与具体图源无关。
enum FilterValue: Hashable, Codable, Sendable {
    case text(String)
    case flag(Bool)
    case choice(String)
    case multi(Set<String>)

    var text: String? { if case .text(let v) = self { v } else { nil } }
    var flag: Bool? { if case .flag(let v) = self { v } else { nil } }
    var choice: String? { if case .choice(let v) = self { v } else { nil } }
    var multi: Set<String>? { if case .multi(let v) = self { v } else { nil } }
}

// MARK: - 筛选声明

/// 图源声明“我支持哪些筛选”，界面据此动态生成，无需为每个图源写菜单。
struct FilterField: Identifiable, Hashable, Sendable {
    struct Option: Identifiable, Hashable, Sendable {
        let id: String
        let title: String
        /// 该选项是否需要密钥才能使用。
        var requiresKey = false
    }

    enum Kind: Hashable, Sendable {
        case choice([Option])                       // 单选
        case multi([Option], minimum: Int)          // 多选，至少选几个
        case toggle                                 // 开关
        case text(prompt: String, keyboard: Keyboard)
    }

    enum Keyboard: Hashable, Sendable { case plain, resolution }

    let id: String
    let title: String
    let kind: Kind
    let defaultValue: FilterValue
    /// 仅当另一个字段取某值时才显示，例如“时间范围”只在排序为“热门”时出现。
    var visibleWhen: Condition?
    var footer: String?

    struct Condition: Hashable, Sendable {
        let fieldID: String
        let equals: String
    }
}

/// 一组筛选取值。键是 `FilterField.id`。
struct FilterState: Hashable, Codable, Sendable {
    var values: [String: FilterValue] = [:]

    func choice(_ id: String) -> String? { values[id]?.choice }
    func multi(_ id: String) -> Set<String>? { values[id]?.multi }
    func text(_ id: String) -> String? { values[id]?.text }
    func flag(_ id: String) -> Bool? { values[id]?.flag }

    /// 用图源声明补全缺省值。
    func filled(with fields: [FilterField]) -> FilterState {
        var copy = self
        for field in fields where copy.values[field.id] == nil {
            copy.values[field.id] = field.defaultValue
        }
        return copy
    }

    static func defaults(for fields: [FilterField]) -> FilterState {
        FilterState().filled(with: fields)
    }
}

// MARK: - 查询

/// 一次查询的完整条件。条件变化即视为新的列表。
struct Query: Hashable, Sendable {
    var keyword = ""
    var filters = FilterState()
}

// MARK: - 图源能力与密钥声明

struct SourceCapabilities: OptionSet, Sendable {
    let rawValue: Int
    static let search = SourceCapabilities(rawValue: 1 << 0)
    static let paging = SourceCapabilities(rawValue: 1 << 1)
}

/// 图源对密钥的要求。界面据此决定是否显示输入框、如何提示。
struct CredentialSpec: Hashable, Sendable {
    let label: String
    let help: String
    let applyURL: URL?
    /// 没有密钥时是否仍可用。false 表示必须填写才能浏览。
    let optional: Bool
}
