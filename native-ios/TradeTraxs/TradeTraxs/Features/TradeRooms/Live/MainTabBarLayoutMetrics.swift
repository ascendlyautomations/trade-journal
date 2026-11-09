import SwiftUI
import UIKit

/// Measured height of the visible main tab bar (for placing session chrome directly above it).
@Observable
@MainActor
final class MainTabBarLayoutMetrics {
    static let shared = MainTabBarLayoutMetrics()

    /// Distance from the window bottom to the top edge of the tab bar (tab bar + home indicator).
    private(set) var tabBarTopInsetFromBottom: CGFloat = 83
    /// UITabBar frame height (includes home-indicator padding in the bar background).
    private(set) var tabBarFrameHeight: CGFloat = 49
    /// Interactive tab strip only — use for session chrome clearance (not full bar frame).
    private(set) var tabBarStripHeight: CGFloat = 49

    func refresh() {
        if let measured = Self.measureTabBar(in: Self.keyWindow) {
            if abs(tabBarTopInsetFromBottom - measured.topInsetFromWindowBottom) > 0.5 {
                tabBarTopInsetFromBottom = measured.topInsetFromWindowBottom
            }
            if abs(tabBarFrameHeight - measured.frameHeight) > 0.5 {
                tabBarFrameHeight = measured.frameHeight
            }
            let strip = Self.tabBarStripHeight(
                topInsetFromWindowBottom: measured.topInsetFromWindowBottom,
                frameHeight: measured.frameHeight,
                safeAreaBottom: measured.safeAreaBottom
            )
            if abs(tabBarStripHeight - strip) > 0.5 {
                tabBarStripHeight = strip
            }
            return
        }
        if let fallback = Self.fallbackTabBarTopInsetFromWindowBottom() {
            if abs(tabBarTopInsetFromBottom - fallback) > 0.5 {
                tabBarTopInsetFromBottom = fallback
            }
            let fallbackBarHeight: CGFloat = 49
            if abs(tabBarFrameHeight - fallbackBarHeight) > 0.5 {
                tabBarFrameHeight = fallbackBarHeight
            }
            if abs(tabBarStripHeight - fallbackBarHeight) > 0.5 {
                tabBarStripHeight = fallbackBarHeight
            }
        }
    }

    /// Strip height for spacing above the tab bar — never count home-indicator area twice.
    private static func tabBarStripHeight(
        topInsetFromWindowBottom: CGFloat,
        frameHeight: CGFloat,
        safeAreaBottom: CGFloat
    ) -> CGFloat {
        let fromTopInset = max(0, topInsetFromWindowBottom - safeAreaBottom)
        if fromTopInset > 0.5 {
            return fromTopInset
        }
        return max(0, frameHeight - safeAreaBottom)
    }

    /// When the tab bar is momentarily hidden during transitions, keep chrome above the usual tab slot.
    private static func fallbackTabBarTopInsetFromWindowBottom() -> CGFloat? {
        guard let window = keyWindow else { return nil }
        let safeBottom = window.safeAreaInsets.bottom
        let tabBarHeight: CGFloat = 49
        return tabBarHeight + safeBottom
    }

    private static func measureTabBar(in window: UIWindow?) -> (
        topInsetFromWindowBottom: CGFloat,
        frameHeight: CGFloat,
        safeAreaBottom: CGFloat
    )? {
        guard let window else { return nil }
        guard let tabBar = findVisibleTabBar(in: window) else { return nil }
        let frameInWindow = tabBar.convert(tabBar.bounds, to: window)
        return (
            topInsetFromWindowBottom: max(0, window.bounds.maxY - frameInWindow.minY),
            frameHeight: max(0, frameInWindow.height),
            safeAreaBottom: window.safeAreaInsets.bottom
        )
    }

    private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
    }

    private static func findVisibleTabBar(in root: UIView) -> UITabBar? {
        if let tabBar = root as? UITabBar, !tabBar.isHidden, tabBar.alpha > 0.01, tabBar.window != nil {
            return tabBar
        }
        for subview in root.subviews.reversed() {
            if let tabBar = findVisibleTabBar(in: subview) {
                return tabBar
            }
        }
        return nil
    }
}

/// Keeps ``MainTabBarLayoutMetrics`` updated while the tab shell is visible.
struct MainTabBarLayoutMetricsProbe: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            MainTabBarLayoutMetrics.shared.refresh()
        }
    }
}
