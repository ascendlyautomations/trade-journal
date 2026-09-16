import SwiftUI
import UIKit

private enum ExperienceKeyboardDismissTapName {
    static let recognizer = "ExperienceKeyboardDismissTap"
}

/// Installs a non-blocking tap on the host view controller so taps outside text inputs resign first responder.
struct ExperienceKeyboardDismissOnTapOutsideInstaller: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.installIfNeeded(from: uiView)
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.uninstall(from: uiView)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private weak var installedHost: UIView?
        private var tapRecognizer: UITapGestureRecognizer?

        func installIfNeeded(from anchor: UIView) {
            guard let host = anchor.nearestViewControllerHostView else { return }
            if installedHost === host, tapRecognizer != nil { return }
            uninstall(from: anchor)

            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
            tap.name = ExperienceKeyboardDismissTapName.recognizer
            tap.cancelsTouchesInView = false
            tap.delegate = self
            host.addGestureRecognizer(tap)
            tapRecognizer = tap
            installedHost = host
        }

        func uninstall(from anchor: UIView) {
            guard let host = installedHost, let tapRecognizer else { return }
            host.removeGestureRecognizer(tapRecognizer)
            self.tapRecognizer = nil
            installedHost = nil
        }

        @objc private func handleTap() {
            ExperienceKeyboard.dismiss()
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            true
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            !Self.touchIsInsideEditableView(touch.view)
        }

        private static func touchIsInsideEditableView(_ view: UIView?) -> Bool {
            var current = view
            while let candidate = current {
                if candidate is UITextField || candidate is UITextView {
                    return true
                }
                current = candidate.superview
            }
            return false
        }
    }
}

private struct ExperienceKeyboardDismissOnTapOutsideModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.background {
            ExperienceKeyboardDismissOnTapOutsideInstaller()
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
    }
}

extension View {
    /// Tap outside ``UITextField`` / ``UITextView`` dismisses the keyboard without blocking other controls.
    func experienceKeyboardDismissOnTapOutside() -> some View {
        modifier(ExperienceKeyboardDismissOnTapOutsideModifier())
    }
}

private extension UIView {
    var nearestViewControllerHostView: UIView? {
        var responder: UIResponder? = self
        while let current = responder {
            if let controller = current as? UIViewController {
                return controller.view
            }
            responder = current.next
        }
        return window
    }
}
