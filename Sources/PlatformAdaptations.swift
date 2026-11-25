import SwiftUI

extension View {
    /// iOS 27 起滚动时收起导航栏，浏览壁纸时让出更多画面；
    /// 26 上保持系统默认，不做任何替代。
    @ViewBuilder
    func minimizingNavigationBarOnScroll() -> some View {
        if #available(iOS 27.0, *) {
            toolbarMinimizationBehavior(.onScrollDown, for: .navigationBar)
        } else {
            self
        }
    }
}
