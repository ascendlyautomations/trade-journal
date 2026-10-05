import Foundation
import Observation

enum DemoExitAuthIntent: Sendable {
    case signIn
    case createAccount
}

/// Owns the process ``AppEnvironment`` and completes deferred bootstrap on demand (sign-in).
@Observable
@MainActor
final class AppLaunchController {
    static let shared = AppLaunchController()

    private(set) var environment: AppEnvironment
    private(set) var bootstrapGeneration: UInt64 = 0
    private(set) var isDemoExperienceActive = false
    /// Bumped when a newer published snapshot is installed during an open Demo session.
    private(set) var demoSnapshotRevision: UInt64 = 0
    private(set) var demoExitAuthIntent: DemoExitAuthIntent?
    private(set) var guestExploreFailurePresented = false
    private(set) var isGuestExploreRequestInFlight = false
    static let guestExploreFailureMessage = "Unable to load Explore as Guest. Please try again."

    var guestSessionIsInstalled: Bool { guestSessionInstalled }

    func consumeDemoExitAuthIntent() -> DemoExitAuthIntent? {
        defer { demoExitAuthIntent = nil }
        return demoExitAuthIntent
    }

    private var deferredContext: DeferredBootstrapContext?
    private var fullBootstrapTask: Task<AppEnvironment, Never>?
    private var preDemoEnvironment: AppEnvironment?
    private var guestSessionInstalled = false
    private var guestRenewalTask: Task<Void, Never>?
    private var guestReissueTask: Task<Bool, Never>?
    private var guestEpoch: UInt64 = 0
    /// One auth generation for the current guest token. Reissue replaces it.
    private var guestNetworkGeneration: UInt64?
    private var guestNetworkBoundary: Task<Void, Never>?

    private init() {
        StartupTrace.begin("AppLaunchController.init")
        StartupTrace.anchorAppStartIfNeeded()
        StartupTrace.event("swiftUIAppInit")
        let result = CompositionRoot.bootstrap()
        environment = result.environment
        deferredContext = result.deferredContext
        StartupTrace.end("AppLaunchController.init")
        // Logged-out: production stack loads only via ``ensureFullBootstrapComplete()`` (sign-in).
    }

    /// Sign-in and other authenticated operations await the live data/network stack.
    func ensureFullBootstrapComplete() async {
        await completeDeferredBootstrap(retainDeferredContext: false)
    }

    var deferredProductionBootstrapAvailable: Bool { deferredContext != nil }

    /// Drops guest bearer state before a real Supabase session is installed.
    func relinquishGuestSessionForAuthenticatedSignIn() {
        guestEpoch &+= 1
        guestRenewalTask?.cancel()
        guestRenewalTask = nil
        guestReissueTask?.cancel()
        guestReissueTask = nil
        if guestSessionInstalled {
            environment.authentication.manager.sessionManagerForNetworking.clearMemory()
            guestSessionInstalled = false
        }
        if isDemoExperienceActive {
            isDemoExperienceActive = false
            DemoExperienceSupport.setExploreLiveCommunityReadsActive(false)
            preDemoEnvironment = nil
        }
    }

    /// Logged-out Explore as Guest. One path: a guest-session for the showcase account.
    func enterDemoExplore() {
        guard !isDemoExperienceActive else { return }
        guard !isGuestExploreRequestInFlight else { return }
        guard environment.authentication.manager.state.isUnauthenticatedForDemoEntry else { return }
        guestExploreFailurePresented = false
        isGuestExploreRequestInFlight = true
        Task { await enterExploreAsGuest() }
    }

    /// Same issuer path as Explore as Guest, without the signed-out guard. Tests only.
    func enterGuestExploreBypassingAuthGateForTesting() {
        guard !isDemoExperienceActive else { return }
        guard !isGuestExploreRequestInFlight else { return }
        guestExploreFailurePresented = false
        isGuestExploreRequestInFlight = true
        Task { await enterExploreAsGuest(requiresSignedOut: false) }
    }

    func dismissGuestExploreFailure() {
        guestExploreFailurePresented = false
    }

    /// Replaces an expired guest access token. Does not call GoTrue refresh.
    func renewExpiredGuestSession() async -> Bool {
        guard guestSessionInstalled else { return false }
        if let guestReissueTask {
            return await guestReissueTask.value
        }
        let task = Task { @MainActor in
            await self.performGuestReissue()
        }
        guestReissueTask = task
        let renewed = await task.value
        if guestReissueTask == task {
            guestReissueTask = nil
        }
        return renewed
    }

    /// Installs a guest token without bootstrapping. Used by guest-session tests.
    func installGuestSessionForTesting(_ issued: GuestSessionIssuance) async {
        await installGuestSession(issued)
        isDemoExperienceActive = true
    }

    func awaitGuestNetworkBoundaryForTesting() async {
        await guestNetworkBoundary?.value
    }

