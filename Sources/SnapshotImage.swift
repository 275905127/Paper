import SwiftUI
import ImageIO

/// 远程图沿用 AsyncImage，本地快照不经网络，按显示用途降采样。
struct SnapshotImage<Content: View>: View {
    let url: URL
    let maxPixels: Int
    @ViewBuilder var content: (AsyncImagePhase) -> Content
    @State private var phase: AsyncImagePhase = .empty

    var body: some View {
        if url.isFileURL {
            content(phase).task(id: url) {
                phase = .empty
                let local = url, size = maxPixels
                let decoded = await Task.detached(priority: .userInitiated) {
                    guard let source = CGImageSourceCreateWithURL(local as CFURL, nil) else { return nil as CGImage? }
                    let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: size, kCGImageSourceCreateThumbnailWithTransform: true]
                    return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
                }.value
                guard !Task.isCancelled else { return }
                if let decoded { phase = .success(Image(decorative: decoded, scale: 1)) }
                else { phase = .failure(CocoaError(.fileReadCorruptFile)) }
            }
        } else {
            AsyncImage(url: url, content: content)
        }
    }
}
