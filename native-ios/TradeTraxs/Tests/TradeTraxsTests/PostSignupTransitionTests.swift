import XCTest
@testable import TradeTraxs

@MainActor
final class PostSignupTransitionTests: XCTestCase {
    func testSignUpActivatesPostSignupTransition() async throws {
        let navigation = CompositionRoot.bootstrapNavigation()
        let auth = CompositionRoot.bootstrapAuthenticationForTests(navigation: navigation)
        _ = auth.manager.prepareColdLaunch()
        XCTAssertFalse(auth.coordinator.postSignupTransition.isObscuringAuthRoot)

        try await auth.coordinator.signUp(
            email: "new-signup@tradetraxs.com",
            password: "password1",
            fullName: "New Signup"
        )

        XCTAssertTrue(auth.manager.state.isAuthenticated)
        XCTAssertTrue(auth.coordinator.postSignupTransition.isObscuringAuthRoot)
        XCTAssertEqual(
            auth.coordinator.postSignupTransition.phase,
            .creatingAccount
        )
    }

    func testSignInDoesNotActivatePostSignupTransition() async throws {
        let auth = CompositionRoot.bootstrapAuthenticationForTests()
        _ = auth.manager.prepareColdLaunch()
        try await auth.coordinator.signIn(email: "a@b.com", password: "password1")
        XCTAssertFalse(auth.coordinator.postSignupTransition.isObscuringAuthRoot)
    }

    func testLogoutClearsPostSignupTransition() async throws {
        let auth = CompositionRoot.bootstrapAuthenticationForTests()
        _ = auth.manager.prepareColdLaunch()
        try await auth.coordinator.signUp(
            email: "logout-signup@tradetraxs.com",
            password: "password1",
            fullName: "Logout Signup"
        )
        XCTAssertTrue(auth.coordinator.postSignupTransition.isObscuringAuthRoot)
        await auth.coordinator.logout()
        XCTAssertFalse(auth.coordinator.postSignupTransition.isObscuringAuthRoot)
    }

    func testPostSignupSessionRepairRestoresAuthenticatedNavigation() async throws {
        let navigation = CompositionRoot.bootstrapNavigation()
        let auth = CompositionRoot.bootstrapAuthenticationForTests(navigation: navigation)
        _ = auth.manager.prepareColdLaunch()
        try await auth.coordinator.signUp(
            email: "race@tradetraxs.com",
            password: "password1",
            fullName: "Race User"
        )
        XCTAssertTrue(auth.coordinator.postSignupTransition.isObscuringAuthRoot)
        navigation.coordinator.markUnauthenticated()
        XCTAssertEqual(navigation.store.sessionPhase, .unauthenticated)
        auth.coordinator.syncNavigation(with: auth.manager.state)
        XCTAssertEqual(navigation.store.sessionPhase, .authenticated)
    }

    func testCreatingAccountClearsWhenAuthenticatedDestinationIsAlreadyReady() {
        let store = PostSignupTransitionStore()
        store.beginCreatingAccount()
        store.releaseCoverIfAuthenticatedDestinationReady(gatePhase: .complete)
        XCTAssertFalse(store.isObscuringAuthRoot)
        XCTAssertEqual(store.phase, .inactive)

        store.beginCreatingAccount()
        store.releaseCoverIfAuthenticatedDestinationReady(gatePhase: .brokerOnboarding)
        XCTAssertEqual(store.phase, .inactive)
    }

    func testCreatingAccountStaysWhileBootstrapIsStillPending() {
        let store = PostSignupTransitionStore()
        store.beginCreatingAccount()
        store.releaseCoverIfAuthenticatedDestinationReady(gatePhase: .idle)
        store.releaseCoverIfAuthenticatedDestinationReady(gatePhase: .resolving)
        XCTAssertTrue(store.isObscuringAuthRoot)
        XCTAssertEqual(store.phase, .creatingAccount)
    }

    func testPostSignupStoreRetryIncrementsAttemptID() {
        let store = PostSignupTransitionStore()
        store.beginCreatingAccount()
        XCTAssertEqual(store.bootstrapAttemptID, 0)
        store.retryBootstrap()
        XCTAssertEqual(store.bootstrapAttemptID, 1)
        XCTAssertEqual(store.phase, .creatingAccount)
    }
}
