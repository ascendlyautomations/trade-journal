import CoreGraphics
import Foundation
import UIKit

#if DEBUG
nonisolated enum FeedClipsLayoutDiagnostics {
    static func logPager(
        clipsCount: Int,
        viewportFrame: CGRect,
        viewportHeight: CGFloat,
        scrollViewBounds: CGRect,
        contentSizeHeight: CGFloat,
        currentIndex: Int,
        activeClipID: String?,
        pageCount: Int,
        pageHeight: CGFloat,
        pageOrigin: CGFloat,
        bottomOfPagerInWindow: CGFloat,
        topOfTabBarInWindow: CGFloat?
    ) {
        print("[ClipsPager] clipsCount=\(clipsCount)")
        print("[ClipsPager] viewportFrame=\(viewportFrame)")
        print("[ClipsPager] viewportHeight=\(viewportHeight)")
        print("[ClipsPager] scrollViewBounds=\(scrollViewBounds)")
        print("[ClipsPager] contentSizeHeight=\(contentSizeHeight)")
        print("[ClipsPager] currentIndex=\(currentIndex)")
        print("[ClipsPager] activeClipID=\(activeClipID ?? "nil")")
        print("[ClipsPager] pageCount=\(pageCount)")
        print("[ClipsPager] pageHeight=\(pageHeight)")
        print("[ClipsPager] pageOrigin=\(pageOrigin)")
        print("[ClipsPager] bottomOfPagerInWindow=\(bottomOfPagerInWindow)")
        if let topOfTabBarInWindow {
            print("[ClipsPager] topOfTabBarInWindow=\(topOfTabBarInWindow)")
        } else {
            print("[ClipsPager] topOfTabBarInWindow=nil")
        }
    }

    static func logClipPage(
        index: Int,
        containerFrame: CGRect,
        hostingViewFrame: CGRect,
        hostingViewBounds: CGRect,
        swiftUIRootSize: CGSize?,
        contentInsetTop: CGFloat,
        contentOffsetY: CGFloat
    ) {
        print("[ClipPage] index=\(index)")
        print("[ClipPage] containerFrame=\(containerFrame)")
        print("[ClipPage] hostingViewFrame=\(hostingViewFrame)")
        print("[ClipPage] hostingViewBounds=\(hostingViewBounds)")
        if let swiftUIRootSize {
            print("[ClipPage] swiftUIRootFrame=(0.0, 0.0, \(swiftUIRootSize.width), \(swiftUIRootSize.height))")
            print("[ClipPage] videoFrame=(0.0, 0.0, \(swiftUIRootSize.width), \(swiftUIRootSize.height))")
            print("[ClipPage] overlayFrame=(0.0, 0.0, \(swiftUIRootSize.width), \(swiftUIRootSize.height))")
        } else {
            print("[ClipPage] swiftUIRootFrame=nil")
        }
        print("[ClipPage] contentInsetTop=\(contentInsetTop)")
        print("[ClipPage] contentOffsetY=\(contentOffsetY)")
    }
}
#else
nonisolated enum FeedClipsLayoutDiagnostics {
    static func logPager(
        clipsCount: Int,
        viewportFrame: CGRect,
        viewportHeight: CGFloat,
        scrollViewBounds: CGRect,
        contentSizeHeight: CGFloat,
        currentIndex: Int,
        activeClipID: String?,
        pageCount: Int,
        pageHeight: CGFloat,
        pageOrigin: CGFloat,
        bottomOfPagerInWindow: CGFloat,
        topOfTabBarInWindow: CGFloat?
    ) {}

    static func logClipPage(
        index: Int,
        containerFrame: CGRect,
        hostingViewFrame: CGRect,
        hostingViewBounds: CGRect,
        swiftUIRootSize: CGSize?,
        contentInsetTop: CGFloat,
        contentOffsetY: CGFloat
    ) {}
}
#endif

extension UIView {
    func feedClipsNearestViewController() -> UIViewController? {
        var responder: UIResponder? = self
        while let current = responder {
            if let viewController = current as? UIViewController {
                return viewController
            }
            responder = current.next
        }
        return nil
    }

    func feedClipsBottomInWindow() -> CGFloat {
        convert(CGPoint(x: bounds.midX, y: bounds.maxY), to: nil).y
    }
}

extension UITabBar {
    static func feedClipsTopInWindow(from view: UIView) -> CGFloat? {
        guard let window = view.window else { return nil }
        return feedClipsTopInWindow(in: window)
    }

    static func feedClipsTopInWindow(in window: UIWindow) -> CGFloat? {
        guard let tabBar = findVisibleTabBar(in: window) else { return nil }
        return tabBar.convert(CGPoint(x: tabBar.bounds.midX, y: tabBar.bounds.minY), to: nil).y
    }

    static func feedClipsTopInKeyWindow() -> CGFloat? {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        else { return nil }
        return feedClipsTopInWindow(in: window)
    }

    private static func findVisibleTabBar(in view: UIView) -> UITabBar? {
        if let tabBar = view as? UITabBar, !tabBar.isHidden, tabBar.alpha > 0.01, tabBar.window != nil {
            return tabBar
        }
        for subview in view.subviews.reversed() {
            if let tabBar = findVisibleTabBar(in: subview) {
                return tabBar
            }
        }
        return nil
    }
}
