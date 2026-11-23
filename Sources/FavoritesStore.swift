import Foundation
import Observation

/// 本地收藏。以 JSON 文件持久化到 Application Support。
@MainActor
@Observable
final class FavoritesStore {
    private(set) var items: [Wallpaper] = []

    private let fileURL: URL

    init() {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )) ?? FileManager.default.temporaryDirectory
        fileURL = base.appendingPathComponent("favorites.json")
        load()
    }

    func contains(_ wallpaper: Wallpaper) -> Bool {
        items.contains { $0.id == wallpaper.id }
    }

    func toggle(_ wallpaper: Wallpaper) {
        if let index = items.firstIndex(where: { $0.id == wallpaper.id }) {
            items.remove(at: index)
        } else {
            items.insert(wallpaper, at: 0)
        }
        save()
    }

    func remove(ids: Set<String>) {
        items.removeAll { ids.contains($0.id) }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([Wallpaper].self, from: data)
        else { return }
        items = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
