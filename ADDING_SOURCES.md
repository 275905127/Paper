# 适配新图源

纸间的界面只依赖 `WallpaperSource` 协议。筛选菜单、密钥输入、图源切换都由协议数据驱动，
**新增图源不需要改任何界面代码**。

## 思路

不同网站的筛选差异很大（排序名不同、有的有颜色、有的只有标签），所以不在界面里写死菜单，
而是让图源**声明**自己支持什么，界面据此生成：

```
图源 ──声明──▶ [FilterField]            界面 FilterSheet 逐项渲染
图源 ◀─翻译─── Query + FilterState      图源把通用查询翻译成自己的请求
图源 ──声明──▶ CredentialSpec?          界面图源页据此显示密钥输入
```

三个关键点：

1. **声明而非硬编码**：每个筛选是一个 `FilterField`（单选 / 多选 / 开关 / 文本）。
2. **取值与图源无关**：用户的选择统一存成 `FilterState`（`[字段 id: 取值]`）。字段 id 由图源自己定义，
   所以每个图源只认自己的 id，互不干扰。
3. **切换图源即重置筛选**：`FeedStore.switchSource` 会换成新图源的默认值，避免把 A 的参数带给 B。

## 实现步骤

在 `Sources/` 新建 `XxxSource.swift`：

```swift
struct XxxSource: WallpaperSource {
    let id = "xxx"                      // 全局唯一，也是密钥在钥匙串里的账户名
    let name = "Xxx"
    let summary = "一句话介绍"
    let symbol = "photo"                // SF Symbols 名称
    let homepage = URL(string: "https://xxx.example")!

    // 1) 声明筛选（没有就返回 []）
    var filterFields: [FilterField] { [
        FilterField(
            id: "sort", title: "排序",
            kind: .choice([.init(id: "hot", title: "热门"), .init(id: "new", title: "最新")]),
            defaultValue: .choice("hot")
        ),
        // 条件显示：仅当 sort == hot 时出现
        FilterField(
            id: "range", title: "时间范围",
            kind: .choice([.init(id: "week", title: "一周"), .init(id: "month", title: "一月")]),
            defaultValue: .choice("week"),
            visibleWhen: .init(fieldID: "sort", equals: "hot")
        ),
    ] }

    // 2) 需要密钥才声明；不需要就不写这一项
    let credential: CredentialSpec? = CredentialSpec(
        label: "API Key", help: "……", applyURL: URL(string: "https://…"), optional: false)

    // 3) 把通用查询翻译成请求
    func page(_ number: Int, query: Query, credential: String?) async throws -> SourcePage {
        let f = query.filters.filled(with: filterFields)   // 补全缺省值
        // 用 f.choice("sort") / f.multi("…") / f.text("…") 取值，拼请求
        // 返回 SourcePage(items: [Wallpaper], hasMore: Bool)
    }

    // 4) 可选：校验密钥。默认视为有效
    func validate(credential: String) async throws -> Bool { … }
}
```

最后在 `SourceCatalog.all` 里追加 `XxxSource()`。

## 字段类型对照

| `FilterField.Kind` | 界面 | 取值读取 |
|---|---|---|
| `.choice([Option])` | 下拉菜单 | `state.choice(id)` |
| `.multi([Option], minimum:)` | 一组开关，至少选 N 项 | `state.multi(id)` |
| `.toggle` | 单个开关 | `state.flag(id)` |
| `.text(prompt:keyboard:)` | 文本框 | `state.text(id)` |

附加能力：

- `Option.requiresKey`：选项需要密钥，无密钥时在界面上标「需密钥」并禁用。
- `visibleWhen`：依赖另一个单选字段的取值才显示。
- `footer`：字段下方的说明文字。

## 把结果映射成 `Wallpaper`

必须字段：`id`、`url`（网页）、`path`（原图）、`thumbLarge`、`thumbSmall`、`width`、`height`。
网站没提供的可填保底值（`fileSize: 0`、`views: 0`、`colors: []`）。`width/height` 一定要真实，
列表按它算比例显示整图；拿不到时用 0，会按 9:16 兜底。`sourceID` 填自己的 `id`。

## 错误约定

抛出 `SourceError`，界面统一展示：

| 情况 | 抛出 |
|---|---|
| 401 / 密钥失效 | `.unauthorized` |
| 429 限流 | `.rateLimited` |
| 其他 HTTP 错误 | `.badResponse(code)` |
| 网络错误 | `.network(message)`；取消任务时直接抛 `CancellationError` |

## 注意

- 密钥放钥匙串（`CredentialStore`），**用请求头发送，不拼进 URL**。
- 先用 `curl` 实测接口再写代码：文档与实际行为可能不同。例如 Wallhaven 无密钥时请求 NSFW 返回空结果而不是 401，
  无效密钥访问 `/settings` 返回 404 而不是 401。
- 这个 App 不内置成人内容的开关默认值；默认只开 SFW，由用户自己打开。

## 目前未覆盖（需要时再扩展）

- 标签、颜色等**自由输入的多值**筛选（可新增 `FilterField.Kind`）。
- **非分页**图源（如“每日一图”）：`page` 返回 `hasMore: false` 即可。
- **自定义 JSON 图源**（用户填接口和字段映射）：可新增一个通用的 `ConfigurableSource`，
  把字段映射存成配置，复用同一套协议。
