import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct RandomImageSource: WallpaperSource {
    let config: JSONSourceConfig
    var id: String { config.id }
    var name: String { config.name.isEmpty ? "随机图片" : config.name }
    let summary = "每次刷新获取一张公开 HTTPS 图片"
    let symbol = "shuffle"
    var capabilities: SourceCapabilities { [] }
    var filterFields: [FilterField] { [] }
    private var endpoint: URL? {
        URL(string: config.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap(publicHTTPS)
    }
    var homepage: URL { endpoint ?? URL(string: "about:blank")! }

    /// 仅把本图源约定的快照相对路径映射到当前容器；不重新请求入口。
    static func relocated(_ url: URL) -> URL {
        guard let name = Snapshots.filename(of: url) else { return url }
        return Snapshots.directory.appendingPathComponent(name)
    }

    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.urlCache = nil
        c.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        c.urlCredentialStorage = nil
        c.httpCookieStorage = nil
        c.httpShouldSetCookies = false
        c.timeoutIntervalForResource = 60
        return URLSession(configuration: c, delegate: PublicImageRequests(), delegateQueue: nil)
    }()

    func page(_ number: Int, query _: Query, credential _: String?) async throws -> SourcePage {
        try Task.checkCancellation()
        guard number == 1 else { return SourcePage(items: [], hasMore: false) }
        guard let endpoint else { throw SourceError.network("请输入不含账号密码的 HTTPS 图片地址。") }
        let (bytes, response) = try await Self.session.bytes(for: PublicImageRequests.request(endpoint))
        defer { bytes.task.cancel() }
        guard let http = response as? HTTPURLResponse, http.url.flatMap(publicHTTPS) != nil else {
            throw SourceError.network("图片响应不是公开 HTTPS 响应。")
        }
        switch http.statusCode {
        case 200: break
        case 403: throw SourceError.network("服务器拒绝访问（403）。请选择可公开直连的图片接口。")
        case 300..<400: throw SourceError.network("未取得图片：重定向目标必须是无账号密码的 HTTPS 地址。")
        default: throw SourceError.badResponse(http.statusCode)
        }
        let html = SourceError.network("接口返回 HTML 网页而非图片；不支持登录或验证页面。")
        if ["text/html", "application/xhtml+xml"].contains(http.mimeType?.lowercased() ?? "") { throw html }
        let limit = 16 * 1024 * 1024
        let tooLarge = SourceError.network("图片超过 16 MiB 下载上限。")
        guard http.expectedContentLength <= Int64(limit) else { throw tooLarge }
        var data = Data()
        for try await byte in bytes {
            guard data.count < limit else { throw tooLarge }
            if data.count.isMultiple(of: 65536) { try Task.checkCancellation() }
            data.append(byte)
        }
        try Task.checkCancellation()
        let prefix = String(decoding: data.prefix(1024), as: UTF8.self).lowercased()
        if prefix.contains("<!doctype html") || prefix.contains("<html") { throw html }
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let image = CGImageSourceCreateWithData(data as CFData, options),
              CGImageSourceGetStatus(image) == .statusComplete,
              let identifier = CGImageSourceGetType(image), let type = UTType(identifier as String),
              type.conforms(to: .image), let ext = type.preferredFilenameExtension,
              let props = CGImageSourceCopyPropertiesAtIndex(image, 0, options) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int,
              w > 0, h > 0, w <= 48_000_000 / h else {
            throw SourceError.network("响应不是受支持的完整图片，或分辨率超过 4800 万像素。")
        }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let file = try await Snapshots.shared.store(data, filename: "\(digest).\(ext)")
        let rotated = (5...8).contains(props[kCGImagePropertyOrientation] as? Int ?? 1)
        let item = Wallpaper(id: "\(id):\(digest)", url: endpoint, path: file, thumbLarge: file, thumbSmall: file,
                             width: rotated ? h : w, height: rotated ? w : h, fileSize: data.count,
                             fileType: type.preferredMIMEType ?? "", category: "", views: 0, favorites: 0,
                             colors: [], source: nil, sourceID: id)
        return SourcePage(items: [item], hasMore: false)
    }
}

private func publicHTTPS(_ url: URL) -> URL? {
    guard url.scheme?.lowercased() == "https", !(url.host ?? "").isEmpty,
          url.user == nil, url.password == nil else { return nil }
    return url
}

private final class PublicImageRequests: NSObject, URLSessionTaskDelegate {
    static func request(_ url: URL) -> URLRequest {
        var r = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
        r.setValue("image/*", forHTTPHeaderField: "Accept")
        r.setValue("no-cache, no-store", forHTTPHeaderField: "Cache-Control")
        return r
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url.flatMap(publicHTTPS).map(Self.request))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let trust = challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust
        completionHandler(trust ? .performDefaultHandling : .rejectProtectionSpace, nil)
    }
}

/// All sources share one content-addressed store and one serialized admission decision.
private actor Snapshots {
    static let shared = Snapshots()
    static let directory = URL.applicationSupportDirectory.appendingPathComponent("RandomImageSnapshots", isDirectory: true)

    static func filename(of url: URL) -> String? {
        guard url.isFileURL, (url.host ?? "").isEmpty, url.query == nil, url.fragment == nil,
              url.deletingLastPathComponent().pathComponents.suffix(3).elementsEqual(directory.pathComponents.suffix(3)),
              url.lastPathComponent.range(of: #"^[0-9a-f]{64}\.[a-z0-9]{1,12}$"#, options: .regularExpression) != nil
        else { return nil }
        return url.lastPathComponent
    }

    private func favoriteNames() throws -> Set<String> {
        let file = URL.applicationSupportDirectory.appendingPathComponent("favorites.json")
        do {
            let favorites = try JSONDecoder().decode([Wallpaper].self, from: Data(contentsOf: file))
            return Set(favorites.flatMap { [$0.path, $0.thumbLarge, $0.thumbSmall] }.compactMap(Self.filename(of:)))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return []
        } catch {
            throw SourceError.network("无法确认收藏状态，为保护已有快照，已停止清理。")
        }
    }

    func store(_ data: Data, filename: String) throws -> URL {
        try Task.checkCancellation()
        let fm = FileManager.default, dir = Self.directory
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent(filename)
        guard Self.filename(of: file) != nil else { throw SourceError.network("无法确定快照文件类型。") }
        if fm.fileExists(atPath: file.path) {
            try fm.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
            return file
        }

        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        var entries: [(url: URL, bytes: Int, date: Date)] = []
        var bytes = data.count
        for url in try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: Array(keys)) {
            guard Self.filename(of: url) != nil else { continue }
            let values = try url.resourceValues(forKeys: keys)
            guard values.isRegularFile == true, let size = values.fileSize else { continue }
            bytes += size
            entries.append((url, size, values.contentModificationDate ?? .distantPast))
        }
        var count = entries.count + 1
        let budget = 256 * 1024 * 1024
        if bytes > budget || count > 256 {
            let pinned = try favoriteNames()
            var victims: [URL] = []
            for entry in entries.sorted(by: { $0.date < $1.date }) {
                if bytes <= budget && count <= 256 { break }
                guard !pinned.contains(entry.url.lastPathComponent) else { continue }
                victims.append(entry.url)
                bytes -= entry.bytes
                count -= 1
            }
            guard bytes <= budget, count <= 256 else {
                throw SourceError.network("快照空间已被收藏占满，请取消部分收藏后重试。")
            }
            for victim in victims { try fm.removeItem(at: victim) }
        }
        try data.write(to: file, options: .atomic)
        return file
    }
}
