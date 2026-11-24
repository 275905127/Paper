import Foundation
import WebKit

/// 在后台网页环境里取一张公开图片，只用于普通请求被站点人机验证拦截的图源。
/// 网页不会显示在界面上；取回的字节仍交给原生流程做格式、大小和像素校验。
@MainActor
enum WebImageFetcher {
    private static let limit = 16 * 1024 * 1024

    static func fetch(_ url: URL) async throws -> Data {
        let session = Session(url: url)
        return try await withTaskCancellationHandler {
            try await session.run()
        } onCancel: {
            Task { @MainActor in session.cancel() }
        }
    }

    @MainActor
    private final class Session: NSObject, WKNavigationDelegate {
        let url: URL
        let view: WKWebView
        var navigation: CheckedContinuation<Void, Error>?
        var cancelled = false

        init(url: URL) {
            self.url = url
            let config = WKWebViewConfiguration()
            // 不与系统浏览器共享 Cookie 和存储，也不留下持久数据。
            config.websiteDataStore = .nonPersistent()
            view = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: config)
            super.init()
            view.navigationDelegate = self
        }

        func cancel() {
            cancelled = true
            view.stopLoading()
            navigation?.resume(throwing: CancellationError())
            navigation = nil
        }

        func run() async throws -> Data {
            // 先载入站点同源页面以通过验证，再在页面内请求图片接口。
            guard var origin = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                throw SourceError.network("图片地址无效。")
            }
            origin.path = "/"
            origin.query = nil
            guard let home = origin.url else { throw SourceError.network("图片地址无效。") }
            try await load(home)
            try await waitForChallenge()
            return try await download()
        }

        private func load(_ page: URL) async throws {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                navigation = continuation
                view.load(URLRequest(url: page, timeoutInterval: 20))
            }
        }

        func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
            navigation?.resume()
            navigation = nil
        }

        func webView(_ webView: WKWebView, didFail _: WKNavigation!, withError error: Error) {
            navigation?.resume(throwing: error)
            navigation = nil
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError error: Error) {
            navigation?.resume(throwing: error)
            navigation = nil
        }

        /// 最多等 15 秒，直到页面不再是验证页。
        private func waitForChallenge() async throws {
            for _ in 0..<30 {
                try Task.checkCancellation()
                let title = (try? await view.evaluateJavaScript("document.title") as? String) ?? ""
                let challenged = title.localizedCaseInsensitiveContains("just a moment")
                    || title.localizedCaseInsensitiveContains("attention required")
                if !challenged { return }
                try await Task.sleep(for: .milliseconds(500))
            }
            throw SourceError.network("站点要求人工验证，无法在后台完成。")
        }

        private func download() async throws -> Data {
            let script = """
            const response = await fetch(url, { headers: { Accept: 'image/*' }, credentials: 'omit', cache: 'no-store' });
            const type = response.headers.get('content-type') || '';
            if (!response.ok) return { status: response.status };
            if (type.includes('text/html')) return { status: 200, html: true };
            const buffer = await response.arrayBuffer();
            if (buffer.byteLength > limit) return { status: 200, tooLarge: true };
            let binary = '';
            const bytes = new Uint8Array(buffer);
            for (let i = 0; i < bytes.length; i += 32768) {
                binary += String.fromCharCode.apply(null, bytes.subarray(i, i + 32768));
            }
            return { status: 200, data: btoa(binary) };
            """
            let raw = try await view.callAsyncJavaScript(
                script, arguments: ["url": url.absoluteString, "limit": WebImageFetcher.limit],
                in: nil, contentWorld: .defaultClient)
            guard let result = raw as? [String: Any], let status = result["status"] as? Int else {
                throw SourceError.network("网页环境没有返回图片。")
            }
            if result["tooLarge"] as? Bool == true { throw SourceError.network("图片超过 16 MiB 下载上限。") }
            if result["html"] as? Bool == true { throw SourceError.network("站点返回网页而非图片，可能需要人工验证。") }
            guard status == 200, let text = result["data"] as? String, let data = Data(base64Encoded: text) else {
                throw SourceError.network(status == 403 ? "站点仍拒绝访问（403）。" : "网页环境请求失败（\(status)）。")
            }
            return data
        }
    }
}
