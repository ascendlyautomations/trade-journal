import UIKit

/// UIKit tab-bar visibility — complements SwiftUI path depth gating.
enum CreateTabSelectionGatePolicy {
    static func allowsCreateShield(
        tabBar: UITabBar,
        tabBarController: UITabBarController?
    ) -> Bool {
        guard !tabBar.isHidden else { return false }
        guard tabBar.alpha > 0.01 else { return false }
        guard tabBar.window != nil else { return false }

        if let tabBarController {
            let barFrame = tabBar.convert(tabBar.bounds, to: tabBarController.view)
            if barFrame.minY >= tabBarController.view.bounds.maxY - 2 {
                return false
            }
            if barFrame.height < 8 {
                return false
            }
            if let nav = tabBarController.selectedViewController as? UINavigationController,
               nav.viewControllers.count > 1,
               nav.topViewController?.hidesBottomBarWhenPushed == true
            {
                return false
            }
        }

        let frameInWindow = tabBar.convert(tabBar.bounds, to: nil)
        guard frameInWindow.width > 1, frameInWindow.height > 1 else { return false }
        if let window = tabBar.window {
            let visible = frameInWindow.intersection(window.bounds)
            guard visible.height > 4, visible.width > 4 else { return false }
        }
        return true
    }
}
