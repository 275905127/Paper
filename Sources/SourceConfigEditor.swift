import SwiftUI

struct SourceConfigEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: JSONSourceConfig
    @State private var requestID: UUID?
    @State private var result: String?
    private let onSave: (JSONSourceConfig) -> Void

    init(initial: JSONSourceConfig, onSave: @escaping (JSONSourceConfig) -> Void) {
        _draft = State(initialValue: initial)
        self.onSave = onSave
    }

    private var config: JSONSourceConfig {
        var value = draft
        value.name = value.name.trimmingCharacters(in: .whitespacesAndNewlines)
        value.endpoint = value.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        return value
    }

    private var validationError: String? {
        let value = config
        guard !value.name.isEmpty else { return "请输入图源名称。" }
        guard let url = URL(string: value.endpoint, encodingInvalidCharacters: false),
              url.scheme?.lowercased() == "https", let host = url.host, !host.isEmpty,
              url.port.map({ (1...65535).contains($0) }) ?? true else {
            return "请输入包含主机名的有效 HTTPS 地址。"
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("类型", selection: Binding(get: { draft.randomImage == true }, set: { random in
                        draft.randomImage = random ? true : nil
                        invalidateTest()
                    })) {
                        Text("JSON 列表").tag(false)
                        Text("随机直链").tag(true)
                    }
                    field("名称", \.name)
                    field("接口地址", \.endpoint).keyboardType(.URL)
                } header: {
                    Text("图源")
                } footer: {
                    if let validationError { Text(validationError) }
                }
                if draft.randomImage != true {
                    Section {
                        field("列表路径", \.listPath)
                        field("原图地址路径", \.imagePath)
                        field("缩略图地址路径", \.thumbPath)
                        field("宽度路径", \.widthPath)
                        field("高度路径", \.heightPath)
                    } header: {
                        Text("JSON 字段映射")
                    } footer: {
                        Text("若 JSON 顶层就是数组，列表路径请留空。其余路径相对于每条记录。")
                    }
                    Section("请求参数") {
                        field("搜索参数名", \.searchParam)
                        field("页码参数名", \.pageParam)
                    }
                }
                filterSection
                Section("测试图源") {
                    Button(draft.randomImage == true ? "测试随机图片" : "测试第一页") {
                        result = nil
                        requestID = UUID()
                    }
                    .disabled(validationError != nil || requestID != nil)
                    if requestID != nil {
                        ProgressView(draft.randomImage == true ? "正在请求图片…" : "正在请求第一页…")
                    }
                    if let result { Text(result) }
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .navigationTitle("图源设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        guard validationError == nil else { return }
                        onSave(config)
                        dismiss()
                    }
                    .disabled(validationError != nil)
                }
            }
            .task(id: requestID) { [id = requestID, snapshot = config] in
                if let id { await test(snapshot, id: id) }
            }
        }
    }

    @ViewBuilder private var filterSection: some View {
        Section {
            ForEach($draft.customFilters.orEmpty) { $item in
                NavigationLink {
                    CustomFilterForm(item: $item) { invalidateTest() }
                } label: {
                    LabeledContent(item.title.isEmpty ? "未命名筛选" : item.title,
                                   value: item.cleanParam.isEmpty ? "未填参数" : item.cleanParam)
                }
            }
            .onDelete { offsets in
                draft.customFilters?.remove(atOffsets: offsets)
                invalidateTest()
            }
            Button("添加筛选项", systemImage: "plus") {
                draft.customFilters = (draft.customFilters ?? []) + [CustomFilter()]
                invalidateTest()
            }
        } header: {
            Text("筛选项")
        } footer: {
            Text("每个筛选项对应请求里的一个查询参数，选择后附加到接口地址。留空的选项不会发送。")
        }
    }

    private func field(_ title: LocalizedStringKey, _ key: WritableKeyPath<JSONSourceConfig, String>) -> some View {
        LabeledContent(title) {
            TextField(title, text: Binding(get: { draft[keyPath: key] }, set: { text in
                draft[keyPath: key] = text
                invalidateTest()
            }))
            .multilineTextAlignment(.trailing)
        }
    }

    private func invalidateTest() {
        requestID = nil
        result = nil
    }

    @MainActor private func test(_ config: JSONSourceConfig, id: UUID) async {
        let message: String
        do {
            if config.randomImage == true {
                let page = try await RandomImageSource(config: config).page(1, query: Query(), credential: nil)
                guard let image = page.items.first else { throw SourceError.network("接口未返回图片。") }
                message = "图片尺寸：\(image.resolution) 像素。"
            } else {
                let page = try await JSONWallpaperSource(config: config).page(1, query: Query(), credential: nil)
                message = page.items.isEmpty ? "第一页未解析到壁纸，请检查列表和原图路径。" : "第一页已解析 \(page.items.count) 张壁纸。"
            }
        } catch {
            message = "测试失败：\(error.localizedDescription)"
        }
        guard !Task.isCancelled, requestID == id else { return }
        result = message
        requestID = nil
    }
}

private extension Binding where Value == [CustomFilter]? {
    /// 把可空数组当作空数组编辑，供 ForEach 使用。
    var orEmpty: Binding<[CustomFilter]> {
        Binding<[CustomFilter]>(get: { wrappedValue ?? [] }, set: { wrappedValue = $0.isEmpty ? nil : $0 })
    }
}

/// 单个筛选项的编辑页。
private struct CustomFilterForm: View {
    @Binding var item: CustomFilter
    let onChange: () -> Void

    var body: some View {
        Form {
            Section {
                LabeledContent("名称") {
                    TextField("例如 分级", text: $item.title).multilineTextAlignment(.trailing)
                }
                LabeledContent("参数名") {
                    TextField("例如 rating", text: $item.param).multilineTextAlignment(.trailing)
                }
                Picker("类型", selection: $item.kind) {
                    Text("单选").tag(CustomFilter.Kind.choice)
                    Text("开关").tag(CustomFilter.Kind.toggle)
                    Text("文本").tag(CustomFilter.Kind.text)
                }
            }
            switch item.kind {
            case .choice:
                Section {
                    ForEach($item.choices) { $choice in
                        HStack {
                            TextField("显示名", text: $choice.title)
                            Divider()
                            TextField("参数值", text: $choice.value).multilineTextAlignment(.trailing)
                        }
                    }
                    .onDelete { item.choices.remove(atOffsets: $0) }
                    Button("添加选项", systemImage: "plus") { item.choices.append(.init()) }
                } header: {
                    Text("选项")
                } footer: {
                    Text("参数值留空表示选择该项时不发送此参数，可用来表示“全部”。第一项为默认值。")
                }
            case .toggle:
                Section {
                    LabeledContent("打开时的值") {
                        TextField("true", text: $item.onValue).multilineTextAlignment(.trailing)
                    }
                } footer: {
                    Text("关闭时不发送此参数。")
                }
            case .text:
                EmptyView()
            }
        }
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .navigationTitle(item.title.isEmpty ? "筛选项" : item.title)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: item) { onChange() }
    }
}
