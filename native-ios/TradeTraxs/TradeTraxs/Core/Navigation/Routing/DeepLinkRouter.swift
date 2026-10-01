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
        let path = url.path
        DeepLinkLaunchTrace.event("universalLink.received", path: path)
        if DeepLinkLaunchTrace.shouldIgnoreDuplicate(url) {
            DeepLinkLaunchTrace.event("navigation.skipped", path: path, detail: "duplicate")
            return true
        }

        if let recovery = PasswordRecoveryLink.parse(url) {
            PasswordRecoveryInbox.shared.receive(recovery)
            DeepLinkLaunchTrace.event("navigation.executed", path: path, detail: "passwordRecovery")
            return true
        }

        guard let destination = parser.parse(url: url) else {
            AppLog.navigation.error("Deep link parse failed path=\(path, privacy: .public)")
            DeepLinkLaunchTrace.event("parsed.failed", path: path)
            openUnhandledTradeTraxsURLInBrowserIfNeeded(url)
            return false
        }

        seedRoomFocus(from: url, destination: destination)
        DeepLinkLaunchTrace.event("parsed.route", path: path, detail: String(describing: destination))

        if store.sessionPhase != .authenticated {
            switch destination {
            case .auth:
                coordinator.open(destination)
                DeepLinkLaunchTrace.event("navigation.executed", path: path, detail: "auth")
            default:
                coordinator.stashForAuthentication(destination)
                DeepLinkLaunchTrace.event("pending.queued", path: path)
            }
            return true
        }

        if NativeOAuthConfiguration.isTradovateBrokerOAuthCallbackURL(url) {
            TradovateBrokerOAuthNotificationPayload.post(from: url)
        }

        // Auth routes call openAuth, which forces sessionPhase back to unauthenticated.
        // The root then stays on SplashView because auth state is already authenticated
        // and applyNavigation will not mark the shell authenticated again.
        if case .auth = destination {
            DeepLinkLaunchTrace.event(
                "navigation.skipped",
                path: path,
                detail: "authRouteWhileAuthenticated"
            )
            return true
        }

        coordinator.open(destination)
        DeepLinkLaunchTrace.event("navigation.executed", path: path)
        return true
    }

    /// Claimed Universal Links with no native route stay in the app shell.
    /// Re-opening them in Safari hands the same URL back to the app.
    @MainActor
    func openUnhandledTradeTraxsURLInBrowserIfNeeded(_ url: URL) {
        guard UniversalLinkPolicy.isSupportedHTTPSHost(url) else { return }
        DeepLinkLaunchTrace.event("navigation.failed", path: url.path, detail: "stayInShell")
    }

    @MainActor
    private func seedRoomFocus(from url: URL, destination: AppDestination) {
        let query = url.queryItemsDictionary
        let section = query["section"]
        let message = query["message"]
        guard section != nil || message != nil else { return }

        let roomID: RoomID?
        switch destination {
        case .feed(.room(let id)), .messages(.room(let id)), .profile(.room(let id)):
            roomID = id
        default:
            if let room = query["room"], !room.isEmpty {
                roomID = RoomID(room)
            } else {
                roomID = nil
            }
        }
        guard let roomID else { return }
        RoomNavigationFocusStore.shared.seed(
            roomID: roomID,
            sectionID: section,
            messageID: message
        )
    }
}

/// DEBUG launch/deep-link breadcrumbs. Release builds compile the calls out.
enum DeepLinkLaunchTrace {
    static func event(_ name: String, path: String = "", detail: String = "") {
        #if DEBUG
        let pathPart = path.isEmpty ? "" : " path=\(path)"
        let detailPart = detail.isEmpty ? "" : " \(detail)"
        print("[DeepLinkLaunch] \(name)\(pathPart)\(detailPart)")
        #endif
    }

    /// Collapses the OS delivering the same link twice (cold start + SwiftUI).
    @MainActor
    static func shouldIgnoreDuplicate(_ url: URL) -> Bool {
        let key = "\((url.scheme ?? "").lowercased())|\((url.host ?? "").lowercased())|\(url.path)"
        let now = Date().timeIntervalSince1970
        if let last = recentRoutes[key], now - last < 1 {
            return true
        }
        recentRoutes[key] = now
        return false
    }

    @MainActor
    static func resetDuplicateGuardForTesting() {
        recentRoutes.removeAll()
    }

    @MainActor
    private static var recentRoutes: [String: TimeInterval] = [:]
}

/// URLs captured before SwiftUI's `onOpenURL` is attached. Drained once the root appears.
enum LaunchUniversalLinkInbox {
    private static var urls: [URL] = []

    static func capture(_ url: URL) {
        DeepLinkLaunchTrace.event("universalLink.received", path: url.path, detail: "inbox")
        if urls.contains(where: { $0.absoluteString == url.absoluteString }) { return }
        urls.append(url)
    }

    static func drain() -> [URL] {
        let copy = urls
        urls.removeAll()
        return copy
    }
}

/// Authenticated session + demoted navigation phase is the permanent splash.
enum AuthenticatedShellGate {
    static func shouldRepairShell(didEnterAuthenticatedShell: Bool, sessionPhase: SessionPhase) -> Bool {
        didEnterAuthenticatedShell && sessionPhase != .authenticated
    }
}
