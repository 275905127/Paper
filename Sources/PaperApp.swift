import SwiftUI

@main
struct PaperApp: App {
    @State private var favorites = FavoritesStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(favorites)
        }
    }
}

struct RootView: View {
    private let source = SourceCatalog.default

    var body: some View {
        TabView {
            Tab("发现", systemImage: "sparkles.rectangle.stack") {
                DiscoverView(source: source)
            }
            Tab("图源", systemImage: "square.stack.3d.up") {
                SourcesView(sources: SourceCatalog.all)
            }
            Tab("收藏", systemImage: "heart") {
                FavoritesView()
            }
            Tab(role: .search) {
                SearchView(source: source)
            }
        }
    }
}
