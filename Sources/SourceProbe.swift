import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ProbeResult {
    case builtinWallhaven
    case candidate(JSONSourceConfig, [URL])
    case manual(String)
}

private func allowed(_ url: URL) -> Bool {
    guard url.scheme?.lowercased() == "https", !(url.host ?? "").isEmpty,
          url.user == nil, url.password == nil else { return false }
    let secrets = ["apikey", "key", "token", "accesstoken", "password", "authorization", "signature", "xamzsignature"]
    return !(URLComponents(url: url, resolvingAgainstBaseURL: true)?.queryItems ?? []).contains {
        secrets.contains($0.name.lowercased().filter { $0.isLetter })
    }
}

private final class ProbeRequests: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url, allowed(url) else { completionHandler(nil); return }
        completionHandler(URLRequest(url: url))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let trust = challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust
        completionHandler(trust ? .performDefaultHandling : .cancelAuthenticationChallenge, nil)
    }
}

enum SourceProbe {
    static func inspect(_ text: String) async throws -> ProbeResult {
        try Task.checkCancellation()
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let address = input.contains("://") ? input : "https://" + input
        guard let url = URL(string: address, encodingInvalidCharacters: false), allowed(url), let host = url.host?.lowercased() else {
            return .manual("请输入不含凭据的公开 HTTPS 地址。")
        }
        if host == "wallhaven.cc" || host.hasSuffix(".wallhaven.cc") { return .builtinWallhaven }
        var config = JSONSourceConfig()
        config.name = host
        config.endpoint = url.absoluteString
        guard let endpoint = URL(string: config.endpoint) else { return .manual("接口地址无效。") }

        let settings = URLSessionConfiguration.ephemeral
        settings.urlCredentialStorage = nil
        settings.httpCookieStorage = nil
        settings.httpShouldSetCookies = false
        settings.urlCache = nil
        settings.timeoutIntervalForRequest = 8
        settings.timeoutIntervalForResource = 15
        let session = URLSession(configuration: settings, delegate: ProbeRequests(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(from: endpoint)
        defer { bytes.task.cancel() }
        guard let http = response as? HTTPURLResponse, let base = http.url, allowed(base) else { return .manual("无效的 HTTPS 响应。") }
        guard http.statusCode == 200 else {
            if http.statusCode == 403 { return .manual("服务器拒绝访问（403），不会尝试绕过。") }
            return .manual("接口返回 HTTP \(http.statusCode)，请检查公开地址。")
        }
        if ["text/html", "application/xhtml+xml"].contains(http.mimeType ?? "") { return .manual("这是网页，请手动填写网站公开声明的 JSON 接口。") }
        let limit = 4 * 1024 * 1024
        guard http.expectedContentLength <= Int64(limit) else { return .manual("响应超过 4 MiB 探测上限。") }
        var data = Data()
        for try await byte in bytes {
            guard data.count < limit else { return .manual("响应超过 4 MiB 探测上限。") }
            if data.count.isMultiple(of: 65536) { try Task.checkCancellation() }
            data.append(byte)
        }
        try Task.checkCancellation()
        if let json = try? JSONSerialization.jsonObject(with: data) {
            return infer(json, config: config, base: base)
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0,
              CGImageSourceGetStatus(source) == .statusComplete, let identifier = CGImageSourceGetType(source),
              let type = UTType(identifier as String), type.conforms(to: .image), let ext = type.preferredFilenameExtension,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = properties[kCGImagePropertyPixelWidth] as? Int, let h = properties[kCGImagePropertyPixelHeight] as? Int,
              w > 0, h > 0, w <= 48_000_000 / h,
              CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: 128] as CFDictionary) != nil else {
            return .manual("未识别到 JSON 列表或可预览的完整图片，请手动配置。")
        }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
        try data.write(to: file, options: .atomic)
        config.randomImage = true
        return .candidate(config, [file])
    }
}

private extension SourceProbe {
    // Only dictionary keys are representable by JSONWallpaperSource's dot paths.
    static func walk(_ value: Any, path: [String] = [], visit: ([String], Any) -> Void) {
        if let object = value as? [String: Any] {
            guard path.count < 8, object.count <= 128 else { return }
            for key in object.keys.sorted() where !key.isEmpty && !key.contains(".") {
                if let child = object[key] { walk(child, path: path + [key], visit: visit) }
            }
        } else { visit(path, value) }
    }

