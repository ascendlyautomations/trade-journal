import SwiftUI
import UIKit

/// Intercepts the interactive pop gesture so unsaved Trading Rules drafts can show a confirmation first.
struct TradingRulesUnsavedNavigationGuard: UIViewControllerRepresentable, Equatable {
    var isActive: Bool
    var interceptBox: UnsavedNavigationInterceptBox

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.isActive == rhs.isActive
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(interceptBox: interceptBox)
    }

    func makeUIViewController(context: Context) -> GuardViewController {
        let controller = GuardViewController()
        controller.coordinator = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: GuardViewController, context: Context) {
        let wasActive = context.coordinator.isActive
        context.coordinator.isActive = isActive
        context.coordinator.interceptBox = interceptBox
        uiViewController.coordinator = context.coordinator
        if wasActive != isActive {
            uiViewController.syncPopGestureDelegateIfNeeded()
        }
    }

    @MainActor
    final class UnsavedNavigationInterceptBox {
        var onIntercept: (() -> Void)?
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var isActive = false
        var interceptBox: UnsavedNavigationInterceptBox

        init(interceptBox: UnsavedNavigationInterceptBox) {
            self.interceptBox = interceptBox
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard isActive else { return true }
            interceptBox.onIntercept?()
            return false
        }
    }

    final class GuardViewController: UIViewController {
        weak var coordinator: Coordinator?

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            syncPopGestureDelegateIfNeeded()
        }

        func syncPopGestureDelegateIfNeeded() {
            guard let coordinator, let nav = navigationController else { return }
            nav.interactivePopGestureRecognizer?.delegate = coordinator
            nav.interactivePopGestureRecognizer?.isEnabled = true
        }
    }
}