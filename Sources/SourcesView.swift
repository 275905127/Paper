import SwiftUI

/// 图源页：展示图源，管理各图源的密钥。
struct SourcesView: View {
    @Environment(CredentialStore.self) private var credentials
    @Environment(AppSettings.self) private var settings
    @State private var editing: (any WallpaperSource)?

    @State private var adding = false
    @State private var editor: JSONSourceConfig?
    @State private var removing: JSONSourceConfig?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(settings.allSources, id: \.id) { source in
                        row(for: source)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if source.credential != nil {
                                    Button("API 密钥", systemImage: "key") { editing = source }
                                        .tint(.blue)
                                }
                                if let config = settings.configs.first(where: { $0.id == source.id }) {
                                    Button("编辑", systemImage: "slider.horizontal.3") { editor = config }
                                        .tint(.blue)
                                    Button("移除", systemImage: "trash", role: .destructive) { removing = config }
                                }
                            }
                    }
                } footer: {
                    Text("轻点切换图源，向左滑动显示管理操作。")
                }

                Section {
                    LabeledContent("版本", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-")
                } header: {
                    Text("关于")
                } footer: {
                    Text("壁纸由图源网站提供，版权归原作者所有。")
                }
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .navigationTitle("图源")
            .toolbar {
                if !settings.configs.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        ShareLink("导出规则", item: SourceRule.export(settings.configs))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) { Button("添加图源", systemImage: "plus") { adding = true } }
            }
            .sheet(isPresented: $adding) { PasteSourceSheet() }
            .sheet(item: $editor) { config in
                SourceConfigEditor(initial: config) { settings.save($0) }
            }
            .alert("移除此图源？", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), presenting: removing) { config in
                Button("移除", role: .destructive) { settings.remove(config) }
                Button("取消", role: .cancel) { }
            } message: { _ in Text("已收藏的壁纸不会被删除。") }
            .sheet(item: Binding(
                get: { editing.map { AnySource(source: $0) } },
                set: { editing = $0?.source }
            )) { wrapper in
                CredentialSheet(source: wrapper.source)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    @ViewBuilder
    private func row(for source: any WallpaperSource) -> some View {
        let isCurrent = settings.selectedSourceID == source.id
        Button {
            settings.selectedSourceID = source.id
        } label: {
            HStack {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(source.name).foregroundStyle(.primary)
                        Text(source.summary)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: source.symbol)
                }
                Spacer()
                if isCurrent {
                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}

/// `sheet(item:)` 需要 Identifiable，而协议存在类型本身不是，这里包一层。
private struct AnySource: Identifiable {
    let source: any WallpaperSource
    var id: String { source.id }
}

/// 密钥输入、校验与删除。
struct CredentialSheet: View {
    let source: any WallpaperSource

    @Environment(CredentialStore.self) private var credentials
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var phase: Phase = .idle

    enum Phase: Equatable {
        case idle, checking
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let spec = source.credential {
                    Section {
                        SecureField(spec.label, text: $input)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textContentType(.password)
                    } header: {
                        Text(source.name)
                    } footer: {
                        Text(spec.help)
                    }

                    if let url = spec.applyURL {
                        Section {
                            Link(destination: url) {
                                Label("去获取密钥", systemImage: "safari")
                            }
                        }
                    }

                    if case .failed(let message) = phase {
                        Section {
                            Label(message, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.red)
                        }
                    }

                    if credentials.isSet(source.id) {
                        Section {
                            Button("删除已保存的密钥", role: .destructive) {
                                credentials.remove(for: source.id)
                                dismiss()
                            }
                        } footer: {
                            Text("密钥保存在本机钥匙串中，不会上传或同步。")
                        }
                    }
                }
            }
            .navigationTitle("密钥")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if phase == .checking {
                        ProgressView()
                    } else {
                        Button("验证并保存") { verify() }
                            .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
    }

    private func verify() {
        let key = input.trimmingCharacters(in: .whitespacesAndNewlines)
        phase = .checking
        Task {
            do {
                if try await source.validate(credential: key) {
                    credentials.save(key, for: source.id)
                    dismiss()
                } else {
                    phase = .failed("密钥无效，请检查后重试。")
                }
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }
}
