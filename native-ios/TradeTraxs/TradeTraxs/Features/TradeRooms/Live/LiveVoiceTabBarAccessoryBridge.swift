import SwiftUI
import UIKit

/// Published height of shell voice/stream chrome sitting directly above the tab bar.
@Observable
@MainActor
final class TradeRoomLiveSessionChromeMetrics {
    static let shared = TradeRoomLiveSessionChromeMetrics()

    private(set) var bottomInset: CGFloat = 0

    func setBottomInset(_ value: CGFloat) {
        let clamped = max(0, value)
        guard abs(bottomInset - clamped) > 0.5 else { return }
        bottomInset = clamped
    }
}

private struct TradeRoomLiveSessionBottomInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    /// Extra space above the tab bar reserved for voice/stream session bars.
    var tradeRoomLiveSessionBottomInset: CGFloat {
        get { self[TradeRoomLiveSessionBottomInsetKey.self] }
        set { self[TradeRoomLiveSessionBottomInsetKey.self] = newValue }
    }
}

/// iOS 18–25: pins session chrome to ``UITabBar`` top and expands child safe areas (no overlay on tab items).
struct LiveVoiceTabBarAccessoryBridge<Accessory: View>: UIViewRepresentable {
    @ViewBuilder var accessory: () -> Accessory

    func makeCoordinator() -> Coordinator {
        Coordinator(accessory: accessory)
    }

    func makeUIView(context: Context) -> LiveVoiceTabBarAccessoryAnchorView {
        let view = LiveVoiceTabBarAccessoryAnchorView()
        view.onAttach = { [weak coordinator = context.coordinator] anchor in
            coordinator?.attach(from: anchor)
        }
        return view
    }

    func updateUIView(_ uiView: LiveVoiceTabBarAccessoryAnchorView, context: Context) {
        context.coordinator.accessoryBuilder = accessory
        context.coordinator.refreshAccessoryLayout()
    }

    static func dismantleUIView(_ uiView: LiveVoiceTabBarAccessoryAnchorView, coordinator: Coordinator) {
        coordinator.teardown()
    }

    @MainActor
    final class Coordinator {
        var accessoryBuilder: () -> Accessory
        private weak var tabBarController: UITabBarController?
        private var containerView: UIView?
        private var hostingController: UIHostingController<AnyView>?
        private var heightConstraint: NSLayoutConstraint?
        private var pendingLayout: DispatchWorkItem?

        init(accessory: @escaping () -> Accessory) {
            self.accessoryBuilder = accessory
        }

        func attach(from anchor: UIView) {
            guard anchor.window != nil else { return }
            guard let tab = Self.findTabBarController(from: anchor) else { return }
            if tabBarController !== tab {
                teardown()
                tabBarController = tab
                installContainer(in: tab)
            }
            refreshAccessoryLayout()
        }

        func refreshAccessoryLayout() {
            guard let tab = tabBarController, let container = containerView else { return }
            let root = AnyView(accessoryBuilder())
            if hostingController == nil {
                let host = UIHostingController(rootView: root)
                host.view.backgroundColor = .clear
                host.view.translatesAutoresizingMaskIntoConstraints = false
                host.sizingOptions = .intrinsicContentSize
                container.addSubview(host.view)
                NSLayoutConstraint.activate([
                    host.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                    host.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                    host.view.topAnchor.constraint(equalTo: container.topAnchor),
                    host.view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                ])
                hostingController = host
            } else {
                hostingController?.rootView = root
            }

            pendingLayout?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.applyMeasuredHeight()
            }
            pendingLayout = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
        }

        private func applyMeasuredHeight() {
            guard let tab = tabBarController, let host = hostingController, let container = containerView else {
                return
            }
            let width = tab.view.bounds.width
            guard width > 0 else { return }
            let target = CGSize(width: width, height: UIView.layoutFittingCompressedSize.height)
            let measured = host.sizeThatFits(in: target)
            let height = max(0, ceil(measured.height))
            heightConstraint?.constant = height
            container.isHidden = height < 1

            var inset = tab.additionalSafeAreaInsets
            inset.bottom = height
            tab.additionalSafeAreaInsets = inset

            TradeRoomLiveSessionChromeMetrics.shared.setBottomInset(height)
            tab.view.setNeedsLayout()
        }

        private func installContainer(in tab: UITabBarController) {
            let container = UIView()
            container.backgroundColor = .clear
            container.translatesAutoresizingMaskIntoConstraints = false
            tab.view.addSubview(container)

            let height = container.heightAnchor.constraint(equalToConstant: 0)
            heightConstraint = height

            NSLayoutConstraint.activate([
                container.leadingAnchor.constraint(equalTo: tab.view.leadingAnchor),
                container.trailingAnchor.constraint(equalTo: tab.view.trailingAnchor),
                container.bottomAnchor.constraint(equalTo: tab.tabBar.topAnchor),
                height,
            ])

            containerView = container
        }

        func teardown() {
            pendingLayout?.cancel()
            pendingLayout = nil
            if let tab = tabBarController {
                var inset = tab.additionalSafeAreaInsets
                inset.bottom = 0
                tab.additionalSafeAreaInsets = inset
            }
            hostingController?.view.removeFromSuperview()
            hostingController = nil
            containerView?.removeFromSuperview()
            containerView = nil
            heightConstraint = nil
            tabBarController = nil
            TradeRoomLiveSessionChromeMetrics.shared.setBottomInset(0)
        }

        private static func findTabBarController(from view: UIView) -> UITabBarController? {
            var responder: UIResponder? = view
            while let current = responder {
                if let tab = current as? UITabBarController { return tab }
                responder = current.next
            }
            return nil
        }
    }
}

final class LiveVoiceTabBarAccessoryAnchorView: UIView {
    var onAttach: ((UIView) -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            onAttach?(self)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        onAttach?(self)
    }
}

struct LiveVoiceTabBarAccessoryBridgeModifier<Accessory: View>: ViewModifier {
    @ViewBuilder var accessory: () -> Accessory

    func body(content: Content) -> some View {
        content
            .background {
                LiveVoiceTabBarAccessoryBridge(accessory: accessory)
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)
            }
            .environment(\.tradeRoomLiveSessionBottomInset, TradeRoomLiveSessionChromeMetrics.shared.bottomInset)
            .onReceive(NotificationCenter.default.publisher(for: .tradeTraxsLiveVoiceSessionDidChange)) { _ in
                // Trigger SwiftUI refresh when inset may change.
            }
    }
}
