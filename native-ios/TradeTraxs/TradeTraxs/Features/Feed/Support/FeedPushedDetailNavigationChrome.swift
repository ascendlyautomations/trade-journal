import SwiftUI
import UIKit

/// Feed stack detail pushes — chevron-only back (no previous-screen "Feed" title).
struct FeedPushedDetailNavigationChrome: ViewModifier {
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden(true)
            .experienceArrowBackToolbarButton(action: dismiss.callAsFunction)
            .background(FeedNavigationInteractivePopEnabler())
    }
}

extension View {
    func feedPushedDetailNavigationChrome() -> some View {
        modifier(FeedPushedDetailNavigationChrome())
    }
}

// MARK: - Interactive pop when the system back button is hidden

/// Re-enables the leading-edge swipe-back gesture on `NavigationStack` pushes.
private struct FeedNavigationInteractivePopEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> FeedNavigationInteractivePopEnablerViewController {
        FeedNavigationInteractivePopEnablerViewController()
    }

    func updateUIViewController(
        _ uiViewController: FeedNavigationInteractivePopEnablerViewController,
        context: Context
    ) {
        uiViewController.enableInteractivePopIfNeeded()
    }
}

private final class FeedNavigationInteractivePopGestureDelegate: NSObject, UIGestureRecognizerDelegate {
    weak var navigationController: UINavigationController?

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        (navigationController?.viewControllers.count ?? 0) > 1
    }
}

private final class FeedNavigationInteractivePopEnablerViewController: UIViewController {
    private let popDelegate = FeedNavigationInteractivePopGestureDelegate()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        enableInteractivePopIfNeeded()
    }

    func enableInteractivePopIfNeeded() {
        guard let navigationController else { return }
        popDelegate.navigationController = navigationController
        guard let pop = navigationController.interactivePopGestureRecognizer else { return }
        pop.isEnabled = true
        pop.delegate = popDelegate
    }
}
