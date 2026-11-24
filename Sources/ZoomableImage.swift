import SwiftUI

/// 可缩放的图片容器：捏合缩放、双击在“适应屏幕 / 填满屏幕”间切换、放大后拖动查看。
/// 只用公开的 SwiftUI 手势（MagnifyGesture / DragGesture / 双击），不涉及自绘。
struct ZoomableImage<Content: View>: View {
    /// 图片本身的宽高比，用来计算“填满屏幕”需要的倍数。
    let aspectRatio: CGFloat
    @ViewBuilder var content: () -> Content

    @State private var scale: CGFloat = 1
    @State private var committedScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var committedOffset: CGSize = .zero

    private let maxScale: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let fill = fillScale(in: size)

            content()
                .scaleEffect(scale)
                .offset(offset)
                .frame(width: size.width, height: size.height)
                .contentShape(.rect)
                .gesture(magnify(in: size))
                .simultaneousGesture(pan(in: size))
                .onTapGesture(count: 2) {
                    // 已放大则复位；否则放大到“填满屏幕”（至少 2 倍，避免方图几乎不变）
                    withAnimation(.smooth) {
                        if scale > 1.01 {
                            reset()
                        } else {
                            let target = min(max(fill, 2), maxScale)
                            scale = target
                            committedScale = target
                        }
                    }
                }
        }
    }

    // MARK: 手势

    private func magnify(in size: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = clamp(committedScale * value.magnification, 1, maxScale)
            }
            .onEnded { _ in
                committedScale = scale
                if scale <= 1.01 { withAnimation(.smooth) { reset() } }
                else { offset = limited(offset, in: size); committedOffset = offset }
            }
    }

    private func pan(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                // 未放大时不拖动，把手势让给导航返回等系统行为。
                guard scale > 1.01 else { return }
                offset = limited(
                    CGSize(width: committedOffset.width + value.translation.width,
                           height: committedOffset.height + value.translation.height),
                    in: size
                )
            }
            .onEnded { _ in
                committedOffset = offset
            }
    }

    // MARK: 计算

    /// 让图片刚好填满容器短边所需的倍数。
    private func fillScale(in size: CGSize) -> CGFloat {
        guard size.width > 0, size.height > 0, aspectRatio > 0 else { return 2 }
        let containerRatio = size.width / size.height
        // 图片在容器里“适应”显示时的比例关系：
        // 图更宽 → 适应后宽顶满，填满需放大 containerRatio 之外的比值
        return aspectRatio > containerRatio ? aspectRatio / containerRatio : containerRatio / aspectRatio
    }

    /// 限制拖动范围，避免把图拖出屏幕。
    private func limited(_ value: CGSize, in size: CGSize) -> CGSize {
        let maxX = size.width * (scale - 1) / 2
        let maxY = size.height * (scale - 1) / 2
        return CGSize(width: clamp(value.width, -maxX, maxX),
                      height: clamp(value.height, -maxY, maxY))
    }

    private func reset() {
        scale = 1; committedScale = 1
        offset = .zero; committedOffset = .zero
    }

    private func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat { min(max(v, lo), hi) }
}
