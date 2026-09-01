import XCTest
@testable import TradeTraxs

/// In-memory navigation restorer for deterministic restoration tests.
final class InMemoryNavigationStateRestorer: NavigationStateRestoring, @unchecked Sendable {
    var stored: NavigationState?

    func load() -> NavigationState? { stored }

    func save(_ state: NavigationState) {
        stored = state
    }

    func clear() {
        stored = nil
    }
}

@MainActor
final class AuthSessionRestorationTests: XCTestCase {
    override func tearDown() {
        BackendV2FeatureFlags.resetFlagsForTests()
        let gateClear = Task { await SessionNetworkGate.shared.markUnauthenticated() }
        let flightClear = Task { await AuthRefreshSingleFlight.shared.cancelAll() }
        _ = (gateClear, flightClear)
        super.tearDown()
    }

    private func makeAuth(
        backend: InMemoryAuthenticationBackend = InMemoryAuthenticationBackend(),
        restorer: InMemoryNavigationStateRestorer = InMemoryNavigationStateRestorer()
    ) -> (AuthenticationEnvironment, NavigationEnvironment, InMemoryNavigationStateRestorer) {
        let bootstrap = NavigationRestorationPolicy.bootstrapState(restorer: restorer)
        let store = NavigationStore(state: bootstrap.shellState)
        let coordinator = NavigationCoordinator(store: store)
        let navigation = NavigationEnvironment(
            store: store,
            coordinator: coordinator,
            stateRestorer: restorer
        )
        if let deferred = bootstrap.deferredAuthenticatedPaths {
            navigation.deferAuthenticatedSnapshot(deferred)
        }
        let auth = CompositionRoot.bootstrapAuthenticationForTests(navigation: navigation, backend: backend)
        return (auth, navigation, restorer)
    }

    private func expiredSession(refreshToken: String? = "refresh-1") -> AuthenticationSession {
        AuthenticationSession(
            userID: UserID("user-restore"),
            email: "restore@tradetraxs.com",
            accessToken: "stale-access",
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(-120),
            provider: .email,
            createdAt: Date(),
            lastRefreshedAt: nil
        )
    }

    private func validSession(userID: String = "user-valid") -> AuthenticationSession {
        AuthenticationSession(
            userID: UserID(userID),
            email: "valid@tradetraxs.com",
            accessToken: "valid-access",
            refreshToken: "valid-refresh",
            expiresAt: Date().addingTimeInterval(3600),
            provider: .email,
            createdAt: Date(),
            lastRefreshedAt: Date()
        )
    }

    // MARK: - Valid session

    func testValidSessionRestoresAuthenticatedShell() throws {
        let (auth, navigation, _) = makeAuth()
        try auth.sessionManager.install(validSession())
        _ = auth.manager.prepareColdLaunch()
        auth.coordinator.syncNavigation(with: auth.manager.state)
        XCTAssertTrue(auth.manager.state.isSessionReady)
        XCTAssertEqual(navigation.store.sessionPhase, .authenticated)
    }

    // MARK: - Expired token refresh

    func testExpiredAccessTokenTriggersRefreshState() throws {
        let (auth, navigation, _) = makeAuth()
        try auth.sessionManager.install(expiredSession())
        _ = auth.manager.prepareColdLaunch()
        auth.coordinator.syncNavigation(with: auth.manager.state)
        if case .refreshing = auth.manager.state { } else {
            XCTFail("Expected refreshing, got \(auth.manager.state)")
        }
        XCTAssertEqual(navigation.store.sessionPhase, .unauthenticated)
    }

    func testSuccessfulRefreshEntersAuthenticatedShellOnce() async throws {
        var backend = InMemoryAuthenticationBackend()
        backend.refreshDelayNanoseconds = 50_000_000
        let (auth, navigation, _) = makeAuth(backend: backend)
        try auth.sessionManager.install(expiredSession())
        _ = auth.manager.prepareColdLaunch()
        auth.coordinator.syncNavigation(with: auth.manager.state)
        await auth.coordinator.bootstrapSession()
        XCTAssertTrue(auth.manager.state.isSessionReady)
        XCTAssertEqual(navigation.store.sessionPhase, .authenticated)
        XCTAssertEqual(backend.refreshCallCount, 1)
    }

