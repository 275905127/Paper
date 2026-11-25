import SwiftUI

@main
struct PaperApp: App {
    @State private var favorites = FavoritesStore()
    @State private var credentials = CredentialStore()
    @State private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            RootView(credentials: credentials, settings: settings)
                .environment(favorites)
                .environment(credentials)
                .environment(settings)
        }
    }
}

struct RootView: View {
    let credentials: CredentialStore
    let settings: AppSettings

    private enum Page: Hashable { case discover, sources, favorites, search }
    @State private var page: Page = .discover

    var body: some View {
        TabView(selection: $page) {
            Tab("发现", systemImage: "sparkles.rectangle.stack", value: Page.discover) {
                DiscoverView(credentials: credentials, source: settings.selectedSource)
            }
            Tab("图源", systemImage: "square.stack.3d.up", value: Page.sources) {
                SourcesView()
            }
            Tab("收藏", systemImage: "heart", value: Page.favorites) {
                FavoritesView()
            }
            Tab("搜索", systemImage: "magnifyingglass", value: Page.search, role: .search) {
                SearchView(credentials: credentials, source: settings.selectedSource)
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .sensoryFeedback(.selection, trigger: page)
    }
}
