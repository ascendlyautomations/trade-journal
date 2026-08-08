import Foundation
import OSLog

/// Entry façade for universal links and custom schemes.
///
/// Parses once, then applies through ``NavigationCoordinator``.
struct DeepLinkRouter: Sendable {
    private let parser: any DeepLinkParsing

    init(parser: any DeepLinkParsing = DeepLinkParser()) {
        self.parser = parser
    }

    @MainActor
    func route(url: URL, using coordinator: NavigationCoordinator, store: NavigationStore) -> Bool {
        guard let destination = parser.parse(url: url) else {
            AppLog.navigation.error("Deep link parse failed: \(url.absoluteString, privacy: .public)")
            return false
        }

        AppLog.navigation.info("Deep link resolved: \(String(describing: destination), privacy: .public)")

        if store.sessionPhase != .authenticated {
            switch destination {
            case .auth:
                coordinator.open(destination)
            default:
                coordinator.stashForAuthentication(destination)
            }
            return true
        }

        coordinator.open(destination)
        return true
    }
}
