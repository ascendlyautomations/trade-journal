import XCTest
@testable import TradeTraxs

@MainActor
final class AuthRootStateMachineTests: XCTestCase {
    func testColdLaunchWithoutSessionShowsLogin() {
        let navigation = CompositionRoot.bootstrapNavigation()
        let auth = CompositionRoot.bootstrapAuthenticationForTests(navigation: navigation)
        _ = auth.manager.prepareColdLaunch()
        auth.coordinator.syncNavigation(with: auth.manager.state)
        XCTAssertEqual(auth.manager.state, .unauthenticated)
        XCTAssertEqual(navigation.store.sessionPhase, .unauthenticated)
    }

    func testRestoredSessionShowsAuthenticatedShell() throws {
        let navigation = CompositionRoot.bootstrapNavigation()
        let auth = CompositionRoot.bootstrapAuthenticationForTests(navigation: navigation)
        let session = AuthenticationSession(
            userID: UserID("restore-user"),
            email: "restore@tradetraxs.com",
            accessToken: "access",
            refreshToken: "refresh",
            expiresAt: Date().addingTimeInterval(3_600),
            provider: .email,
            createdAt: Date(),
            lastRefreshedAt: Date()
        )
        try auth.sessionManager.install(session)
        _ = auth.manager.prepareColdLaunch()
        auth.coordinator.syncNavigation(with: auth.manager.state)
        XCTAssertTrue(auth.manager.state.isAuthenticated)
        XCTAssertEqual(navigation.store.sessionPhase, .authenticated)
    }

    func testSuccessfulSignInMarksAuthenticatedShell() async throws {
        let navigation = CompositionRoot.bootstrapNavigation()
        let auth = CompositionRoot.bootstrapAuthenticationForTests(navigation: navigation)
        _ = auth.manager.prepareColdLaunch()
        try await auth.coordinator.signIn(email: "a@b.com", password: "password1")
        XCTAssertTrue(auth.manager.state.isAuthenticated)
        XCTAssertEqual(navigation.store.sessionPhase, .authenticated)
    }

    func testSignInFailureKeepsLoginInteractive() async {
        let navigation = CompositionRoot.bootstrapNavigation()
        let auth = CompositionRoot.bootstrapAuthenticationForTests(navigation: navigation)
        _ = auth.manager.prepareColdLaunch()
        do {
            try await auth.coordinator.signIn(email: "", password: "password1")
            XCTFail("Expected sign-in to fail")
        } catch {
            XCTAssertFalse(auth.manager.state.isAuthenticated)
            XCTAssertEqual(navigation.store.sessionPhase, .unauthenticated)
        }

        let viewModel = LoginViewModel(
            authenticationCoordinator: auth.coordinator,
            allowsDevelopmentBypass: false
        )
        viewModel.email = "retry@tradetraxs.com"
        viewModel.password = "password1"
        await viewModel.submit()
        XCTAssertTrue(auth.manager.state.isAuthenticated)
        XCTAssertFalse(viewModel.isSubmitting)
    }

    func testStaleSignInAttemptCannotOverwriteNewerSuccess() async throws {
        let navigation = CompositionRoot.bootstrapNavigation()
        let auth = CompositionRoot.bootstrapAuthenticationForTests(navigation: navigation)
        _ = auth.manager.prepareColdLaunch()

        let slow = Task {
            try await Task.sleep(nanoseconds: 200_000_000)
            try await auth.coordinator.signIn(email: "slow@tradetraxs.com", password: "password1")
        }
        try await auth.coordinator.signIn(email: "fast@tradetraxs.com", password: "password1")
        XCTAssertEqual(navigation.store.sessionPhase, .authenticated)
        _ = try? await slow.value
        XCTAssertEqual(navigation.store.sessionPhase, .authenticated)
    }

    func testAuthenticatedSessionSurvivesProfileBootstrapFailure() async throws {
        let navigation = CompositionRoot.bootstrapNavigation()
        let auth = CompositionRoot.bootstrapAuthenticationForTests(navigation: navigation)
        try await auth.coordinator.signIn(email: "a@b.com", password: "password1")
        XCTAssertEqual(navigation.store.sessionPhase, .authenticated)

        let bootstrap = AppBootstrapState()
        bootstrap.beginLoading()
        bootstrap.markFailedRecoverable(message: "Profile unavailable")

        XCTAssertTrue(auth.manager.state.isAuthenticated)
        XCTAssertEqual(navigation.store.sessionPhase, .authenticated)
        XCTAssertEqual(bootstrap.phase, .failedRecoverable)
    }

    func testLogoutClearsAuthenticatedShell() async throws {
        let navigation = CompositionRoot.bootstrapNavigation()
        let auth = CompositionRoot.bootstrapAuthenticationForTests(navigation: navigation)
        try await auth.coordinator.signIn(email: "a@b.com", password: "password1")
        await auth.coordinator.logout()
        XCTAssertFalse(auth.manager.state.isAuthenticated)
        XCTAssertEqual(navigation.store.sessionPhase, .unauthenticated)
    }

    func testSignInAfterLogoutSucceeds() async throws {
        let navigation = CompositionRoot.bootstrapNavigation()
        let auth = CompositionRoot.bootstrapAuthenticationForTests(navigation: navigation)
        try await auth.coordinator.signIn(email: "a@b.com", password: "password1")
        await auth.coordinator.logout()
        try await auth.coordinator.signIn(email: "a@b.com", password: "password1")
        XCTAssertEqual(navigation.store.sessionPhase, .authenticated)
    }

    func testSyncNavigationRepairsMissedTransition() async throws {
        let navigation = CompositionRoot.bootstrapNavigation()
        let auth = CompositionRoot.bootstrapAuthenticationForTests(navigation: navigation)
        try await auth.manager.signIn(email: "a@b.com", password: "password1")
        XCTAssertEqual(navigation.store.sessionPhase, .unauthenticated)
        auth.coordinator.syncNavigation(with: auth.manager.state)
        XCTAssertEqual(navigation.store.sessionPhase, .authenticated)
    }

    func testAppBootstrapStateResetOnLogoutInvalidation() {
        let bootstrap = AppBootstrapState()
        bootstrap.beginLoading()
        bootstrap.markFailedRecoverable(message: "offline")
        bootstrap.reset()
        XCTAssertEqual(bootstrap.phase, .idle)
        XCTAssertNil(bootstrap.lastErrorMessage)
    }
}
