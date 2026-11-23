import SwiftUI
import UIKit

private struct ExperienceInfoPopoverAnchorKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

/// Chooses popover arrow edge from anchor position and measured content height.
enum ExperienceInfoPopoverPlacement {
    private static let anchorGap: CGFloat = 10
    private static let edgeMargin: CGFloat = 12

    /// `.top` arrow → popover below the ⓘ; `.bottom` arrow → popover above.
    static func preferredArrowEdge(anchorInScreen: CGRect, estimatedPopoverHeight: CGFloat) -> Edge {
        guard anchorInScreen.width > 0, anchorInScreen.height > 0 else {
            return .top
        }

        let (visibleTop, visibleBottom) = visibleVerticalLimitsInScreenSpace()
        let required = max(estimatedPopoverHeight, 44)

        let spaceBelow = max(0, visibleBottom - anchorInScreen.maxY - anchorGap)
        let spaceAbove = max(0, anchorInScreen.minY - visibleTop - anchorGap)

        let fitsBelow = spaceBelow >= required
        let fitsAbove = spaceAbove >= required

        if fitsBelow, !fitsAbove { return .top }
        if fitsAbove, !fitsBelow { return .bottom }
        if fitsBelow, fitsAbove {
            return spaceBelow >= spaceAbove ? .top : .bottom
        }
        return spaceBelow >= spaceAbove ? .top : .bottom
    }

    private static func visibleVerticalLimitsInScreenSpace() -> (top: CGFloat, bottom: CGFloat) {
        guard let window = keyWindow else {
            let bounds = UIScreen.main.bounds
            return (bounds.minY + edgeMargin, bounds.maxY - edgeMargin)
        }

        let bounds = window.bounds
        let safe = window.safeAreaInsets
        let top = bounds.minY + safe.top + edgeMargin

        var bottom = bounds.maxY - safe.bottom - edgeMargin
        if let tabBarTopY = tabBarTopEdgeY(in: window) {
            bottom = min(bottom, tabBarTopY - edgeMargin)
        }

        return (top, max(top + 1, bottom))
    }

    private static func tabBarTopEdgeY(in window: UIWindow) -> CGFloat? {
        guard let root = window.rootViewController?.view,
              let tabBar = findVisibleTabBar(in: root)
        else {
            return nil
        }
        let frame = tabBar.convert(tabBar.bounds, to: window)
        return frame.minY
    }

    private static func findVisibleTabBar(in root: UIView?) -> UITabBar? {
        guard let root else { return nil }
        if let tabBar = root as? UITabBar, !tabBar.isHidden, tabBar.alpha > 0.01, tabBar.window != nil {
            return tabBar
        }
        for subview in root.subviews {
            if let found = findVisibleTabBar(in: subview) {
                return found
            }
        }
        return nil
    }

    private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
    }
}

extension ExperienceInfoPopoverMetrics {
    static func estimatedContentHeight(title: String, bodyText: String, contentWidth: CGFloat) -> CGFloat {
        let horizontalPadding = ExperienceSpacing.md * 2
        let textWidth = max(1, contentWidth - horizontalPadding)

        let titleFont = UIFont.preferredFont(forTextStyle: .subheadline).emphasized()
        let bodyFont = UIFont.preferredFont(forTextStyle: .footnote)

        func measure(_ text: String, font: UIFont, lineSpacing: CGFloat) -> CGFloat {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = lineSpacing
            let rect = (text as NSString).boundingRect(
                with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: font, .paragraphStyle: paragraph],
                context: nil
            )
            return ceil(rect.height)
        }

        let titleHeight = measure(title, font: titleFont, lineSpacing: 0)
        let bodyHeight = measure(bodyText, font: bodyFont, lineSpacing: bodyLineSpacing)
        let verticalPadding = ExperienceSpacing.md * 2
        let interItem = ExperienceSpacing.sm
        let arrowAndShadowSlack: CGFloat = 16
        return titleHeight + interItem + bodyHeight + verticalPadding + arrowAndShadowSlack
    }
}

private extension UIFont {
    func emphasized() -> UIFont {
        let traits = UIFontDescriptor.SymbolicTraits.traitBold
        guard let descriptor = fontDescriptor.withSymbolicTraits(traits) else { return self }
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}

extension View {
    func experienceInfoPopoverAnchorTracking(_ anchor: Binding<CGRect>) -> some View {
        background {
            GeometryReader { geometry in
                Color.clear
                    .preference(
                        key: ExperienceInfoPopoverAnchorKey.self,
                        value: geometry.frame(in: .global)
                    )
            }
        }
        .onPreferenceChange(ExperienceInfoPopoverAnchorKey.self) { anchor.wrappedValue = $0 }
    }
}