import Foundation
import Observation
import OSLog

/// App lifecycle hooks for authentication (background / foreground).
@Observable
final class AuthenticationLifecycle {
    private let authenticationManager: AuthenticationManager
    private let authenticationCoordinator: AuthenticationCoordinator
    private(set) var initialRestoreCompleted = false

    /// Bound by ``CompositionRoot`` — coalesced TraxPro entitlement refresh on foreground.
    /// Not part of SwiftUI observation (closure isolation is incompatible with `@Observable` synthesis).
    @ObservationIgnored
    var refreshBillingEntitlementsOnForeground: (@MainActor () async -> Void)?

    init(
        authenticationManager: AuthenticationManager,
        authenticationCoordinator: AuthenticationCoordinator
    ) {
        self.authenticationManager = authenticationManager
        self.authenticationCoordinator = authenticationCoordinator
    }

    func applicationDidLaunch() async {
        defer { markInitialRestoreCompleted() }
        if authenticationManager.shouldSkipAsyncRestoreAfterColdLaunch() {
            AppLog.authentication.debug(
                "AuthenticationLifecycle — cold launch already resolved session state"
            )
            await authenticationCoordinator.bootstrapSession()
            return
        }
        AppLog.authentication.debug("AuthenticationLifecycle — initial session restore")
        await authenticationCoordinator.bootstrapSession()
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
        await refreshBillingEntitlementsOnForeground?()
    }
}
