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

    var body: some View {
        NavigationStack {
            Form {
                Section("壁纸网站或接口") {
                    TextField("https://…", text: $address).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("识别地址") { ticket = UUID() }.disabled(address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || ticket != nil)
                    if ticket != nil { ProgressView("正在识别…") }
                    if !message.isEmpty { Text(message) }
                }
                if var config = candidate {
                    Section("识别结果") {
                        LabeledContent("类型", value: config.randomImage == true ? "图片直链" : "JSON 列表")
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
            .onChange(of: address) { ticket = nil; candidate = nil; message = ""; previews = [] }
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
    private func duplicate(_ c: JSONSourceConfig) -> Bool { settings.configs.contains { $0.endpoint == c.endpoint } }
    private func save(_ c: JSONSourceConfig) {
        if duplicate(c) { candidate = nil; message = "此接口已存在。"; return }
        settings.save(c); dismiss()
    }
}
