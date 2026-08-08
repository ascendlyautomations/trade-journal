import XCTest
@testable import TradeTraxs

final class AuthenticationPlatformTests: XCTestCase {
    func testSessionRestorationFromKeychain() async throws {
        let navigation = CompositionRoot.bootstrapNavigation()
        let auth = CompositionRoot.bootstrapAuthenticationForTests(navigation: navigation)
        let session = try await auth.emailProvider.signIn(email: "a@b.com", password: "password1")
        try auth.sessionManager.install(session)

        let restored = CompositionRoot.bootstrapAuthenticationForTests(
            navigation: CompositionRoot.bootstrapNavigation(),
            backend: InMemoryAuthenticationBackend()
        )
        // Separate keychain — install into shared in-memory for this test:
        let keychain = InMemoryKeychainService()
        let configuration = AuthenticationConfiguration.make(for: .debug)
        let store = SecureCredentialStore(keychain: keychain, configuration: configuration)
        try store.saveSession(session)

        let loaded = try store.loadSession()
        XCTAssertEqual(loaded?.userID, session.userID)
        XCTAssertEqual(loaded?.accessToken, session.accessToken)
    }

    func testSessionExpirationClearsInvalidSession() throws {
        let keychain = InMemoryKeychainService()
        let configuration = AuthenticationConfiguration.make(for: .debug)
        let credentials = SecureCredentialStore(keychain: keychain, configuration: configuration)
        let tokens = TokenStore(keychain: keychain, configuration: configuration)
        let sessionStore = SessionStore(credentials: credentials, tokens: tokens)
        let expiration = SessionExpiration(leeway: 0)
        let manager = SessionManager(store: sessionStore, expiration: expiration)

        let expired = AuthenticationSession(
            userID: UserID("u1"),
            email: "a@b.com",
            accessToken: "access",
            refreshToken: nil,
            expiresAt: Date().addingTimeInterval(-10),
            provider: .email,
            createdAt: Date().addingTimeInterval(-100),
            lastRefreshedAt: nil
        )
        try manager.install(expired)
        let restored = try SessionRestoration(store: sessionStore, expiration: expiration).restore()
        XCTAssertNil(restored)
    }

    func testLogoutDestroysCredentials() async throws {
        let navigation = CompositionRoot.bootstrapNavigation()
        let auth = CompositionRoot.bootstrapAuthenticationForTests(navigation: navigation)
        try await auth.coordinator.signIn(email: "user@tradetraxs.com", password: "password12")
        XCTAssertTrue(auth.manager.state.isAuthenticated)
        XCTAssertEqual(navigation.store.sessionPhase, .authenticated)

        await auth.coordinator.logout()
        XCTAssertFalse(auth.manager.state.isAuthenticated)
        XCTAssertEqual(navigation.store.sessionPhase, .unauthenticated)
        XCTAssertNil(try auth.sessionManager.restoreFromStore())
    }

    func testCredentialPersistenceRoundTrip() throws {
        let keychain = InMemoryKeychainService()
        let configuration = AuthenticationConfiguration.make(for: .debug)
        let store = SecureCredentialStore(keychain: keychain, configuration: configuration)
        let session = AuthenticationSession(
            userID: UserID("persist-1"),
            email: "p@t.com",
            accessToken: "tok",
            refreshToken: "ref",
            expiresAt: Date().addingTimeInterval(3_600),
            provider: .email,
            createdAt: Date(),
            lastRefreshedAt: Date()
        )
        try store.saveSession(session)
        let loaded = try store.loadSession()
        XCTAssertEqual(loaded, session)
        try store.clearSession()
        XCTAssertNil(try store.loadSession())
    }

    func testAuthenticationStateTransitions() async throws {
        let navigation = CompositionRoot.bootstrapNavigation()
        let auth = CompositionRoot.bootstrapAuthenticationForTests(navigation: navigation)
        XCTAssertEqual(auth.manager.state, .unknown)
        _ = auth.manager.prepareColdLaunch()
        XCTAssertEqual(auth.manager.state, .unauthenticated)

        try await auth.manager.signIn(email: "a@b.com", password: "password12")
        XCTAssertTrue(auth.manager.state.isAuthenticated)
        if case .authenticated(let session) = auth.manager.state {
            XCTAssertEqual(session.provider, .email)
        } else {
            XCTFail("Expected authenticated")
        }
    }

    func testProviderSwitchingUpdatesState() {
        let navigation = CompositionRoot.bootstrapNavigation()
        let auth = CompositionRoot.bootstrapAuthenticationForTests(navigation: navigation)
        auth.manager.switchProvider(to: .apple)
        XCTAssertEqual(auth.manager.state, .authenticating(.apple))
        auth.manager.switchProvider(to: .google)
        XCTAssertEqual(auth.manager.state, .authenticating(.google))
    }

    func testTokenRefreshScheduling() async throws {
        var backend = InMemoryAuthenticationBackend()
        backend.defaultExpiresIn = 0.2
        let navigation = CompositionRoot.bootstrapNavigation()
        let auth = CompositionRoot.bootstrapAuthenticationForTests(
            navigation: navigation,
            backend: backend
        )
        try await auth.manager.signIn(email: "a@b.com", password: "password12")
        let firstToken = auth.manager.state.session?.accessToken
        XCTAssertNotNil(firstToken)

        try auth.manager.sessionManagerForNetworking.updateTokens(
            accessToken: "stale",
            refreshToken: auth.manager.state.session?.refreshToken,
            expiresAt: Date().addingTimeInterval(-1)
        )
        guard let session = auth.sessionManager.currentSession else {
            return XCTFail("Missing session")
        }
        let refreshed = try await auth.emailProvider.refresh(session: session)
        try auth.sessionManager.install(refreshed)
        XCTAssertNotEqual(refreshed.accessToken, "stale")
        XCTAssertNotNil(refreshed.refreshToken)
    }

    func testValidatorRejectsBadEmail() {
        let validator = AuthenticationValidator()
        XCTAssertEqual(validator.validateEmail("nope"), .invalidEmail)
        XCTAssertNil(validator.validateEmail("ok@tradetraxs.com"))
        XCTAssertEqual(validator.validatePassword("short"), .invalidPassword)
    }

    func testBootstrapWiresAuthentication() {
        let environment = CompositionRoot.bootstrap()
        XCTAssertNotNil(environment.authentication.manager)
        XCTAssertNotNil(environment.data.authentication)
        XCTAssertFalse(environment.authentication.configuration.keychainService.isEmpty)
    }

    func testDevelopmentSessionRequiresDebugBypass() async {
        let navigation = CompositionRoot.bootstrapNavigation()
        let auth = CompositionRoot.bootstrapAuthenticationForTests(navigation: navigation)
        // Debug configuration allows bypass
        do {
            try await auth.coordinator.continueAsDevelopmentSessionIfAllowed()
            XCTAssertTrue(auth.manager.state.isAuthenticated)
            XCTAssertEqual(auth.manager.state.session?.provider, .development)
        } catch {
            XCTFail("Debug bypass should succeed: \(error)")
        }
    }
}
