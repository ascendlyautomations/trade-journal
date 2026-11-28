import UIKit

/// UIKit tab-bar button bounds for App Walkthrough (SwiftUI tab bars may not expose titled subviews).
enum ContextualTourTabBarIntrospection {
    /// Must match ``MainTabShellView`` tab order.
    static let shellTabOrder: [TabIdentifier] = [.home, .feed, .create, .messages, .profile]

    private static var lastTraceAt: [TabIdentifier: CFAbsoluteTime] = [:]

    enum MeasurementMethod: String {
        case uiKitTabBarItemSubview = "uiKit-tab-bar-item-subview"
        case accessibilityLabel = "accessibility-label"
        case tabBarItemsTitleIndex = "tab-bar-items-title-index"
        case tabBarItemsOrdinalIndex = "tab-bar-items-ordinal-index"
        case layoutPlatterSegments = "layout-platter-segments"
        case geometryEqualColumns = "geometry-equal-columns"
    }

    private struct ResolvedFrame {
        var frame: CGRect
        var method: MeasurementMethod
    }

    static func globalFrame(for tab: TabIdentifier, trace: Bool = false) -> CGRect? {
        let resolved = resolveGlobalFrame(for: tab)
        let now = CFAbsoluteTimeGetCurrent()
        let mayTrace = trace && (now - (lastTraceAt[tab] ?? 0) >= 0.75)
        if mayTrace {
            lastTraceAt[tab] = now
            if let resolved {
                ContextualTourDebug.logTourTrace(
                    "tab frame resolved tab=\(tab.displayName) method=\(resolved.method.rawValue) frame=\(resolved.frame)"
                )
            } else if let window = keyWindow,
                      let tabBar = findVisibleTabBar(in: window)
            {
                ContextualTourDebug.logTourTrace(
                    "tab frame unresolved tab=\(tab.displayName) barFrame=\(tabBar.convert(tabBar.bounds, to: window))"
                )
            } else {
                ContextualTourDebug.logTourTrace("tab frame unresolved tab=\(tab.displayName) reason=no-tab-bar")
            }
        }
        return resolved?.frame
    }

    private static func resolveGlobalFrame(for tab: TabIdentifier) -> ResolvedFrame? {
        guard let window = keyWindow,
              let tabBar = findVisibleTabBar(in: window),
              let ordinal = shellTabOrder.firstIndex(of: tab),
              let frame = geometrySlot(
                  in: tabBar,
                  window: window,
                  index: ordinal,
                  count: shellTabOrder.count
              )
        else {
            return nil
        }
        return ResolvedFrame(frame: frame, method: .geometryEqualColumns)
    }

    // MARK: - Geometry

    /// Interactive tab strip in window coordinates (excludes home-indicator padding when embedded in the bar).
    private static func interactiveStripRect(in tabBar: UITabBar, window: UIWindow) -> CGRect {
        let barInWindow = tabBar.convert(tabBar.bounds, to: window)
        let safeBottom = window.safeAreaInsets.bottom
        let stripHeight = max(44, min(49, barInWindow.height - safeBottom))
        if barInWindow.height - stripHeight > 1 {
            return CGRect(
                x: barInWindow.minX,
                y: barInWindow.minY,
                width: barInWindow.width,
                height: stripHeight
            )
        }
        return barInWindow
    }

    private static func geometrySlot(
        in tabBar: UITabBar,
        window: UIWindow,
        index: Int,
        count: Int
    ) -> CGRect? {
        guard count > 0, index >= 0, index < count else { return nil }
        let strip = interactiveStripRect(in: tabBar, window: window)
        let slotWidth = strip.width / CGFloat(count)
        guard slotWidth > 1 else { return nil }
        let horizontalInset = ExperienceSpacing.xs
        let verticalInset = ExperienceSpacing.xxs
        let slot = CGRect(
            x: strip.minX + slotWidth * CGFloat(index) + horizontalInset,
            y: strip.minY + verticalInset,
            width: max(1, slotWidth - horizontalInset * 2),
            height: max(1, strip.height - verticalInset * 2)
        )
        guard ContextualTourGeometry.isUsable(slot) else { return nil }
        return slot
    }

    // MARK: - UIKit introspection

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
            for sub in view.subviews.reversed() {
                if let found = walk(sub) { return found }
            }
            return nil
        }
        return walk(window)
    }

    private static func tabBarItemSubview(in tabBar: UITabBar, title: String) -> UIView? {
        if let button = tabBarButton(in: tabBar, title: title) {
            return normalizedTabControl(button, tabBar: tabBar)
        }
        return nil
    }

    private static func accessibilityMatch(in tabBar: UITabBar, label: String) -> UIView? {
        guard let control = largestView(in: tabBar, accessibilityLabel: label) else { return nil }
        return normalizedTabControl(control, tabBar: tabBar)
    }

    private static func normalizedTabControl(_ control: UIView, tabBar: UITabBar) -> UIView {
        var candidate = control
        while let parent = candidate.superview,
              parent !== tabBar,
              parent.isDescendant(of: tabBar),
              parent.bounds.width < tabBar.bounds.width * 0.45
        {
            candidate = parent
        }
        return candidate
    }

    /// Horizontally ordered tab-sized subviews inside the bar (SwiftUI platter layout).
    private static func layoutPlatterSegments(in tabBar: UITabBar, expectedCount: Int) -> [UIView]? {
        var leafCandidates: [UIView] = []
        func walk(_ view: UIView) {
            let frameInBar = view.convert(view.bounds, to: tabBar)
            let widthRatio = frameInBar.width / max(1, tabBar.bounds.width)
            let heightRatio = frameInBar.height / max(1, tabBar.bounds.height)
            let isTabSized = widthRatio >= 0.1 && widthRatio <= 0.32
                && heightRatio >= 0.35
                && frameInBar.height > 20
            if isTabSized, view.subviews.isEmpty || view is UIControl {
                leafCandidates.append(view)
            }
            view.subviews.forEach(walk)
        }
        walk(tabBar)

        let sorted = leafCandidates.sorted {
            $0.convert($0.bounds, to: tabBar).minX < $1.convert($1.bounds, to: tabBar).minX
        }

        var deduped: [UIView] = []
        for view in sorted {
            let frame = view.convert(view.bounds, to: tabBar)
            if let last = deduped.last {
                let lastFrame = last.convert(last.bounds, to: tabBar)
                if abs(lastFrame.midX - frame.midX) < 4 { continue }
            }
            deduped.append(view)
        }

        guard deduped.count >= expectedCount else { return nil }
        if deduped.count > expectedCount {
            return Array(deduped.prefix(expectedCount))
        }
        return deduped
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