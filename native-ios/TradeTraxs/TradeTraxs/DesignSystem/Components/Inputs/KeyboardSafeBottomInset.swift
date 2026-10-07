import SwiftUI
import UIKit

/// Extra space required to clear the keyboard after the system safe area has already been applied.
///
/// `keyboardCover` is the height of the system keyboard layout guide overlapping the host,
/// including the keyboard accessory. `safeAreaBottom` is the host's current bottom safe area.
enum KeyboardSafeBottomMath {
    static func additionalLift(keyboardCover: CGFloat, safeAreaBottom: CGFloat) -> CGFloat {
        max(0, keyboardCover - safeAreaBottom)
    }
}

/// Keeps bottom-aligned content above the keyboard the same way Messages does:
/// the system keyboard layout guide (keyboard + accessory), minus any inset UIKit already applied.
///
/// The measured host is the view controller, so this padding does not feed back into the measurement.
struct KeyboardSafeBottomInsetModifier: ViewModifier {
    @State private var lift: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear
                    .frame(height: lift)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .background {
                KeyboardSafeBottomProbe(lift: $lift)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
    }
}

extension View {
    /// Lifts this container above whatever part of the keyboard the safe area did not already clear.
    func experienceKeyboardSafeBottom() -> some View {
        modifier(KeyboardSafeBottomInsetModifier())
    }
}

private struct KeyboardSafeBottomProbe: UIViewRepresentable {
    @Binding var lift: CGFloat

    func makeUIView(context: Context) -> KeyboardLiftTracker {
        let tracker = KeyboardLiftTracker()
        tracker.onLift = { [weak coordinator = context.coordinator] newValue in
            coordinator?.publish(newValue)
        }
        context.coordinator.bind(lift: $lift)
        return tracker
    }

    func updateUIView(_ uiView: KeyboardLiftTracker, context: Context) {
        context.coordinator.bind(lift: $lift)
        uiView.onLift = { [weak coordinator = context.coordinator] newValue in
            coordinator?.publish(newValue)
        }
    }

    static func dismantleUIView(_ uiView: KeyboardLiftTracker, coordinator: Coordinator) {
        uiView.stopTracking()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var lift: Binding<CGFloat>?

        func bind(lift: Binding<CGFloat>) {
            self.lift = lift
        }

        func publish(_ newValue: CGFloat) {
            guard let lift else { return }
            guard abs(lift.wrappedValue - newValue) > 0.5 else { return }
            DispatchQueue.main.async {
                self.lift?.wrappedValue = newValue
            }
        }
    }
}

/// Tracks the animated keyboard layout guide, including interactive dismissal.
private final class KeyboardLiftTracker: UIView {
    var onLift: (CGFloat) -> Void = { _ in }

    private var sentinel: UIView?
    private weak var sentinelHost: UIView?
    private var displayLink: CADisplayLink?
    private var displayLinkProxy: DisplayLinkProxy?
    private var keyboardObservers: [NSObjectProtocol] = []
    private var lastPublishedLift: CGFloat = -.greatestFiniteMagnitude
    private var stableTicks = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        backgroundColor = .clear
        installKeyboardObservers()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        teardown()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            stopLink()
            removeSentinel()
            return
        }
        installSentinelIfNeeded()
    }

    private func installKeyboardObservers() {
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            UIResponder.keyboardWillChangeFrameNotification,
            UIResponder.keyboardWillHideNotification,
            UIResponder.keyboardDidHideNotification,
        ]
        keyboardObservers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                self?.handleKeyboard(notification)
            }
        }
    }

    private func handleKeyboard(_ notification: Notification) {
        installSentinelIfNeeded()
        if notification.name == UIResponder.keyboardDidHideNotification {
            lastPublishedLift = 0
            stableTicks = 0
            onLift(0)
            stopLink()
            return
        }
        stableTicks = 0
        startLink()
        publishLift()
    }

    private func installSentinelIfNeeded() {
        guard let host = nearestViewControllerView else { return }
        guard sentinelHost !== host else { return }
        removeSentinel()
        let sentinel = UIView()
        sentinel.isUserInteractionEnabled = false
        sentinel.isAccessibilityElement = false
        sentinel.accessibilityElementsHidden = true
        sentinel.backgroundColor = .clear
        sentinel.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(sentinel)
        NSLayoutConstraint.activate([
            sentinel.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            sentinel.widthAnchor.constraint(equalToConstant: 0),
            sentinel.topAnchor.constraint(equalTo: host.keyboardLayoutGuide.topAnchor),
            sentinel.bottomAnchor.constraint(equalTo: host.bottomAnchor),
        ])
        self.sentinel = sentinel
        sentinelHost = host
    }

    private func publishLift() {
        guard let host = sentinelHost, let sentinel else { return }
        let presentedHeight = sentinel.layer.presentation()?.bounds.height ?? sentinel.bounds.height
        let lift = KeyboardSafeBottomMath.additionalLift(
            keyboardCover: presentedHeight,
            safeAreaBottom: host.safeAreaInsets.bottom
        )
        if abs(lift - lastPublishedLift) <= 0.5 {
            stableTicks += 1
            if stableTicks > 30 {
                stopLink()
            }
            return
        }
        stableTicks = 0
        lastPublishedLift = lift
        onLift(lift)
    }

    func stopTracking() {
        stopLink()
        removeSentinel()
        let center = NotificationCenter.default
        keyboardObservers.forEach { center.removeObserver($0) }
        keyboardObservers.removeAll()
    }

    private func startLink() {
        guard displayLink == nil else { return }
        let proxy = DisplayLinkProxy(tracker: self)
        let link = CADisplayLink(target: proxy, selector: #selector(DisplayLinkProxy.tick))
        link.add(to: .main, forMode: .common)
        displayLinkProxy = proxy
        displayLink = link
    }

    private func stopLink() {
        displayLink?.invalidate()
        displayLink = nil
        displayLinkProxy = nil
    }

    fileprivate func tick() {
        publishLift()
    }

    private func removeSentinel() {
        sentinel?.removeFromSuperview()
        sentinel = nil
        sentinelHost = nil
    }

    private func teardown() {
        stopTracking()
    }

    private var nearestViewControllerView: UIView? {
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

/// Breaks the display-link retain cycle. The link retains the proxy; the proxy does not retain the tracker.
private final class DisplayLinkProxy: NSObject {
    weak var tracker: KeyboardLiftTracker?

    init(tracker: KeyboardLiftTracker) {
        self.tracker = tracker
    }

    @objc func tick() {
        tracker?.tick()
    }
}
