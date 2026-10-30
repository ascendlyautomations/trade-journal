import SwiftUI
import UIKit

/// Instagram-style back: interactive pop only from the leading ~10% of the screen.
enum NavigationInteractivePopEdgeSupport {
    /// Fraction of container width reserved for navigation back (not profile tab paging).
    static let leadingBackZoneWidthRatio: CGFloat = 0.10

    static func leadingBackZoneMaxX(containerWidth: CGFloat) -> CGFloat {
        containerWidth * leadingBackZoneWidthRatio
    }

    /// Global horizontal touch location (screen coordinates).
    static func beginsInLeadingBackZone(globalX: CGFloat, containerWidth: CGFloat) -> Bool {
        globalX <= leadingBackZoneMaxX(containerWidth: containerWidth)
    }

    static func beginsInLeadingBackZone(globalX: CGFloat) -> Bool {
        beginsInLeadingBackZone(globalX: globalX, containerWidth: currentContainerWidth)
    }

    static var currentContainerWidth: CGFloat {
        UIScreen.main.bounds.width
    }
}

// MARK: - UIKit enabler

struct NavigationInteractivePopEdgeEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ uiViewController: Controller, context: Context) {
        uiViewController.enableInteractivePopIfNeeded()
    }

    final class Controller: UIViewController {
        private let popDelegate = PopGestureDelegate()

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

    private final class PopGestureDelegate: NSObject, UIGestureRecognizerDelegate {
        weak var navigationController: UINavigationController?

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard (navigationController?.viewControllers.count ?? 0) > 1 else { return false }
            guard let view = navigationController?.view else { return false }
            let location = gestureRecognizer.location(in: view)
            let maxX = NavigationInteractivePopEdgeSupport.leadingBackZoneMaxX(
                containerWidth: view.bounds.width
            )
            return location.x <= maxX
        }
    }
}

extension View {
    /// Re-enables swipe-back, limited to the leading edge (content-area swipes stay local).
    func navigationInteractivePopFromLeadingEdgeOnly() -> some View {
        background(NavigationInteractivePopEdgeEnabler())
    }
}
