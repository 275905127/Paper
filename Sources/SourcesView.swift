import SwiftUI

/// 图源页：展示图源，管理各图源的密钥。
struct SourcesView: View {
    @Environment(CredentialStore.self) private var credentials
    @Environment(AppSettings.self) private var settings
    @State private var editing: (any WallpaperSource)?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(SourceCatalog.all, id: \.id) { source in
                        row(for: source)
                    }
                } header: {
                    Text("图源")
                } footer: {
                    Text("图片版权归原作者所有。壁纸从图源网站实时加载，受其可用性与限流影响。")
                }

                Section("关于") {
                    LabeledContent("版本", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-")
                }
            }
            .navigationTitle("图源")
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
        VStack(alignment: .leading, spacing: 10) {
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
            }
            .buttonStyle(.plain)

            if let spec = source.credential {
                Button {
                    editing = source
                } label: {
                    Label(
                        credentials.isSet(source.id) ? "\(spec.label)：已设置" : "\(spec.label)：未设置",
                        systemImage: credentials.isSet(source.id) ? "key.fill" : "key"
                    )
                    .font(.footnote)
                }
                .buttonStyle(.glass)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 2)
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
