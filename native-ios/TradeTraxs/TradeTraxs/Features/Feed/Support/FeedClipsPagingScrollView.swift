import SwiftUI
import UIKit

/// Authoritative vertical Clips pager — page height is always the SwiftUI-assigned container height.
struct FeedClipsVerticalPager: UIViewRepresentable {
    let pageCount: Int
    @Binding var activeIndex: Int
    let clipIDs: [String]
    var isScrollEnabled: Bool = true
    let makePage: (Int) -> AnyView
    var onPageSettled: ((Int, Int) -> Void)?

    func makeUIView(context: Context) -> FeedClipsPagingContainerView {
        let view = FeedClipsPagingContainerView()
        view.scrollView.delegate = context.coordinator
        context.coordinator.containerView = view
        return view
    }

    func updateUIView(_ uiView: FeedClipsPagingContainerView, context: Context) {
        context.coordinator.parent = self
        uiView.apply(
            pageCount: pageCount,
            activeIndex: activeIndex,
            clipIDs: clipIDs,
            isScrollEnabled: isScrollEnabled,
            makePage: makePage,
            onPageSettled: onPageSettled,
            coordinator: context.coordinator
        )
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: FeedClipsPagingContainerView, context: Context) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height,
              width.isFinite, height.isFinite, width > 0, height > 0
        else { return nil }
        return CGSize(width: width, height: height)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var parent: FeedClipsVerticalPager
        weak var containerView: FeedClipsPagingContainerView?

        init(parent: FeedClipsVerticalPager) {
            self.parent = parent
        }

        func reportIndexChange(_ index: Int) {
            guard parent.activeIndex != index else { return }
            parent.activeIndex = index
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            containerView?.userDidBeginDragging()
        }

        func scrollViewWillEndDragging(
            _ scrollView: UIScrollView,
            withVelocity velocity: CGPoint,
            targetContentOffset: UnsafeMutablePointer<CGPoint>
        ) {
            containerView?.userWillEndDragging(
                velocityY: velocity.y,
                targetContentOffset: targetContentOffset
            )
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            containerView?.handleScroll()
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            containerView?.finishScrollInteraction(decelerated: true)
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            guard !decelerate else { return }
            containerView?.finishScrollInteraction(decelerated: false)
        }

        func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
            containerView?.finishProgrammaticScrollAnimation()
        }
    }
}

// MARK: - UIKit container

final class FeedClipsPagingContainerView: UIView {
    let scrollView = UIScrollView()

    private var pageHosts: [Int: UIHostingController<AnyView>] = [:]
    private weak var hostingParentViewController: UIViewController?

    private var pageCount = 0
    private var activeIndex = 0
    private var clipIDs: [String] = []
    private var lastAppliedClipIDs: [String] = []
    private var makePage: ((Int) -> AnyView)?
    private var onPageSettled: ((Int, Int) -> Void)?
    private weak var coordinator: FeedClipsVerticalPager.Coordinator?
    private var isProgrammaticScroll = false
    private var isUserInteracting = false
    private var lastViewportSize: CGSize = .zero
    private var hostedClipIDs: [Int: String] = [:]
    private var lastScrollOffsetY: CGFloat = 0
    private var lastScrollDirection: Int = 1

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        backgroundColor = .clear
        insetsLayoutMarginsFromSafeArea = false

        scrollView.isPagingEnabled = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.automaticallyAdjustsScrollIndicatorInsets = false
        scrollView.contentInset = .zero
        scrollView.scrollIndicatorInsets = .zero
        scrollView.clipsToBounds = true
        scrollView.backgroundColor = .clear
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.decelerationRate = .fast
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            hostingParentViewController = feedClipsNearestViewController()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let viewportChanged = lastViewportSize != bounds.size
        if viewportChanged {
            lastViewportSize = bounds.size
        }

        // During an active user drag/deceleration, UIKit owns contentOffset — do not relayout/correct.
        if isUserInteracting, !viewportChanged {
            return
        }

