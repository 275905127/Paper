import SwiftUI

/// 大图预览：图片延伸到安全区，系统栏自动呈现玻璃效果。
struct WallpaperDetailView: View {
    let wallpaper: Wallpaper

    @Environment(FavoritesStore.self) private var favorites
    @Environment(\.dismiss) private var closePreview
    @State private var showInfo = false
    @State private var saveState: SaveState = .idle
    /// 下拉关闭的进度，用来让背景和工具栏随手势渐隐。
    @State private var dismissProgress: CGFloat = 0

    enum SaveState: Equatable {
        case idle, saving, saved
        case failed(String)
    }

    var body: some View {
        ZoomableImage(aspectRatio: CGFloat(wallpaper.aspectRatio),
                      dismissProgress: $dismissProgress,
                      onDismiss: { closePreview() }) {
            SnapshotImage(url: wallpaper.path, maxPixels: 4096) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFit()
                case .failure:
                    ContentUnavailableView("原图加载失败", systemImage: "photo.badge.exclamationmark")
                default:
                    // 原图较大时，先显示已缓存的缩略图兜底
                    if !wallpaper.path.isFileURL { AsyncImage(url: wallpaper.thumbLarge) { thumb in
                        thumb.resizable().scaledToFit()
                    } placeholder: {
                        Color.clear
                    }
                    .overlay { ProgressView() } } else { ProgressView() }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("壁纸大图，\(wallpaper.resolution)")
        // 跟随系统外观：浅色为白，深色为黑；下拉时背景随进度变透明，露出下层内容。
        .background(.background.opacity(1 - dismissProgress * 0.85))
        .ignoresSafeArea()
        .toolbarVisibility(dismissProgress > 0.02 ? .hidden : .automatic, for: .navigationBar, .bottomBar)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(role: .close) { closePreview() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("信息", systemImage: "info.circle") { showInfo = true }
            }
            ToolbarItemGroup(placement: .bottomBar) {
                Button(
                    favorites.contains(wallpaper) ? "取消收藏" : "收藏",
                    systemImage: favorites.contains(wallpaper) ? "heart.fill" : "heart"
                ) {
                    favorites.toggle(wallpaper)
                }
                .symbolEffect(.bounce, value: favorites.contains(wallpaper))
                .contentTransition(.symbolEffect(.replace))
                .sensoryFeedback(.selection, trigger: favorites.contains(wallpaper))

                Spacer()

                ShareLink(item: wallpaper.shareItem) {
                    Label("分享", systemImage: "square.and.arrow.up")
                }

                Spacer()

                Button(saveTitle, systemImage: saveSymbol) { save() }
                    .contentTransition(.symbolEffect(.replace))
                    .disabled(saveState == .saving)
            }
        }
        .sheet(isPresented: $showInfo) {
            InfoSheet(wallpaper: wallpaper)
                .presentationDetents([.medium, .large])
        }
        .alert("保存失败", isPresented: failureBinding) {
            Button("好") { saveState = .idle }
        } message: {
            if case .failed(let message) = saveState { Text(message) }
        }
        .sensoryFeedback(.success, trigger: saveState == .saved)
    }

    private var saveTitle: String {
        switch saveState {
        case .idle, .failed: "保存"
        case .saving: "保存中"
        case .saved: "已保存"
        }
    }

    private var saveSymbol: String {
        saveState == .saved ? "checkmark" : "arrow.down.to.line"
    }

    private var failureBinding: Binding<Bool> {
        Binding(
            get: { if case .failed = saveState { true } else { false } },
            set: { if !$0 { saveState = .idle } }
        )
    }

    private func save() {
        saveState = .saving
        Task {
            do {
                try await PhotoSaver.save(wallpaper)
                saveState = .saved
            } catch is CancellationError {
                saveState = .idle
            } catch {
                saveState = .failed(error.localizedDescription)
            }
        }
    }
}

/// 壁纸信息与“设为壁纸”的操作指引。
struct InfoSheet: View {
    @Environment(AppSettings.self) private var settings
    let wallpaper: Wallpaper
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("信息") {
                    LabeledContent("分辨率", value: wallpaper.resolution)
                    LabeledContent("大小", value: wallpaper.fileSize.formatted(.byteCount(style: .file)))
                    LabeledContent("分类", value: categoryTitle)
                    LabeledContent("浏览", value: wallpaper.views.formatted())
                    LabeledContent("收藏", value: wallpaper.favorites.formatted())
                }
                if let source = wallpaper.source, let url = URL(string: source) {
                    Section("来源") {
                        Link(destination: url) {
                            Label(url.host() ?? source, systemImage: "link")
                        }
                    }
                }
                Section {
                    Link(destination: wallpaper.url) {
                        Label("在 \(sourceName) 中打开", systemImage: "safari")
                    }
                }
                Section {
                    Label("先点“保存”存入相册", systemImage: "1.circle")
                    Label("打开系统“设置 > 墙纸”", systemImage: "2.circle")
                    Label("选择“照片”并选中这张图", systemImage: "3.circle")
                } header: {
                    Text("如何设为壁纸")
                } footer: {
                    Text("iOS 不允许第三方 App 直接设置壁纸，需要在系统设置中完成最后一步。")
                }
            }
            .dynamicTypeSize(...DynamicTypeSize.accessibility3)
            .navigationTitle("壁纸信息")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private var sourceName: String {
        settings.source(id: wallpaper.sourceID)?.name ?? "来源网站"
    }

    private var categoryTitle: String {
        switch wallpaper.category {
        case "general": "综合"
        case "anime": "动漫"
        case "people": "人物"
        default: wallpaper.category
        }
    }
}
