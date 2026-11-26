import UIKit

/// UIKit tab-bar button bounds for App Walkthrough (same introspection as Create tab shield).
enum ContextualTourTabBarIntrospection {
    static func globalFrame(for tab: TabIdentifier) -> CGRect? {
        guard let window = keyWindow, let tabBar = findVisibleTabBar(in: window) else { return nil }
        guard let control = tabBarControl(in: tabBar, title: tab.displayName) else { return nil }
        return control.convert(control.bounds, to: window)
    }

    private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
    }

    private static func findVisibleTabBar(in window: UIWindow) -> UITabBar? {
        func walk(_ view: UIView) -> UITabBar? {
            if let bar = view as? UITabBar, !bar.isHidden, bar.alpha > 0.01, bar.window != nil {
                return bar
            }
            for sub in view.subviews {
                if let found = walk(sub) { return found }
            }
            return nil
        }
        return walk(window)
    }

    /// The tab-bar button that owns the label, not the label itself.
    static func tabBarControl(in tabBar: UITabBar, title: String) -> UIView? {
        if let button = tabBarButton(in: tabBar, title: title) {
            return button
        }
        guard var control = largestView(in: tabBar, accessibilityLabel: title) else { return nil }
        while let parent = control.superview,
              parent !== tabBar,
              parent.isDescendant(of: tabBar),
              parent.bounds.width < tabBar.bounds.width * 0.45
        {
            control = parent
        }
        return control
    }

    private static func tabBarButton(in root: UIView, title: String) -> UIView? {
        let selector = NSSelectorFromString("tabBarItem")
        var match: UIView?
        func walk(_ view: UIView) {
            if view.responds(to: selector),
               let item = view.perform(selector)?.takeUnretainedValue() as? UITabBarItem,
               item.title == title
            {
                let area = view.bounds.width * view.bounds.height
                let best = (match?.bounds.width ?? 0) * (match?.bounds.height ?? 0)
                if area >= best { match = view }
            }
            view.subviews.forEach(walk)
        }
        walk(root)
        return match
    }

    private static func largestView(in root: UIView, accessibilityLabel: String) -> UIView? {
        var match: UIView?
        func walk(_ view: UIView) {
            if view.accessibilityLabel == accessibilityLabel {
                let area = view.bounds.width * view.bounds.height
                let best = (match?.bounds.width ?? 0) * (match?.bounds.height ?? 0)
                if area > best { match = view }
            }
            view.subviews.forEach(walk)
        }
        walk(root)
        return match
    }
}