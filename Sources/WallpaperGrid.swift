import SwiftUI

/// 壁纸缩略图：按图片真实比例显示整图，不裁切。
struct WallpaperThumbnail: View {
    let wallpaper: Wallpaper

    var body: some View {
        Color.clear
            .aspectRatio(wallpaper.aspectRatio, contentMode: .fit)
            .overlay {
                SnapshotImage(url: wallpaper.thumbLarge, maxPixels: 800) { phase in
                    switch phase {
                    case .success(let image):
                        // 格子比例与图片比例一致，用 fill 填满，避免露出底色。
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

/// 发现、搜索、收藏共用的双列网格。
///
/// 原生没有瀑布流容器，这里用两列 `LazyVStack` 并排，
/// 并把每张图分配给当前较矮的一列，让两列高度尽量接近。
struct WallpaperGrid: View {
    @Environment(FavoritesStore.self) private var favorites
    @State private var preview: Wallpaper?
    let items: [Wallpaper]
    var onReachEnd: ((Wallpaper) -> Void)?
    var selection: Binding<Set<String>>?

    private let spacing: CGFloat = 10

    var body: some View {
        let columns = distribute(items)
        HStack(alignment: .top, spacing: spacing) {
            ForEach(columns.indices, id: \.self) { index in
                LazyVStack(spacing: spacing) {
                    ForEach(columns[index]) { wallpaper in
                        cell(for: wallpaper)
                            .onAppear { onReachEnd?(wallpaper) }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .fullScreenCover(item: $preview) { item in
            NavigationStack { WallpaperDetailView(wallpaper: item) }
        }
    }

    /// 按“高 / 宽”累计高度，把每张图放进当前最矮的一列。
    private func distribute(_ items: [Wallpaper]) -> [[Wallpaper]] {
        var columns: [[Wallpaper]] = [[], []]
        var heights: [Double] = [0, 0]
        for item in items {
            let shorter = heights[0] <= heights[1] ? 0 : 1
            columns[shorter].append(item)
            heights[shorter] += 1 / max(item.aspectRatio, 0.2)
        }
        return columns
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
            Button { preview = wallpaper } label: {
                WallpaperThumbnail(wallpaper: wallpaper)
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button(favorites.contains(wallpaper) ? "移出收藏" : "收藏", systemImage: favorites.contains(wallpaper) ? "heart.slash" : "heart") {
                    favorites.toggle(wallpaper)
                }
                ShareLink(item: wallpaper.shareItem) { Label(wallpaper.path.isFileURL ? "分享图片" : "分享来源链接", systemImage: "square.and.arrow.up") }
            }
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
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
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
