import SwiftUI

/// 收藏页：本地收藏网格，支持多选批量删除。
struct FavoritesView: View {
    @Environment(FavoritesStore.self) private var favorites
    @State private var selection = Set<String>()
    @State private var isEditing = false
    @State private var confirmDelete = false

    @State private var showsSelection = false
    private var selected: [Wallpaper] { favorites.items.filter { selection.contains($0.id) } }

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
                        selection: isEditing ? $selection : nil
                    )
                }
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .navigationTitle("收藏")
            .toolbarVisibility(isEditing ? .hidden : .automatic, for: .tabBar)
            .toolbar {
                if isEditing {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(selection.count == favorites.items.count ? "取消全选" : "全选") {
                            selection = selection.count == favorites.items.count ? [] : Set(favorites.items.map(\.id))
                        }
                    }
                    ToolbarItem(placement: .bottomBar) {
                        ShareLink(items: selected.map(\.url)) { Label("分享所选壁纸链接", systemImage: "square.and.arrow.up") }
                            .disabled(selection.isEmpty)
                    }
                    ToolbarSpacer(.flexible, placement: .bottomBar)
                    ToolbarItem(placement: .bottomBar) {
                        Button("显示所选内容 (\(selection.count))") { showsSelection = true }
                            .disabled(selection.isEmpty)
                    }
                    ToolbarSpacer(.flexible, placement: .bottomBar)
                    ToolbarItem(placement: .bottomBar) {
                        Button("移出收藏", systemImage: "trash", role: .destructive) { confirmDelete = true }
                            .disabled(selection.isEmpty)
                            .confirmationDialog(
                                "从收藏中移出 \(selection.count) 张？",
                                isPresented: $confirmDelete,
                                titleVisibility: .visible
                            ) {
                                Button("移出收藏", role: .destructive) {
                                    favorites.remove(ids: selection)
                                    selection.removeAll()
                                    if favorites.items.isEmpty { isEditing = false }
                                }
                            }
                    }
                }
                if !favorites.items.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(isEditing ? "完成" : "选择") {
                            isEditing.toggle()
                            selection.removeAll()
                        }
                    }
                }
            }
            .sheet(isPresented: $showsSelection) {
                NavigationStack {
                    ScrollView { WallpaperGrid(items: selected) }
                        .navigationTitle("所选内容 (\(selected.count))")
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showsSelection = false } } }
                }
            }

        }
    }

}
