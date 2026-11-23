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

    init() {
        let saved = UserDefaults.standard.string(forKey: Self.key)
        if let saved, SourceCatalog.source(id: saved) != nil {
            selectedSourceID = saved
        } else {
            selectedSourceID = SourceCatalog.default.id
        }
    }

    var selectedSource: any WallpaperSource {
        SourceCatalog.source(id: selectedSourceID) ?? SourceCatalog.default
    }
}
