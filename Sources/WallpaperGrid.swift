import SwiftUI

/// 壁纸缩略图。固定竖屏比例裁切，统一网格节奏，加载时不跳动。
struct WallpaperThumbnail: View {
    let wallpaper: Wallpaper

    var body: some View {
        Color.clear
            .aspectRatio(9.0 / 16.0, contentMode: .fit)
            .overlay {
                AsyncImage(url: wallpaper.thumbLarge) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        Image(systemName: "photo")
                            .font(.title)
                            .foregroundStyle(.secondary)
                    default:
                        ProgressView()
                    }
                }
            }
            .background(.quaternary)
            .clipShape(.rect(cornerRadius: 14))
            .accessibilityLabel("壁纸 \(wallpaper.resolution)")
    }
}

/// 发现、搜索、收藏共用的两列网格。
struct WallpaperGrid: View {
    let items: [Wallpaper]
    var onReachEnd: ((Wallpaper) -> Void)?
    var selection: Binding<Set<String>>?
    let namespace: Namespace.ID

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 10)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(items) { wallpaper in
                cell(for: wallpaper)
                    .onAppear { onReachEnd?(wallpaper) }
            }
        }
        .padding(.horizontal, 12)
    }

    @ViewBuilder
    private func cell(for wallpaper: Wallpaper) -> some View {
        if let selection {
            let isSelected = selection.wrappedValue.contains(wallpaper.id)
            Button {
                if isSelected {
                    selection.wrappedValue.remove(wallpaper.id)
                } else {
                    selection.wrappedValue.insert(wallpaper.id)
                }
            } label: {
                WallpaperThumbnail(wallpaper: wallpaper)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title2)
                            .foregroundStyle(isSelected ? Color.accentColor : .white)
                            .padding(8)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        } else {
            NavigationLink(value: wallpaper) {
                WallpaperThumbnail(wallpaper: wallpaper)
                    .matchedTransitionSource(id: wallpaper.id, in: namespace)
            }
            .buttonStyle(.plain)
        }
    }
}

/// 列表底部的加载 / 失败 / 到底提示。
struct FeedFooter: View {
    let store: FeedStore

    var body: some View {
        Group {
            switch store.phase {
            case .loading:
                ProgressView().padding()
            case .failed(let message):
                VStack(spacing: 8) {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                    Button("重试") { store.loadMore() }
                        .buttonStyle(.glass)
                }
                .padding()
            case .idle:
                if !store.hasMore && !store.items.isEmpty {
                    Text("已经到底了").font(.footnote).foregroundStyle(.secondary).padding()
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}
