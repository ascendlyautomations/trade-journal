import Foundation
import OSLog

/// App lifecycle hooks for authentication (background / foreground).
final class AuthenticationLifecycle {
    private let authenticationManager: AuthenticationManager
    private let authenticationCoordinator: AuthenticationCoordinator

    init(
        authenticationManager: AuthenticationManager,
        authenticationCoordinator: AuthenticationCoordinator
    ) {
        self.authenticationManager = authenticationManager
        self.authenticationCoordinator = authenticationCoordinator
    }

    func applicationDidLaunch() async {
        AppLog.authentication.info("AuthenticationLifecycle — cold launch restore")
        await authenticationCoordinator.bootstrapSession()
    }

    func applicationDidEnterBackground() {
        // Tokens remain in Keychain; in-memory session retained for quick resume.
        AppLog.authentication.debug("AuthenticationLifecycle — background")
    }

    func applicationWillEnterForeground() async {
        guard let session = authenticationManager.state.session else { return }
        if session.isExpired {
            await authenticationCoordinator.bootstrapSession()
        }
    }
}
