import SwiftUI

/// 收藏页：本地收藏网格，支持多选批量删除。
struct FavoritesView: View {
    @Environment(FavoritesStore.self) private var favorites
    @State private var selection = Set<String>()
    @State private var isEditing = false
    @State private var confirmDelete = false
    @Namespace private var namespace

    var body: some View {
        NavigationStack {
            ScrollView {
                if favorites.items.isEmpty {
                    ContentUnavailableView(
                        "还没有收藏",
                        systemImage: "heart",
                        description: Text("在壁纸大图页点心形按钮，就会出现在这里。")
                    )
                    .containerRelativeFrame(.vertical) { height, _ in height * 0.7 }
                } else {
                    WallpaperGrid(
                        items: favorites.items,
                        selection: isEditing ? $selection : nil,
                        namespace: namespace
                    )
                }
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .navigationTitle("收藏")
            .safeAreaInset(edge: .bottom) {
                if isEditing {
                    editBar
                }
            }
            .navigationDestination(for: Wallpaper.self) { wallpaper in
                WallpaperDetailView(wallpaper: wallpaper)
                    .navigationTransition(.zoom(sourceID: wallpaper.id, in: namespace))
            }
            .toolbar {
                if !favorites.items.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(isEditing ? "完成" : "选择") {
                            isEditing.toggle()
                            selection.removeAll()
                        }
                    }
                }
            }
            .confirmationDialog(
                "删除 \(selection.count) 张收藏？",
                isPresented: $confirmDelete,
                titleVisibility: .visible
            ) {
                Button("删除", role: .destructive) {
                    favorites.remove(ids: selection)
                    selection.removeAll()
                    if favorites.items.isEmpty { isEditing = false }
                }
            }
        }
    }

    /// 编辑模式下的底部操作栏。作为安全区插入，始终位于系统标签栏上方，两者不会叠在一起。
    private var editBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Button("删除 \(selection.count) 张", systemImage: "trash", role: .destructive) {
                    confirmDelete = true
                }
                .disabled(selection.isEmpty)
                Spacer()
                Button(selection.count == favorites.items.count ? "取消全选" : "全选") {
                    if selection.count == favorites.items.count {
                        selection.removeAll()
                    } else {
                        selection = Set(favorites.items.map(\.id))
                    }
                }
            }
            .buttonStyle(.borderless)
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.bar)
        }
    }
}
