import Foundation
import Observation

/// 轻量的应用设置。目前只记录当前图源。
@MainActor
@Observable
final class AppSettings {
    private static let key = "selectedSourceID"

    var selectedSourceID: String {
        didSet { UserDefaults.standard.set(selectedSourceID, forKey: Self.key) }
    }

    private(set) var configs: [JSONSourceConfig] = []
    private(set) var revision = 0
    var allSources: [any WallpaperSource] {
        SourceCatalog.all + configs.map { config -> any WallpaperSource in
            if config.randomImage == true { return RandomImageSource(config: config) }
            return JSONWallpaperSource(config: config)
        }
    }
    func source(id: String) -> (any WallpaperSource)? { allSources.first { $0.id == id } }
    func save(_ config: JSONSourceConfig) {
        if let i = configs.firstIndex(where: { $0.id == config.id }) { configs[i] = config }
        else { configs.append(config) }
        persist()
    }
    func remove(_ config: JSONSourceConfig) {
        configs.removeAll { $0.id == config.id }
        if selectedSourceID == config.id { selectedSourceID = SourceCatalog.default.id }
        persist()
    }
    private func persist() {
        if let data = try? JSONEncoder().encode(configs) { UserDefaults.standard.set(data, forKey: "paper.jsonSources") }
        revision += 1
    }
    init() {
        selectedSourceID = SourceCatalog.default.id
        if let data = UserDefaults.standard.data(forKey: "paper.jsonSources"), let records = try? JSONDecoder().decode([JSONSourceConfig].self, from: data) { configs = records }

        let saved = UserDefaults.standard.string(forKey: Self.key)
        if let saved, source(id: saved) != nil {
            selectedSourceID = saved
        } else {
            selectedSourceID = SourceCatalog.default.id
        }
    }

    var selectedSource: any WallpaperSource {
        source(id: selectedSourceID) ?? SourceCatalog.default
    }
}