    private func enterExploreAsGuest(requiresSignedOut: Bool = true) async {
        defer { isGuestExploreRequestInFlight = false }
        guard !isDemoExperienceActive else { return }
        if requiresSignedOut, !environment.authentication.manager.state.isUnauthenticatedForDemoEntry {
            return
        }
        if let issued = await GuestSessionClient.issue(configuration: environment.configuration) {
            await enterProductionGuest(issued)
            return
        }
        guestExploreFailurePresented = true
    }

    private func performGuestReissue() async -> Bool {
        let epoch = guestEpoch
        guard guestSessionInstalled, isDemoExperienceActive else { return false }
        guard let issued = await GuestSessionClient.issue(configuration: environment.configuration) else {
            guard epoch == guestEpoch else { return false }
            exitDemoExplore()
            guestExploreFailurePresented = true
            return false
        }
        guard epoch == guestEpoch, isDemoExperienceActive else { return false }
        await installGuestSession(issued)
        return true
    }

    private func enterProductionGuest(_ issued: GuestSessionIssuance) async {
        preDemoEnvironment = environment
        await installGuestSession(issued)
        await completeDeferredBootstrap(retainDeferredContext: true)
        AuthLandingInstallState.shared.recordLoggedOutAuthLandingPresented()
        SessionScopedCaches.invalidate(
            currentUserProfile: environment.currentUserProfile,
            data: environment.data
        )
        SessionViewerGate.shared.bind(issued.userID.rawValue)
        environment.navigation.coordinator.markExploreExperience()
        ExploreSessionStore.shared.invalidate()
        bootstrapGeneration &+= 1
        isDemoExperienceActive = true
        StartupTrace.event("guestExplore.entered")
        ExploreModeConversionPromptCoordinator.shared.exploreModeDidEnter()
    }

    private func installGuestSession(_ issued: GuestSessionIssuance) async {
        let epoch = guestEpoch
        guard epoch == guestEpoch else { return }
        let session = AuthenticationSession(
            userID: issued.userID,
            email: nil,
            accessToken: issued.accessToken,
            refreshToken: nil,
            expiresAt: issued.expiresAt,
            provider: .email,
            createdAt: Date(),
            lastRefreshedAt: nil
        )
        let manager = environment.authentication.manager
        guard epoch == guestEpoch else { return }
        // A real sign-in session has a refresh token. Never replace it with a guest bearer.
        guard manager.sessionManagerForNetworking.currentSession?.refreshToken == nil else { return }
        manager.suppressGoTrueRefreshForGuestSession()
        manager.sessionManagerForNetworking.installEphemeral(session)
        guard epoch == guestEpoch else {
            manager.sessionManagerForNetworking.clearMemory()
            return
        }
        guestSessionInstalled = true
        scheduleGuestReissue(expiresAt: issued.expiresAt)
        await activateGuestNetworking()
    }

    /// Opens authenticated networking for this guest token without ending that same generation.
    private func activateGuestNetworking() async {
        await guestNetworkBoundary?.value
        let generation = AuthLifecycleGeneration.bump()
        guestNetworkGeneration = generation
        AuthLifecycleTrace.log(
            operation: "guest.install.begin",
            authGeneration: generation,
            sessionGeneration: generation,
            phase: "guest",
            decision: "allowed",
            reason: "installingGuestSession"
        )
        await NetworkConcurrencyCoordinator.shared.markAuthenticatedSessionActive(
            authGeneration: generation
        )
        AuthLifecycleTrace.log(
            operation: "guest.install.complete",
            authGeneration: generation,
            sessionGeneration: generation,
            phase: "guest",
            decision: "allowed",
            reason: "guestSessionStable"
        )
    }

