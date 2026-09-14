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
        if authenticationManager.shouldSkipAsyncRestoreAfterColdLaunch() {
            AppLog.authentication.debug(
                "AuthenticationLifecycle — cold launch already resolved session state"
            )
            await authenticationCoordinator.bootstrapSession()
            markInitialRestoreCompleted()
            return
        }
        AppLog.authentication.debug("AuthenticationLifecycle — initial session restore")
        await authenticationCoordinator.bootstrapSession()
        markInitialRestoreCompleted()
    }

    /// Logged-out cold launch — login must not wait for async restore.
    func markInitialRestoreCompletedIfLoggedOut() {
        guard authenticationManager.shouldSkipAsyncRestoreAfterColdLaunch() else { return }
        markInitialRestoreCompleted()
    }

    private func markInitialRestoreCompleted() {
        guard !initialRestoreCompleted else { return }
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
