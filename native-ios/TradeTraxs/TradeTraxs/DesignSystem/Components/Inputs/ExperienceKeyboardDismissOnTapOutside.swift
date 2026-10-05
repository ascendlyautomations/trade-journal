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
        private var ownsRecognizer = false

        func installIfNeeded(from anchor: UIView) {
            guard let host = anchor.nearestViewControllerHostView else { return }
            if installedHost === host,
               let tapRecognizer,
               host.gestureRecognizers?.contains(tapRecognizer) == true {
                return
            }
            uninstall(from: anchor)

            if let existing = host.gestureRecognizers?.first(where: {
                $0.name == ExperienceKeyboardDismissTapName.recognizer
            }) as? UITapGestureRecognizer {
                tapRecognizer = existing
                installedHost = host
                ownsRecognizer = false
                return
            }

            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            tap.name = ExperienceKeyboardDismissTapName.recognizer
            tap.cancelsTouchesInView = false
            tap.delaysTouchesBegan = false
            tap.delaysTouchesEnded = false
            tap.delegate = self
            host.addGestureRecognizer(tap)
            tapRecognizer = tap
            installedHost = host
            ownsRecognizer = true
        }

        func uninstall(from anchor: UIView) {
            if ownsRecognizer, let host = installedHost, let tapRecognizer {
                host.removeGestureRecognizer(tapRecognizer)
            }
            tapRecognizer = nil
            installedHost = nil
            ownsRecognizer = false
        }

        @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
            let hit = recognizer.view?.hitTest(recognizer.location(in: recognizer.view), with: nil)
            if TextInputFocusGuard.touchIsInsideEditableView(hit) {
                TextInputResponsivenessProbe.tap(
                    screen: "keyboardDismiss",
                    field: TextInputFocusGuard.fieldIdentifier(for: hit)
                )
                return
            }
            TextInputResponsivenessProbe.focusChanged(
                screen: "keyboardDismiss",
                field: "outsideTap",
                focused: false
            )
            ExperienceKeyboard.dismiss()
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            true
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            if TextInputFocusGuard.touchIsInsideEditableView(touch.view) {
                TextInputResponsivenessProbe.tap(
                    screen: "keyboardDismiss",
                    field: TextInputFocusGuard.fieldIdentifier(for: touch.view)
                )
                return false
            }
            return true
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