    private func scheduleGuestReissue(expiresAt: Date?) {
        let existing = guestRenewalTask
        guestRenewalTask = nil
        guard let expiresAt else {
            existing?.cancel()
            return
        }
        let delay = expiresAt.timeIntervalSinceNow - 60
        guard delay > 0 else {
            existing?.cancel()
            return
        }
        let task = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            _ = await self.renewExpiredGuestSession()
        }
        guestRenewalTask = task
        existing?.cancel()
    }

    /// Legacy bundled demo entry. Explore as Guest does not call this.
    func enterBundledDemoExplore() {
        guard !isDemoExperienceActive else { return }
        guard environment.authentication.manager.state.isUnauthenticatedForDemoEntry else { return }

        preDemoEnvironment = environment
        isDemoExperienceActive = true
        AuthLandingInstallState.shared.recordLoggedOutAuthLandingPresented()
        DemoExperienceSupport.setExploreLiveCommunityReadsActive(true)

        let configuration = environment.configuration
        let demoEnvironment = CompositionRoot.buildExploreDemoEnvironment(
            configuration: configuration,
            featureFlags: environment.featureFlags,
            lifecycle: environment.lifecycle,
            themeManager: environment.themeManager,
            navigation: environment.navigation,
            authentication: environment.authentication
        )

        SessionScopedCaches.invalidate(
            currentUserProfile: environment.currentUserProfile,
            data: environment.data
        )
        // Invalidate locks the viewer gate. Re-bind the local demo identity so
        // dashboard and other session-scoped surfaces can render bundled data.
        SessionViewerGate.shared.bind(DemoExperienceSupport.profileID.rawValue)
        demoEnvironment.navigation.coordinator.markExploreExperience()
        let cached = DemoSnapshotStore.shared.activateCachedSnapshot()
        let cachedVersion = cached?.version
        DemoSnapshotLog.event("entry cached=\(cachedVersion.map(String.init) ?? "none") source=\(cached == nil ? "bundled" : "disk")")
        let snapshotDatabase = demoEnvironment.data.supabase.database
        let demoData = demoEnvironment.data
        Task {
            let result = await DemoSnapshotStore.shared.refresh {
                try await snapshotDatabase.rpcDataAllowingAnon(
                    functionName: "rpc_v1_demo_snapshot",
                    parametersJSON: Data("{}".utf8)
                )
            }
            self.applyRemoteDemoSnapshot(result, cachedVersion: cachedVersion, data: demoData)
        }

        ExploreSessionStore.shared.invalidate()

        environment = demoEnvironment
        bootstrapGeneration &+= 1
        StartupTrace.event("demoExplore.entered")
        ExploreModeConversionPromptCoordinator.shared.exploreModeDidEnter()
    }

    func exitDemoExplore(authIntent: DemoExitAuthIntent? = nil) {
        guard isDemoExperienceActive else { return }
        ExploreModeConversionPromptCoordinator.shared.exploreModeDidExit()
        isDemoExperienceActive = false
        DemoExperienceSupport.setExploreLiveCommunityReadsActive(false)
        guestEpoch &+= 1
        guestRenewalTask?.cancel()
        guestRenewalTask = nil
        guestReissueTask?.cancel()
        guestReissueTask = nil
        if guestSessionInstalled {
            environment.authentication.manager.sessionManagerForNetworking.clearMemory()
            guestSessionInstalled = false
            let generation = AuthLifecycleGeneration.bump()
            guestNetworkGeneration = nil
            guestNetworkBoundary = Task {
                _ = await NetworkConcurrencyCoordinator.shared.resetForAuthenticatedSessionEnd(
                    authGeneration: generation
                )
            }
        }
        DemoSnapshotStore.shared.clearMemory()
        demoExitAuthIntent = authIntent

        SessionScopedCaches.invalidate(
            currentUserProfile: environment.currentUserProfile,
            data: environment.data
        )

        if let preDemo = preDemoEnvironment {
            environment = preDemo
        }
        preDemoEnvironment = nil

        environment.navigation.coordinator.markUnauthenticated(clearPersistedNavigation: true)
        environment.currentUserProfile.clear()
        environment.profileOnboardingGate.reset()
        bootstrapGeneration &+= 1
        StartupTrace.event("demoExplore.exited")
    }

    /// A newer valid snapshot replaces the open Demo experience, not only the disk cache.
    private func applyRemoteDemoSnapshot(
        _ result: DemoSnapshotRefreshResult,
        cachedVersion: Int?,
        data: DataEnvironment
    ) {
        guard isDemoExperienceActive else { return }
        guard case .applied(let version) = result, version != cachedVersion else { return }
        DemoCanonicalDataset.seedDetailCache(data.detailCache)
        MessagesInboxStore.shared.invalidate()
        MessagingDomain.shared.invalidate()
        demoSnapshotRevision &+= 1
        DemoSnapshotLog.event("applied version=\(version) active=demo")
    }

    /// Guest entry keeps the deferred context so a later real sign-in can build a fresh production stack.
    private func completeDeferredBootstrap(retainDeferredContext: Bool) async {
        guard deferredContext != nil || environment.isDeferredBootstrapPending else { return }
        if let task = fullBootstrapTask {
            _ = await task.value
            return
        }
        guard let context = deferredContext else { return }
        let applyEpoch = guestEpoch
        let retain = retainDeferredContext
        if !retain {
            StartupTrace.event("ensureFullBootstrapComplete.started")
        }
        fullBootstrapTask = Task { @MainActor in
            StartupTrace.begin("CompositionRoot.completeDeferredBootstrap")
            let full = await CompositionRoot.completeDeferredBootstrap(context: context)
            StartupTrace.end("CompositionRoot.completeDeferredBootstrap")
            guard !retain || applyEpoch == self.guestEpoch else {
                self.fullBootstrapTask = nil
                return full
            }
            self.applyFullEnvironment(full, retainDeferredContext: retain)
            return full
        }
        _ = await fullBootstrapTask?.value
    }

    private func applyFullEnvironment(_ full: AppEnvironment, retainDeferredContext: Bool) {
        environment = full
        bootstrapGeneration &+= 1
        if !retainDeferredContext {
            deferredContext = nil
        }
        fullBootstrapTask = nil
    }

}

private extension AuthenticationState {
    var isUnauthenticatedForDemoEntry: Bool {
        switch self {
        case .unauthenticated, .failure:
            return true
        default:
            return false
        }
    }
}