    func testInvalidRefreshTokenClearsSessionAndShowsLogin() async throws {
        var backend = InMemoryAuthenticationBackend()
        backend.refreshError = .invalidCredentials
        let (auth, navigation, _) = makeAuth(backend: backend)
        try auth.sessionManager.install(expiredSession())
        _ = auth.manager.prepareColdLaunch()
        await auth.coordinator.bootstrapSession()
        XCTAssertEqual(auth.manager.state, .unauthenticated)
        XCTAssertEqual(navigation.store.sessionPhase, .unauthenticated)
        XCTAssertNil(auth.sessionManager.currentSession)
    }

    func testRevokedRefreshTokenClearsSessionAndShowsLogin() async throws {
        var backend = InMemoryAuthenticationBackend()
        backend.refreshError = .refreshFailed
        let (auth, navigation, _) = makeAuth(backend: backend)
        try auth.sessionManager.install(expiredSession())
        _ = auth.manager.prepareColdLaunch()
        await auth.coordinator.bootstrapSession()
        XCTAssertEqual(auth.manager.state, .unauthenticated)
        XCTAssertEqual(navigation.store.sessionPhase, .unauthenticated)
    }

    func testMissingRefreshTokenShowsLogin() throws {
        let (auth, navigation, _) = makeAuth()
        try auth.sessionManager.install(expiredSession(refreshToken: nil))
        _ = auth.manager.prepareColdLaunch()
        auth.coordinator.syncNavigation(with: auth.manager.state)
        XCTAssertEqual(auth.manager.state, .unauthenticated)
        XCTAssertEqual(navigation.store.sessionPhase, .unauthenticated)
    }

    // MARK: - Transient failures

    func testTransientNetworkFailureDoesNotEnterAuthenticatedShell() async throws {
        var backend = InMemoryAuthenticationBackend()
        backend.refreshError = .unknown("networkUnavailable")
        let (auth, navigation, _) = makeAuth(backend: backend)
        try auth.sessionManager.install(expiredSession())
        _ = auth.manager.prepareColdLaunch()
        await auth.coordinator.bootstrapSession()
        if case .sessionValidationFailed = auth.manager.state { } else {
            XCTFail("Expected sessionValidationFailed, got \(auth.manager.state)")
        }
        XCTAssertFalse(auth.manager.state.isSessionReady)
        XCTAssertEqual(navigation.store.sessionPhase, .unauthenticated)
    }

    func testRetryAfterTransientFailureSucceeds() async throws {
        var backend = InMemoryAuthenticationBackend()
        backend.refreshError = .unknown("networkUnavailable")
        let (auth, navigation, _) = makeAuth(backend: backend)
        try auth.sessionManager.install(expiredSession())
        _ = auth.manager.prepareColdLaunch()
        await auth.coordinator.bootstrapSession()
        backend.refreshError = nil
        await auth.coordinator.retrySessionValidation()
        XCTAssertTrue(auth.manager.state.isSessionReady)
        XCTAssertEqual(navigation.store.sessionPhase, .authenticated)
    }

    // MARK: - Stale completion / generation

    func testLateRestorationCompletionCannotOverrideRefreshFailure() async throws {
        var backend = InMemoryAuthenticationBackend()
        backend.refreshError = .invalidCredentials
        let (auth, navigation, _) = makeAuth(backend: backend)
        try auth.sessionManager.install(expiredSession())
        _ = auth.manager.prepareColdLaunch()
        await auth.coordinator.bootstrapSession()
        auth.coordinator.syncNavigation(with: .authenticated(validSession()))
        XCTAssertEqual(auth.manager.state, .unauthenticated)
        XCTAssertEqual(navigation.store.sessionPhase, .unauthenticated)
    }

    func testLateValidationCannotOverrideLogout() async throws {
        let (auth, navigation, _) = makeAuth()
        try await auth.coordinator.signIn(email: "a@b.com", password: "password1")
        await auth.coordinator.logout()
        auth.coordinator.syncNavigation(with: .authenticated(validSession()))
        XCTAssertEqual(auth.manager.state, .unauthenticated)
        XCTAssertEqual(navigation.store.sessionPhase, .unauthenticated)
    }

    // MARK: - Bootstrap gating

    func testNavigationDoesNotRestoreWhileRefreshing() throws {
        let restorer = InMemoryNavigationStateRestorer()
        var saved = NavigationState.initial
        saved.sessionPhase = .authenticated
        saved.selectedTab = .profile
        saved.profilePath = [.activity]
        restorer.stored = saved

        let (auth, navigation, _) = makeAuth(restorer: restorer)
        try auth.sessionManager.install(expiredSession())
        _ = auth.manager.prepareColdLaunch()
        auth.coordinator.syncNavigation(with: auth.manager.state)
        XCTAssertTrue(navigation.store.paths.profile.isEmpty)
        XCTAssertEqual(navigation.store.selectedTab, .profile)
        XCTAssertNotNil(navigation.deferredAuthenticatedSnapshot)
    }

