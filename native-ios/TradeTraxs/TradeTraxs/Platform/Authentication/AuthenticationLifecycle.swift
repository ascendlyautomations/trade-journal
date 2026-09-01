import Foundation
import OSLog

/// App lifecycle hooks for authentication (background / foreground).
@Observable
final class AuthenticationLifecycle {
    private let authenticationManager: AuthenticationManager
    private let authenticationCoordinator: AuthenticationCoordinator
    private(set) var initialRestoreCompleted = false

    init(
        authenticationManager: AuthenticationManager,
        authenticationCoordinator: AuthenticationCoordinator
    ) {
        self.authenticationManager = authenticationManager
        self.authenticationCoordinator = authenticationCoordinator
    }

    func applicationDidLaunch() async {
        AppLog.authentication.debug("AuthenticationLifecycle — initial session restore")
        await authenticationCoordinator.bootstrapSession()
        initialRestoreCompleted = true
    }

    func applicationDidEnterBackground() {
        AppLog.authentication.debug("AuthenticationLifecycle — background")
    }

    func applicationWillEnterForeground() async {
        guard initialRestoreCompleted else { return }
        guard authenticationManager.state.session != nil else { return }
        if authenticationManager.sessionNeedsRefresh() {
            await authenticationCoordinator.bootstrapSession()
        }
    }
}
