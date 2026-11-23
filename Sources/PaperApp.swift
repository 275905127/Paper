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

    var body: some View {
        TabView {
            Tab("发现", systemImage: "sparkles.rectangle.stack") {
                DiscoverView(credentials: credentials, source: settings.selectedSource)
            }
            Tab("图源", systemImage: "square.stack.3d.up") {
                SourcesView()
            }
            Tab("收藏", systemImage: "heart") {
                FavoritesView()
            }
            Tab("搜索", systemImage: "magnifyingglass", role: .search) {
                SearchView(credentials: credentials, source: settings.selectedSource)
            }
        }
    }
}