    // MARK: - Terminal cleanup

    func testTerminalFailureClearsAllTabPaths() async throws {
        var backend = InMemoryAuthenticationBackend()
        backend.refreshError = .refreshFailed
        let restorer = InMemoryNavigationStateRestorer()
        var saved = NavigationState.initial
        saved.sessionPhase = .authenticated
        saved.selectedTab = .profile
        saved.profilePath = [.activity]
        saved.homePath = [.settings(.home)]
        restorer.stored = saved

        let (auth, navigation, _) = makeAuth(backend: backend, restorer: restorer)
        try auth.sessionManager.install(expiredSession())
        _ = auth.manager.prepareColdLaunch()
        await auth.coordinator.bootstrapSession()
        XCTAssertTrue(navigation.store.paths.home.isEmpty)
        XCTAssertTrue(navigation.store.paths.profile.isEmpty)
        XCTAssertNil(navigation.deferredAuthenticatedSnapshot)
        XCTAssertNil(restorer.stored)
    }

    func testSuccessfulAuthRestoresDeferredProfileActivityPath() async throws {
        let restorer = InMemoryNavigationStateRestorer()
        var saved = NavigationState.initial
        saved.sessionPhase = .authenticated
        saved.selectedTab = .profile
        saved.profilePath = [.activity]
        restorer.stored = saved

        let (auth, navigation, _) = makeAuth(restorer: restorer)
        try auth.sessionManager.install(validSession())
        _ = auth.manager.prepareColdLaunch()
        await auth.coordinator.bootstrapSession()
        XCTAssertEqual(navigation.store.sessionPhase, .authenticated)
        XCTAssertEqual(navigation.store.paths.profile, [.activity])
        XCTAssertEqual(navigation.store.selectedTab, .profile)
    }

    func testTerminalFailureRemovesProfileActivityRestoration() async throws {
        var backend = InMemoryAuthenticationBackend()
        backend.refreshError = .invalidCredentials
        let restorer = InMemoryNavigationStateRestorer()
        var saved = NavigationState.initial
        saved.sessionPhase = .authenticated
        saved.selectedTab = .profile
        saved.profilePath = [.activity]
        restorer.stored = saved

        let (auth, navigation, _) = makeAuth(backend: backend, restorer: restorer)
        try auth.sessionManager.install(expiredSession())
        _ = auth.manager.prepareColdLaunch()
        await auth.coordinator.bootstrapSession()
        XCTAssertTrue(navigation.store.paths.profile.isEmpty)
        XCTAssertNil(navigation.deferredAuthenticatedSnapshot)
    }

    // MARK: - Account isolation

    func testAccountBStateCannotAppearAfterAccountALogin() async throws {
        let (auth, navigation, _) = makeAuth()
        try await auth.coordinator.signIn(email: "a@b.com", password: "password1")
        let accountA = auth.manager.state.session?.userID
        await auth.coordinator.logout()
        try await auth.coordinator.signIn(email: "b@b.com", password: "password1")
        let accountB = auth.manager.state.session?.userID
        XCTAssertNotEqual(accountA, accountB)
        XCTAssertEqual(navigation.store.sessionPhase, .authenticated)
    }

    // MARK: - Auth flow phase

    func testRefreshingMapsToRestoringNotAuthenticated() throws {
        let (auth, _, _) = makeAuth()
        try auth.sessionManager.install(expiredSession())
        _ = auth.manager.prepareColdLaunch()
        XCTAssertEqual(auth.manager.state.authFlowPhase, .restoring)
        XCTAssertFalse(auth.manager.state.isSessionReady)
    }

    func testDuplicateRestoreDoesNotCreateMultipleRefreshCalls() async throws {
        var backend = InMemoryAuthenticationBackend()
        backend.refreshDelayNanoseconds = 100_000_000
        let (auth, _, _) = makeAuth(backend: backend)
        try auth.sessionManager.install(expiredSession())
        _ = auth.manager.prepareColdLaunch()
        async let first = auth.manager.restoreSession()
        async let second = auth.manager.restoreSession()
        await first
        await second
        XCTAssertEqual(backend.refreshCallCount, 1)
    }
}