    static func infer(_ root: Any, config: JSONSourceConfig, base: URL) -> ProbeResult {
        var best = 0, result = ProbeResult.manual("样本没有可识别的图片列表，请手动指定字段。")
        walk(root) { list, value in
            guard let rows = value as? [Any] else { return }
            var samples = [(images: [String: URL], thumbs: [String: URL], dimensions: [String: Int])]()
            var ranks = [String: Int]()
            for row in rows.prefix(16) {
                var images = [String: URL](), thumbs = [String: URL](), dims = [String: Int]()
                walk(row) { keys, leaf in
                    let path = keys.joined(separator: ".")
                    let names = keys.map { $0.lowercased().filter { $0.isLetter } }
                    let name = names.last ?? ""
                    if ["width", "height", "w", "h"].contains(name),
                       let text = (leaf as? String) ?? (leaf as? NSNumber)?.stringValue,
                       let n = Int(text), n > 0 { dims[path] = n; return }
                    guard let raw = leaf as? String else { return }
                    let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty, let url = URL(string: text, relativeTo: base)?.absoluteURL, allowed(url) else { return }
                    let isFile = ["jpg", "jpeg", "png", "webp", "heic", "avif", "gif"].contains(url.pathExtension.lowercased())
                    guard isFile || text.hasPrefix("/") || text.hasPrefix("https://") else { return }
                    if names.contains(where: { $0.contains("thumb") || ["preview", "previewurl", "small", "smallurl"].contains($0) }) {
                        thumbs[path] = url; return
                    }
                    let rank: Int
                    if names.contains(where: { ["original", "originalurl", "full", "fullsize", "fullurl", "downloadurl", "raw"].contains($0) }) { rank = 5 }
                    else if ["imageurl", "image", "src", "large", "regular", "path"].contains(name) { rank = 4 }
                    else if isFile { rank = 3 }
                    else if name == "url" { rank = 1 }
                    else { return }
                    images[path] = url; ranks[path] = max(ranks[path] ?? 0, rank)
                }
                samples.append((images, thumbs, dims))
            }
            for path in ranks.keys.sorted() {
                let matches = samples.filter { $0.images[path] != nil }
                let score = (ranks[path] ?? 0) * 20 + matches.count
                guard score > best else { continue }
                func frequent(_ paths: [String]) -> String {
                    let counts = Dictionary(grouping: paths, by: { $0 }).mapValues { $0.count }
                    return counts.keys.sorted().max { counts[$0, default: 0] < counts[$1, default: 0] } ?? ""
                }
                let dims = matches.flatMap { Array($0.dimensions.keys) }
                func dimension(_ names: [String]) -> String {
                    frequent(dims.filter { names.contains($0.components(separatedBy: ".").last?.lowercased() ?? "") })
                }
                var candidate = config
                candidate.listPath = list.joined(separator: "."); candidate.imagePath = path
                candidate.thumbPath = frequent(matches.flatMap { Array($0.thumbs.keys) })
                candidate.widthPath = dimension(["width", "w"]); candidate.heightPath = dimension(["height", "h"])
                var seen = Set<URL>(), previews = [URL]()
                for row in matches {
                    guard let image = row.images[path], seen.insert(image).inserted else { continue }
                    previews.append(row.thumbs[candidate.thumbPath] ?? image)
                    if previews.count == 4 { break }
                }
                best = score; result = .candidate(candidate, previews)
            }
        }
        return result
    }
}
