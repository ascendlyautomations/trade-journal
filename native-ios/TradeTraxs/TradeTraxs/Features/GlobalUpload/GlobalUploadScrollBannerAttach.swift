import SwiftUI
import UIKit

/// Pins the global upload banner to the top of the nearest scroll view so it scrolls away with page content.
private let globalUploadBannerAnimationDuration: TimeInterval = 0.28

@MainActor
enum GlobalUploadScrollBannerAttach {

    static func attach(
        to scrollView: UIScrollView,
        coordinator: GlobalUploadCoordinator,
        onAttached: @escaping (Bool) -> Void
    ) -> GlobalUploadScrollBannerHandle {
        let handle = GlobalUploadScrollBannerHandle(
            scrollView: scrollView,
            coordinator: coordinator,
            onAttached: onAttached
        )
        handle.syncPresentation(animated: false)
        return handle
    }
}

@MainActor
final class GlobalUploadScrollBannerHandle {
    private weak var scrollView: UIScrollView?
    private let coordinator: GlobalUploadCoordinator
    private let onAttached: (Bool) -> Void
    private var hosting: UIHostingController<GlobalUploadStatusBarHost>?
    private var headerContainer: UIView?
    private var heightConstraint: NSLayoutConstraint?
    private var tableHeaderContainer: UIView?

    init(
        scrollView: UIScrollView,
        coordinator: GlobalUploadCoordinator,
        onAttached: @escaping (Bool) -> Void
    ) {
        self.scrollView = scrollView
        self.coordinator = coordinator
        self.onAttached = onAttached
    }

    func syncPresentation(animated: Bool) {
        guard let scrollView else { return }
        guard let presentation = coordinator.barPresentation else {
            collapse(animated: animated)
            return
        }
        ensureInstalled(on: scrollView)
        updateHeight(for: presentation, animated: animated)
        onAttached(true)
    }

    func detach() {
        collapse(animated: true)
        hosting?.view.removeFromSuperview()
        hosting = nil
        headerContainer?.removeFromSuperview()
        headerContainer = nil
        tableHeaderContainer = nil
        heightConstraint = nil
        if let tableView = scrollView as? UITableView {
            tableView.tableHeaderView = nil
        }
        onAttached(false)
    }

    private func collapse(animated: Bool) {
        let apply = {
            self.heightConstraint?.constant = 0
            self.hosting?.view.isHidden = true
            self.headerContainer?.isHidden = true
            self.tableHeaderContainer?.isHidden = true
            if let tableView = self.scrollView as? UITableView {
                tableView.tableHeaderView = nil
            }
            self.scrollView?.layoutIfNeeded()
        }
        if animated {
            UIView.animate(withDuration: globalUploadBannerAnimationDuration, animations: apply)
        } else {
            apply()
        }
        onAttached(false)
    }

    private func ensureInstalled(on scrollView: UIScrollView) {
        guard hosting == nil else { return }

        let hostView = GlobalUploadStatusBarHost(
            coordinator: coordinator,
            presentation: coordinator.barPresentation ?? GlobalUploadBarPresentation(
                line: "",
                progress: nil,
                showsRetry: false,
                retryJobID: nil,
                activeCount: 0
            )
        )
        let hosting = UIHostingController(rootView: hostView)
        hosting.view.backgroundColor = .clear
        hosting.sizingOptions = [.intrinsicContentSize]
        self.hosting = hosting

        if let tableView = scrollView as? UITableView {
            let container = UIView(frame: CGRect(x: 0, y: 0, width: tableView.bounds.width, height: 1))
            container.addSubview(hosting.view)
            hosting.view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                hosting.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                hosting.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                hosting.view.topAnchor.constraint(equalTo: container.topAnchor),
                hosting.view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])
            tableView.tableHeaderView = container
            tableHeaderContainer = container
            return
        }

        let container = UIView()
        container.clipsToBounds = true
        scrollView.addSubview(container)
        container.translatesAutoresizingMaskIntoConstraints = false
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(hosting.view)

        let height = container.heightAnchor.constraint(equalToConstant: 0)
        heightConstraint = height
        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            height,
            hosting.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: container.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        headerContainer = container
    }

    private func updateHeight(for presentation: GlobalUploadBarPresentation, animated: Bool) {
        guard let hosting else { return }
        hosting.rootView = GlobalUploadStatusBarHost(coordinator: coordinator, presentation: presentation)
        hosting.view.isHidden = false
        headerContainer?.isHidden = false
        tableHeaderContainer?.isHidden = false

        hosting.view.setNeedsLayout()
        hosting.view.layoutIfNeeded()
        let targetHeight = hosting.view.systemLayoutSizeFitting(
            CGSize(width: scrollView?.bounds.width ?? UIScreen.main.bounds.width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height

        let apply = {
            self.heightConstraint?.constant = max(0, targetHeight)
            if let tableView = self.scrollView as? UITableView, let container = self.tableHeaderContainer {
                var frame = container.frame
                frame.size.height = max(1, targetHeight)
                frame.size.width = tableView.bounds.width
                container.frame = frame
                tableView.tableHeaderView = container
            }
            self.scrollView?.layoutIfNeeded()
        }

        if animated {
            UIView.animate(withDuration: globalUploadBannerAnimationDuration, animations: apply)
        } else {
            apply()
        }
    }
}

private struct GlobalUploadStatusBarHost: View {
    @Bindable var coordinator: GlobalUploadCoordinator
    let presentation: GlobalUploadBarPresentation

    var body: some View {
        GlobalUploadStatusBar(coordinator: coordinator, presentation: presentation)
    }
}

private struct GlobalUploadScrollBannerAnchor: UIViewRepresentable {
    @Bindable var coordinator: GlobalUploadCoordinator
    @Binding var scrollBannerAttached: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(scrollBannerAttached: $scrollBannerAttached)
    }

    func makeUIView(context: Context) -> GlobalUploadScrollAnchorView {
        let view = GlobalUploadScrollAnchorView()
        view.delegate = context.coordinator
        return view
    }

    func updateUIView(_ uiView: GlobalUploadScrollAnchorView, context: Context) {
        context.coordinator.coordinator = coordinator
        uiView.resolveScrollViewIfNeeded()
        context.coordinator.syncPresentation(from: uiView)
    }

    final class Coordinator: NSObject, GlobalUploadScrollAnchorViewDelegate {
        @Binding var scrollBannerAttached: Bool
        var coordinator: GlobalUploadCoordinator
        private var handle: GlobalUploadScrollBannerHandle?

        init(scrollBannerAttached: Binding<Bool>) {
            _scrollBannerAttached = scrollBannerAttached
            coordinator = GlobalUploadCoordinator.shared
        }

        func scrollViewDidResolve(_ scrollView: UIScrollView) {
            handle?.detach()
            handle = GlobalUploadScrollBannerAttach.attach(
                to: scrollView,
                coordinator: coordinator,
                onAttached: { [weak self] attached in
                    self?.publishScrollBannerAttached(attached)
                }
            )
        }

        func syncPresentation(from anchor: GlobalUploadScrollAnchorView) {
            guard let scrollView = anchor.resolvedScrollView else {
                handle?.detach()
                handle = nil
                publishScrollBannerAttached(false)
                return
            }
            if handle == nil {
                scrollViewDidResolve(scrollView)
            }
            handle?.syncPresentation(animated: true)
        }

        /// SwiftUI `@Binding` must not change during `updateUIView` when clearing attachment.
        private func publishScrollBannerAttached(_ attached: Bool) {
            guard scrollBannerAttached != attached else { return }
            if attached {
                scrollBannerAttached = true
                return
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.scrollBannerAttached != attached else { return }
                self.scrollBannerAttached = attached
            }
        }
    }
}

