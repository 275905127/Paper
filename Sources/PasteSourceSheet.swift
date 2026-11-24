import SwiftUI

struct PasteSourceSheet: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var ticket: UUID?
    @State private var candidate: JSONSourceConfig?
    @State private var previews: [URL] = []
    @State private var message = ""
    @State private var manual: JSONSourceConfig?
    @State private var name = ""
    @State private var imported: [JSONSourceConfig] = []

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("粘贴地址或规则", text: $address, axis: .vertical).lineLimit(1...8).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button(SourceRule.looksLikeRule(address) ? "导入规则" : "识别地址") { run() }.disabled(address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || ticket != nil)
                    if ticket != nil { ProgressView("正在识别…") }
                    if !message.isEmpty { Text(message) }
                } header: {
                    Text("壁纸网站、接口或规则")
                } footer: {
                    Text("以 { 开头的内容按规则导入，包含图源和筛选项；其余内容按地址识别。")
                }
                if !imported.isEmpty {
                    Section("将添加 \(imported.count) 个图源") {
                        ForEach(imported) { config in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(config.name)
                                Text(summary(of: config)).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        Button("确认添加") { saveImported() }
                    }
                }
                if var config = candidate {
                    Section("识别结果") {
                        LabeledContent("类型", value: config.randomImage == true ? "图片直链" : "JSON 列表")
                        if !config.usableFilters.isEmpty {
                            LabeledContent("筛选项", value: config.usableFilters.map(\.title).joined(separator: "、"))
                        }
                        TextField("图源名称", text: $name)
                        ForEach(Array(previews.prefix(3).enumerated()), id: \.offset) { _, url in
                            SnapshotImage(url: url, maxPixels: 600) { phase in
                                switch phase {
                                case .success(let image): image.resizable().scaledToFit().frame(maxHeight: 150)
                                case .failure: Text("图片预览加载失败")
                                default: ProgressView()
                                }
                            }
                        }
                        Button("确认添加") {
                            config.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                            save(config)
                        }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                Button("手动配置") {
                    var draft = candidate ?? JSONSourceConfig()
                    if candidate == nil { draft.endpoint = address.trimmingCharacters(in: .whitespacesAndNewlines) }
                    manual = draft
                }
            }
            .navigationTitle("添加图源")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
            .onChange(of: address) { ticket = nil; candidate = nil; imported = []; message = ""; previews = [] }
            .task(id: ticket) { [id = ticket, text = address] in
                guard let id else { return }
                do {
                    let result = try await SourceProbe.inspect(text)
                    guard !Task.isCancelled, id == ticket else { return }
                    switch result {
                    case .builtinWallhaven: message = "Wallhaven 已内置，无需重复添加。"
                    case .manual(let reason): message = reason
                    case .candidate(let c, let urls):
                        if duplicate(c) { message = "此接口已在图源列表中。" }
                        else { candidate = c; name = c.name; previews = urls }
                    }
                } catch { if !Task.isCancelled, id == ticket { message = error.localizedDescription } }
                if ticket == id { ticket = nil }
            }
            .sheet(item: $manual) { initial in
                SourceConfigEditor(initial: initial) { c in save(c) }
            }
        }
    }
    /// 规则直接解析，不发网络请求；其余文本按地址探测。
    private func run() {
        guard SourceRule.looksLikeRule(address) else { ticket = UUID(); return }
        do {
            let all = try SourceRule.parseAll(address)
            let fresh = all.filter { !duplicate($0) }
            imported = fresh
            message = fresh.isEmpty ? "这些图源的接口都已存在。"
                : fresh.count < all.count ? "已跳过 \(all.count - fresh.count) 个已存在的图源。" : "规则有效，确认后添加。"
        } catch { message = error.localizedDescription }
    }

    private func summary(of config: JSONSourceConfig) -> String {
        var parts = [config.randomImage == true ? "随机直链" : "JSON 列表"]
        if !config.searchParam.isEmpty { parts.append("搜索") }
        if !config.pageParam.isEmpty { parts.append("翻页") }
        let filters = config.usableFilters.map(\.title)
        if !filters.isEmpty { parts.append("筛选：" + filters.joined(separator: "、")) }
        return parts.joined(separator: " · ")
    }

    private func saveImported() {
        for config in imported where !duplicate(config) { settings.save(config) }
        dismiss()
    }

    private func duplicate(_ c: JSONSourceConfig) -> Bool { settings.configs.contains { $0.endpoint == c.endpoint } }
    private func save(_ c: JSONSourceConfig) {
        if duplicate(c) { candidate = nil; message = "此接口已存在。"; return }
        settings.save(c); dismiss()
    }
}
