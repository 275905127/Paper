import SwiftUI

/// 图源页：展示可用图源。当前内置 Wallhaven，结构上已支持扩展。
struct SourcesView: View {
    let sources: [any WallpaperSource]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(sources, id: \.id) { source in
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(source.name)
                                Text(source.summary)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: source.symbol)
                        }
                    }
                } header: {
                    Text("当前图源")
                } footer: {
                    Text("图片版权归原作者所有。壁纸从图源网站实时加载，受其可用性与限流影响。")
                }

                Section("关于") {
                    LabeledContent("版本", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-")
                    Link(destination: URL(string: "https://wallhaven.cc")!) {
                        Label("访问 Wallhaven", systemImage: "safari")
                    }
                }
            }
            .navigationTitle("图源")
        }
    }
}