@MainActor
protocol GlobalUploadScrollAnchorViewDelegate: AnyObject {
    func scrollViewDidResolve(_ scrollView: UIScrollView)
}

final class GlobalUploadScrollAnchorView: UIView {
    weak var delegate: GlobalUploadScrollAnchorViewDelegate?
    private(set) weak var resolvedScrollView: UIScrollView?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        resolveScrollViewIfNeeded()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        resolveScrollViewIfNeeded()
    }

    func resolveScrollViewIfNeeded() {
        let found = findEnclosingScrollView() ?? findOutermostScrollView(in: superview)
        guard found !== resolvedScrollView else { return }
        resolvedScrollView = found
        if let found {
            delegate?.scrollViewDidResolve(found)
        }
    }

    private func findEnclosingScrollView() -> UIScrollView? {
        var current: UIView? = superview
        while let view = current {
            if let scrollView = view as? UIScrollView { return scrollView }
            current = view.superview
        }
        return nil
    }

    /// Prefer the page-level scroll view — never a nested list/tab scroll inside section content.
    private func findOutermostScrollView(in root: UIView?) -> UIScrollView? {
        guard let root else { return nil }
        var scrollViews: [UIScrollView] = []
        collectScrollViews(in: root, into: &scrollViews, budget: 96)
        let outermost = scrollViews.filter { candidate in
            !scrollViews.contains { other in
                other !== candidate && candidate.isDescendant(of: other)
            }
        }
        return outermost.max { lhs, rhs in
            lhs.bounds.width * lhs.bounds.height < rhs.bounds.width * rhs.bounds.height
        }
    }

    private func collectScrollViews(in root: UIView, into list: inout [UIScrollView], budget: Int) {
        guard budget > 0 else { return }
        if let scrollView = root as? UIScrollView {
            list.append(scrollView)
        }
        var remaining = budget - 1
        for subview in root.subviews where remaining > 0 {
            collectScrollViews(in: subview, into: &list, budget: remaining)
            remaining -= 1
        }
    }
}

struct GlobalUploadPageLayoutModifier: ViewModifier {
    @Bindable private var coordinator = GlobalUploadCoordinator.shared
    @State private var scrollBannerAttached = false

    func body(content: Content) -> some View {
        let showsInlineFallback = !scrollBannerAttached && coordinator.barPresentation != nil
        VStack(spacing: 0) {
            if showsInlineFallback, let presentation = coordinator.barPresentation {
                GlobalUploadStatusBar(coordinator: coordinator, presentation: presentation)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            content
                .background {
                    GlobalUploadScrollBannerAnchor(
                        coordinator: coordinator,
                        scrollBannerAttached: $scrollBannerAttached
                    )
                }
        }
        .animation(.easeInOut(duration: 0.28), value: showsInlineFallback)
        .animation(.easeInOut(duration: 0.28), value: coordinator.barPresentation?.line)
    }
}
