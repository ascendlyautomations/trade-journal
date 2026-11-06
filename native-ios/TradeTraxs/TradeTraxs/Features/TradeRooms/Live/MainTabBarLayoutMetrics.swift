import SwiftUI
import UIKit

/// Measured height of the visible main tab bar (for placing session chrome directly above it).
@Observable
@MainActor
final class MainTabBarLayoutMetrics {
    static let shared = MainTabBarLayoutMetrics()

    /// Distance from the window bottom to the top edge of the tab bar (tab bar + home indicator).
    private(set) var tabBarTopInsetFromBottom: CGFloat = 83

    func refresh() {
        if let inset = Self.measureTabBarTopInsetFromWindowBottom() {
            if abs(tabBarTopInsetFromBottom - inset) > 0.5 {
                tabBarTopInsetFromBottom = inset
            }
            return
        }
        if let fallback = Self.fallbackTabBarTopInsetFromWindowBottom() {
            if abs(tabBarTopInsetFromBottom - fallback) > 0.5 {
                tabBarTopInsetFromBottom = fallback
            }
        }
    }

    /// When the tab bar is momentarily hidden during transitions, keep chrome above the usual tab slot.
    private static func fallbackTabBarTopInsetFromWindowBottom() -> CGFloat? {
        guard let window = keyWindow else { return nil }
        let safeBottom = window.safeAreaInsets.bottom
        let tabBarHeight: CGFloat = 49
        return tabBarHeight + safeBottom
    }

    private static func measureTabBarTopInsetFromWindowBottom() -> CGFloat? {
        guard let window = keyWindow else { return nil }
        guard let tabBar = findVisibleTabBar(in: window) else { return nil }
        let frameInWindow = tabBar.convert(tabBar.bounds, to: window)
        return max(0, window.bounds.maxY - frameInWindow.minY)
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