        relayoutAllPages(preserveScrollPosition: !viewportChanged)
        if viewportChanged, pageCount > 0 {
            scrollToPage(activeIndex, animated: false, reason: "viewportResize")
        } else if !isUserInteracting {
            normalizeScrollOffsetToActiveIndex(reason: "layoutSubviews")
        }
    }

    func apply(
        pageCount: Int,
        activeIndex: Int,
        clipIDs: [String],
        isScrollEnabled: Bool,
        makePage: @escaping (Int) -> AnyView,
        onPageSettled: ((Int, Int) -> Void)?,
        coordinator: FeedClipsVerticalPager.Coordinator
    ) {
        let previousCount = self.pageCount
        let dataChanged = previousCount != max(0, pageCount) || clipIDs != lastAppliedClipIDs

        self.pageCount = max(0, pageCount)
        self.clipIDs = clipIDs
        self.lastAppliedClipIDs = clipIDs
        self.makePage = makePage
        self.onPageSettled = onPageSettled
        self.coordinator = coordinator
        scrollView.isScrollEnabled = isScrollEnabled
        scrollView.alwaysBounceVertical = pageCount > 1

        if previousCount != pageCount {
            purgeHostsOutsideValidRange()
        }

        let clamped = clampedIndex(activeIndex)
        let indexChanged = self.activeIndex != clamped
        self.activeIndex = clamped

        guard bounds.height > 0 else { return }

        // SwiftUI updates during a user swipe must not re-scroll or relayout the pager.
        if isUserInteracting {
            return
        }

        if dataChanged {
            relayoutAllPages(preserveScrollPosition: !indexChanged)
        }

        if indexChanged {
            scrollToPage(clamped, animated: false, reason: "externalIndexChange")
        } else if dataChanged {
            normalizeScrollOffsetToActiveIndex(reason: "applyDataChanged")
        }
    }

    func userDidBeginDragging() {
        isUserInteracting = true
        ClipsPagerScrollProbe.dragBegin(
            index: activeIndex,
            offset: scrollView.contentOffset.y,
            viewportHeight: bounds.height
        )
    }

    func userWillEndDragging(
        velocityY: CGFloat,
        targetContentOffset: UnsafeMutablePointer<CGPoint>
    ) {
        let pageHeight = bounds.height
        guard pageHeight > 0, pageCount > 0 else { return }
        let targetIndex = clampedIndex(Int(round(targetContentOffset.pointee.y / pageHeight)))
        ClipsPagerScrollProbe.willEndDragging(
            velocityY: velocityY,
            currentOffset: scrollView.contentOffset.y,
            targetOffset: targetContentOffset.pointee.y,
            targetIndex: targetIndex,
            viewportHeight: pageHeight
        )
    }

    func handleScroll() {
        guard !isProgrammaticScroll else { return }
        let currentOffset = scrollView.contentOffset.y
        if currentOffset != lastScrollOffsetY {
            lastScrollDirection = currentOffset >= lastScrollOffsetY ? 1 : -1
            lastScrollOffsetY = currentOffset
        }
    }

    func finishScrollInteraction(decelerated: Bool) {
        isProgrammaticScroll = false
        settleToNearestPage(decelerated: decelerated)
        isUserInteracting = false
    }

    func finishProgrammaticScrollAnimation() {
        isProgrammaticScroll = false
        reportMetrics(settledIndex: currentPageIndex())
    }

    // MARK: Layout

    private func relayoutAllPages(preserveScrollPosition: Bool) {
        guard let makePage else { return }

        let viewport = bounds.size
        guard viewport.height > 0, viewport.width > 0 else { return }

        let preservedOffset = scrollView.contentOffset

        if pageCount > 0 {
            scrollView.contentSize = CGSize(
                width: viewport.width,
                height: viewport.height * CGFloat(pageCount)
            )

            for index in 0..<pageCount {
                let originY = CGFloat(index) * viewport.height
                let frame = CGRect(x: 0, y: originY, width: viewport.width, height: viewport.height)
                let clipID = clipIDs.indices.contains(index) ? clipIDs[index] : ""
                let host = hostingController(for: index, makePage: makePage)
                attachHostIfNeeded(host)
                configureHostedPage(host)
                host.view.frame = frame
                host.view.clipsToBounds = true
                if hostedClipIDs[index] != clipID {
                    host.rootView = makePage(index)
                    hostedClipIDs[index] = clipID
                }
                host.view.setNeedsLayout()
                host.view.layoutIfNeeded()

                if index == activeIndex || index == activeIndex + 1 || index == activeIndex - 1 {
                    logClipPage(index: index, containerFrame: frame, host: host)
                }
            }
        } else {
            scrollView.contentSize = .zero
        }

        purgeHostsOutsideValidRange()

        scrollView.contentInset = .zero
        scrollView.scrollIndicatorInsets = .zero

        if preserveScrollPosition, pageCount > 0 {
            let pageHeight = viewport.height
            let maxY = max(0, scrollView.contentSize.height - pageHeight)
            let clampedY = min(max(0, preservedOffset.y), maxY)
            if abs(scrollView.contentOffset.y - clampedY) > 0.5 {
                scrollView.contentOffset = CGPoint(x: 0, y: clampedY)
            }
        } else if !isUserInteracting {
            normalizeScrollOffsetToActiveIndex(reason: "relayoutAllPages")
        }

        reportMetrics(settledIndex: currentPageIndex())
    }

    private func configureHostedPage(_ host: UIHostingController<AnyView>) {
        host.view.backgroundColor = .clear
        host.view.clipsToBounds = true
        host.view.insetsLayoutMarginsFromSafeArea = false
        if #available(iOS 16.0, *) {
            host.sizingOptions = []
        }
        if #available(iOS 16.4, *) {
            host.safeAreaRegions = []
        }
    }

    private func normalizeScrollOffsetToActiveIndex(reason: String) {
        guard pageCount > 0, bounds.height > 0, !isUserInteracting else { return }
        scrollView.contentInset = .zero
        scrollView.scrollIndicatorInsets = .zero
        let expectedY = CGFloat(clampedIndex(activeIndex)) * bounds.height
        guard abs(scrollView.contentOffset.y - expectedY) > 0.5 else { return }
        programmaticallyScroll(toOffsetY: expectedY, animated: false, reason: reason)
    }

    private func logClipPage(index: Int, containerFrame: CGRect, host: UIHostingController<AnyView>) {
        #if DEBUG
        let swiftUISize = FeedClipsPageMetricsStore.sizes[index]
        #else
        let swiftUISize: CGSize? = nil
        #endif
        FeedClipsLayoutDiagnostics.logClipPage(
            index: index,
            containerFrame: containerFrame,
            hostingViewFrame: host.view.frame,
            hostingViewBounds: host.view.bounds,
            swiftUIRootSize: swiftUISize,
            contentInsetTop: scrollView.contentInset.top,
            contentOffsetY: scrollView.contentOffset.y
        )
    }

    private func attachHostIfNeeded(_ host: UIHostingController<AnyView>) {
        guard host.view.superview == nil else { return }

        if let hostingParentViewController {
            if host.parent !== hostingParentViewController {
                hostingParentViewController.addChild(host)
                scrollView.addSubview(host.view)
                host.didMove(toParent: hostingParentViewController)
            }
        } else {
            scrollView.addSubview(host.view)
        }
    }

    private func detachHost(_ host: UIHostingController<AnyView>) {
        if host.parent != nil {
            host.willMove(toParent: nil)
            host.view.removeFromSuperview()
            host.removeFromParent()
        } else {
            host.view.removeFromSuperview()
        }
    }

    private func hostingController(
        for index: Int,
        makePage: @escaping (Int) -> AnyView
    ) -> UIHostingController<AnyView> {
        if let existing = pageHosts[index] {
            return existing
        }

        let host = UIHostingController(rootView: makePage(index))
        configureHostedPage(host)
        pageHosts[index] = host
        return host
    }

    private func purgeHostsOutsideValidRange() {
        for (index, host) in pageHosts where index >= pageCount {
            detachHost(host)
            pageHosts.removeValue(forKey: index)
            hostedClipIDs.removeValue(forKey: index)
        }
    }

    // MARK: Scrolling

    private func scrollToPage(_ index: Int, animated: Bool, reason: String) {
        let clamped = clampedIndex(index)
        let from = activeIndex
        activeIndex = clamped
        let pageHeight = bounds.height
        guard pageHeight > 0, pageCount > 0 else { return }

        let targetY = CGFloat(clamped) * pageHeight
        guard abs(scrollView.contentOffset.y - targetY) > 0.5 else {
            reportMetrics(settledIndex: clamped)
            return
        }

        ClipsPagerScrollProbe.programmaticScroll(
            from: from,
            to: clamped,
            animated: animated,
            reason: reason
        )
        programmaticallyScroll(toOffsetY: targetY, animated: animated, reason: reason)
        reportMetrics(settledIndex: clamped)
    }

    private func programmaticallyScroll(toOffsetY targetY: CGFloat, animated: Bool, reason: String) {
        isProgrammaticScroll = true
        scrollView.setContentOffset(CGPoint(x: 0, y: targetY), animated: animated)
        if !animated {
            isProgrammaticScroll = false
        }
        _ = reason
    }

    private func settleToNearestPage(decelerated: Bool) {
        let pageHeight = bounds.height
        guard pageHeight > 0, pageCount > 0 else { return }

        let index = currentPageIndex(pageHeight: pageHeight)
        let clamped = clampedIndex(index)
        let expectedY = CGFloat(clamped) * pageHeight

        ClipsPagerScrollProbe.decelerationEnded(
            offset: scrollView.contentOffset.y,
            resolvedIndex: clamped,
            viewportHeight: pageHeight
        )

        // `isPagingEnabled` already snaps — only correct genuine drift without a second animation.
        if abs(scrollView.contentOffset.y - expectedY) > 1.0 {
            ClipsPagerScrollProbe.programmaticScroll(
                from: activeIndex,
                to: clamped,
                animated: false,
                reason: decelerated ? "postDecelerationDriftCorrection" : "postDragDriftCorrection"
            )
            programmaticallyScroll(toOffsetY: expectedY, animated: false, reason: "driftCorrection")
        }

        commitPageChange(clamped, scrollDirection: lastScrollDirection)
    }

    private func commitPageChange(_ index: Int, scrollDirection: Int = 1) {
        let clamped = clampedIndex(index)
        let changed = activeIndex != clamped
        activeIndex = clamped
        coordinator?.reportIndexChange(clamped)
        reportMetrics(settledIndex: clamped)

        if changed {
            onPageSettled?(clamped, scrollDirection)
        }
    }

    private func currentPageIndex(pageHeight: CGFloat? = nil) -> Int {
        let height = pageHeight ?? bounds.height
        guard height > 0, pageCount > 0 else { return 0 }
        return clampedIndex(Int(round(scrollView.contentOffset.y / height)))
    }

    private func clampedIndex(_ index: Int) -> Int {
        guard pageCount > 0 else { return 0 }
        return min(max(0, index), pageCount - 1)
    }

    private func clipID(for index: Int) -> String? {
        guard clipIDs.indices.contains(index) else { return nil }
        return clipIDs[index]
    }

    private func reportMetrics(settledIndex: Int) {
        let viewportHeight = bounds.height
        guard viewportHeight > 0 else { return }

        let pageHeight = viewportHeight
        let pageOrigin = scrollView.contentOffset.y
        let clipID = clipID(for: settledIndex)

        FeedClipsLayoutDiagnostics.logPager(
            clipsCount: pageCount,
            viewportFrame: bounds,
            viewportHeight: viewportHeight,
            scrollViewBounds: scrollView.bounds,
            contentSizeHeight: scrollView.contentSize.height,
            currentIndex: settledIndex,
            activeClipID: clipID,
            pageCount: pageCount,
            pageHeight: pageHeight,
            pageOrigin: pageOrigin,
            bottomOfPagerInWindow: feedClipsBottomInWindow(),
            topOfTabBarInWindow: UITabBar.feedClipsTopInWindow(from: self)
        )
    }
}
