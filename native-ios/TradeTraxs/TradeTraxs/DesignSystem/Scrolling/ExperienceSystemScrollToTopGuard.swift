import SwiftUI
import UIKit

/// Disables UIKit status-bar, navigation-bar, and tab-bar automatic scroll-to-top on the
/// enclosing `UIScrollView` while programmatic scroll (tab reselect, filters, tour) stays intact.
extension View {
    func experienceDisablesSystemScrollToTop() -> some View {
        background(ExperienceSystemScrollToTopDisableAnchor())
    }
}

// MARK: - UIKit scroll-to-top guard

private struct ExperienceSystemScrollToTopDisableAnchor: UIViewRepresentable {
    func makeUIView(context: Context) -> ExperienceSystemScrollToTopGuardView {
        ExperienceSystemScrollToTopGuardView()
    }

    func updateUIView(_ uiView: ExperienceSystemScrollToTopGuardView, context: Context) {
        uiView.applyDisablingScrollsToTopIfNeeded()
    }
}

private final class ExperienceSystemScrollToTopGuardView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        applyDisablingScrollsToTopIfNeeded()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        applyDisablingScrollsToTopIfNeeded()
    }

    func applyDisablingScrollsToTopIfNeeded() {
        for scrollView in enclosingScrollViews where scrollView.scrollsToTop {
            scrollView.scrollsToTop = false
        }
    }

    private var enclosingScrollViews: [UIScrollView] {
        var views: [UIScrollView] = []
        var current = superview
        while let view = current {
            if let scrollView = view as? UIScrollView {
                views.append(scrollView)
            }
            current = view.superview
        }
        return views
    }
}