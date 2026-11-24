import Foundation
import Security
import Observation

/// 把图源密钥存进系统钥匙串。只存本机，不同步、不进备份明文。
enum Keychain {
    private static let service = "io.github.paper.wallpaper.credentials"

    static func read(account: String) -> String? {
        var query = base(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func write(_ value: String, account: String) -> Bool {
        let data = Data(value.utf8)
        let update = SecItemUpdate(
            base(account) as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if update == errSecSuccess { return true }
        var add = base(account)
        add[kSecValueData as String] = data
        // 仅在设备解锁后可读，且不迁移到其他设备。
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    static func delete(account: String) -> Bool {
        let status = SecItemDelete(base(account) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    private static func base(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

/// 各图源的密钥状态。界面读取 `isSet`，网络层通过 `value(for:)` 取值。
@MainActor
@Observable
final class CredentialStore {
    /// 每个图源是否已有密钥。只暴露布尔值，避免密钥进入界面状态。
    private(set) var configured: Set<String> = []
    /// 版本号：密钥变化时自增，让依赖它的列表重新加载。
    private(set) var revision = 0

    init() {
        for source in SourceCatalog.all where Keychain.read(account: source.id) != nil {
            configured.insert(source.id)
        }
    }

    func isSet(_ sourceID: String) -> Bool { configured.contains(sourceID) }

    func value(for sourceID: String) -> String? {
        Keychain.read(account: sourceID)
    }

    func save(_ key: String, for sourceID: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if Keychain.write(trimmed, account: sourceID) {
            configured.insert(sourceID)
            revision += 1
        }
    }

    func remove(for sourceID: String) {
        Keychain.delete(account: sourceID)
        configured.remove(sourceID)
        revision += 1
    }
}
