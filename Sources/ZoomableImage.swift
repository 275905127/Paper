import SwiftUI

/// 可缩放的图片容器：捏合缩放、双击切换、放大后拖动，带惯性回弹；
/// 未放大时向下拖动可关闭（跟手缩小、背景渐隐，松手超过阈值关闭，否则回弹）。
/// 只用公开 SwiftUI 手势，不涉及自绘。
struct ZoomableImage<Content: View>: View {
    /// 图片本身的宽高比，用来计算“填满屏幕”需要的倍数。
    let aspectRatio: CGFloat
    /// 下拉关闭进度（0...1），供外层同步背景和工具栏。
    @Binding var dismissProgress: CGFloat
    /// 松手后确认关闭。
    var onDismiss: () -> Void
    @ViewBuilder var content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scale: CGFloat = 1
    @State private var committedScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var committedOffset: CGSize = .zero
    @State private var pullDown: CGFloat = 0

    private let maxScale: CGFloat = 6
    private let dismissDistance: CGFloat = 140

    private var settle: Animation { reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.38, dampingFraction: 0.82) }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let fill = fillScale(in: size)
            // 下拉时整体随手指移动并略微缩小。
            let pullScale = 1 - min(pullDown / 900, 0.18)

            content()
                .scaleEffect(scale)
                .offset(offset)
                .scaleEffect(pullScale)
                .offset(y: pullDown)
                .frame(width: size.width, height: size.height)
                .contentShape(.rect)
                .gesture(magnify(in: size))
                .simultaneousGesture(pan(in: size))
                .onTapGesture(count: 2) {
                    withAnimation(settle) {
                        if scale > 1.01 {
                            reset()
                        } else {
                            let target = min(max(fill, 2), maxScale)
                            scale = target
                            committedScale = target
                        }
                    }
                }
                .accessibilityAction(named: "放大") {
                    withAnimation(settle) {
                        let target = min(max(committedScale * 1.6, 2), maxScale)
                        scale = target
                        committedScale = target
                    }
                }
                .accessibilityAction(named: "还原") { withAnimation(settle) { reset() } }
        }
    }

    // MARK: 手势

    private func magnify(in size: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                // 超出范围时带阻尼，松手后回弹，而不是硬截断。
                scale = rubber(committedScale * value.magnification, lower: 1, upper: maxScale)
            }
            .onEnded { _ in
                let target = clamp(scale, 1, maxScale)
                withAnimation(settle) {
                    scale = target
                    committedScale = target
                    if target <= 1.01 { reset() }
                    else { offset = limited(offset, in: size, scale: target); committedOffset = offset }
                }
            }
    }

    private func pan(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                if scale > 1.01 {
                    // 放大后拖动查看；超出边界带阻尼。
                    let proposed = CGSize(width: committedOffset.width + value.translation.width,
                                          height: committedOffset.height + value.translation.height)
                    offset = softLimited(proposed, in: size)
                } else if value.translation.height > 0,
                          abs(value.translation.height) > abs(value.translation.width) {
                    // 未放大：向下拖动关闭。
                    pullDown = value.translation.height
                    dismissProgress = min(pullDown / dismissDistance, 1)
                }
            }
            .onEnded { value in
                if scale > 1.01 {
                    // 带惯性滑行，再收回到边界内。
                    let projected = CGSize(
                        width: committedOffset.width + value.predictedEndTranslation.width,
                        height: committedOffset.height + value.predictedEndTranslation.height)
                    withAnimation(settle) {
                        offset = limited(projected, in: size, scale: scale)
                        committedOffset = offset
                    }
                } else if pullDown > 0 {
                    let shouldClose = pullDown > dismissDistance || value.predictedEndTranslation.height > 420
                    if shouldClose {
                        onDismiss()
                    }
                    withAnimation(settle) {
                        pullDown = 0
                        dismissProgress = 0
                    }
                }
            }
    }

    // MARK: 计算

    private func fillScale(in size: CGSize) -> CGFloat {
        guard size.width > 0, size.height > 0, aspectRatio > 0 else { return 2 }
        let containerRatio = size.width / size.height
        return aspectRatio > containerRatio ? aspectRatio / containerRatio : containerRatio / aspectRatio
    }

    private func limited(_ value: CGSize, in size: CGSize, scale: CGFloat) -> CGSize {
        let maxX = size.width * (scale - 1) / 2
        let maxY = size.height * (scale - 1) / 2
        return CGSize(width: clamp(value.width, -maxX, maxX),
                      height: clamp(value.height, -maxY, maxY))
    }

    /// 拖动中越界部分按 0.35 衰减，形成橡皮筋手感。
    private func softLimited(_ value: CGSize, in size: CGSize) -> CGSize {
        let maxX = size.width * (scale - 1) / 2
        let maxY = size.height * (scale - 1) / 2
        func soft(_ v: CGFloat, _ m: CGFloat) -> CGFloat {
            if v > m { return m + (v - m) * 0.35 }
            if v < -m { return -m + (v + m) * 0.35 }
            return v
        }
        return CGSize(width: soft(value.width, maxX), height: soft(value.height, maxY))
    }

    private func rubber(_ v: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        if v < lower { return lower - (lower - v) * 0.35 }
        if v > upper { return upper + (v - upper) * 0.35 }
        return v
    }

    private func reset() {
        scale = 1; committedScale = 1
        offset = .zero; committedOffset = .zero
    }

    private func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat { min(max(v, lo), hi) }
}
