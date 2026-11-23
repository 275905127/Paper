import Foundation
import ImageIO
import Photos

enum SaveError: LocalizedError {
    case denied
    case download
    case decode

    var errorDescription: String? {
        switch self {
        case .denied: "没有相册写入权限，请在系统设置中允许“纸间”添加照片。"
        case .download: "原图下载失败，请检查网络后重试。"
        case .decode: "图片数据无法识别。"
        }
    }
}

/// 把原图下载并保存到系统相册。数据层，不涉及界面。
enum PhotoSaver {
    static func save(_ wallpaper: Wallpaper) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw SaveError.denied }

        var request = URLRequest(url: wallpaper.path)
        request.timeoutInterval = 60
        let data: Data
        do {
            let (body, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw SaveError.download
            }
            data = body
        } catch is SaveError {
            throw SaveError.download
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw SaveError.download
        }

        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(imageSource) > 0
        else { throw SaveError.decode }

        try await PHPhotoLibrary.shared().performChanges {
            let options = PHAssetResourceCreationOptions()
            options.uniformTypeIdentifier = wallpaper.fileType == "image/png" ? "public.png" : "public.jpeg"
            PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: options)
        }
    }
}
