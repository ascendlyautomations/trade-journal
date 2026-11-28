import SwiftUI
import UIKit

/// Fights SwiftUI re-applying keyboard toolbars on `inputAccessoryView` after the field becomes first responder.
struct ExperienceKeyboardAccessorySuppressor: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.setActive(true)
        context.coordinator.stripAccessoryIfNeeded()
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.setActive(false)
    }

    final class Coordinator {
        private var observers: [NSObjectProtocol] = []
        private var displayLink: CADisplayLink?
        private var displayLinkProxy: DisplayLinkProxy?
        private var stripBudget = 0
        private var isActive = false

        func setActive(_ active: Bool) {
            isActive = active
            if active {
                startObservingIfNeeded()
            } else {
                stopObserving()
            }
        }

        func startObservingIfNeeded() {
            guard observers.isEmpty else { return }
            let center = NotificationCenter.default
            let names: [Notification.Name] = [
                UIResponder.keyboardWillShowNotification,
                UIResponder.keyboardDidShowNotification,
                UIResponder.keyboardWillChangeFrameNotification,
            ]
            observers = names.map { name in
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    self?.beginStripBurst()
                }
            }
        }

        func stopObserving() {
            let center = NotificationCenter.default
            observers.forEach { center.removeObserver($0) }
            observers.removeAll()
            stopDisplayLink()
            stripBudget = 0
        }

        func beginStripBurst() {
            stripBudget = 45
            startDisplayLinkIfNeeded()
            stripAccessoryIfNeeded()
        }

        func stripAccessoryIfNeeded() {
            guard isActive else { return }
            ExperienceKeyboardAccessoryStrip.clearOnFirstResponderIfNeeded()
        }

        private func startDisplayLinkIfNeeded() {
            guard displayLink == nil else { return }
            let proxy = DisplayLinkProxy(coordinator: self)
            let link = CADisplayLink(target: proxy, selector: #selector(DisplayLinkProxy.tick))
            link.add(to: .main, forMode: .common)
            displayLinkProxy = proxy
            displayLink = link
        }

        private func stopDisplayLink() {
            displayLink?.invalidate()
            displayLink = nil
            displayLinkProxy = nil
        }

        fileprivate func tick() {
            guard stripBudget > 0 else {
                stopDisplayLink()
                return
            }
            stripBudget -= 1
            stripAccessoryIfNeeded()
        }
    }
}

private final class DisplayLinkProxy: NSObject {
    weak var coordinator: ExperienceKeyboardAccessorySuppressor.Coordinator?

    init(coordinator: ExperienceKeyboardAccessorySuppressor.Coordinator) {
        self.coordinator = coordinator
    }

    @objc func tick() {
        coordinator?.tick()
    }
}

extension View {
    /// Story-style composers: no keyboard accessory strip above the system keyboard.
    @ViewBuilder
    func experienceSuppressKeyboardInputAccessory() -> some View {
        if ExperienceKeyboardNativeIsolation.isEnabled {
            self
        } else {
            background {
                ExperienceKeyboardAccessorySuppressor()
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }
}