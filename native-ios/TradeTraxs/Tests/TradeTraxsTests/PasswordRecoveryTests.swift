import XCTest
@testable import TradeTraxs

@MainActor
final class PasswordRecoveryTests: XCTestCase {
    private var verifiers: MemoryPasswordRecoveryVerifierStore!

    override func setUp() async throws {
        verifiers = MemoryPasswordRecoveryVerifierStore()
        PasswordRecoveryVerifierStore.replaceForTesting(verifiers)
        PasswordRecoveryInbox.shared.resetForTesting()
        DeepLinkLaunchTrace.resetDuplicateGuardForTesting()
    }

    override func tearDown() async throws {
        PasswordRecoveryInbox.shared.resetForTesting()
        PasswordRecoveryVerifierStore.useProductionStoreForTesting()
        verifiers = nil
    }

    func testValidRecoveryLinkPreservesCode() {
        let link = PasswordRecoveryLink.parse(
            URL(string: "https://www.tradetraxs.com/reset-password?code=recovery-code")!
        )
        guard case .pkceCode(let code) = link else {
            return XCTFail("Expected a PKCE recovery code")
        }
        XCTAssertEqual(code, "recovery-code")
    }

    func testFragmentRecoveryTokensArePreserved() {
        let access = jwt(subject: "user-1")
        let url = URL(string: "https://www.tradetraxs.com/reset-password#access_token=\(access)&refresh_token=refresh-1&type=recovery")!
        guard case .implicit(let token, let refresh) = PasswordRecoveryLink.parse(url) else {
            return XCTFail("Expected implicit recovery tokens")
        }
        XCTAssertEqual(token, access)
        XCTAssertEqual(refresh, "refresh-1")
        XCTAssertEqual(PasswordRecoveryLink.implicitSession(accessToken: access, refreshToken: refresh)?.userID.rawValue, "user-1")
    }

    func testInvalidOrExpiredLinkUsesFriendlyCopy() async {
        let url = URL(string: "https://www.tradetraxs.com/reset-password?error_code=otp_expired&error_description=Email%20link%20is%20invalid%20or%20has%20expired")!
        XCTAssertEqual(PasswordRecoveryLink.parse(url), .invalid)
        let model = PasswordRecoveryModel()
        model.begin(.invalid)
        await waitUntil { model.phase != .verifying }
        XCTAssertEqual(model.phase, .invalid(PasswordRecoveryLink.invalidMessage))
        if case .invalid(let message) = model.phase {
            XCTAssertFalse(message.contains("otp"))
            XCTAssertFalse(message.contains("Email link"))
        }
    }

    func testColdLoggedOutResetLinkDoesNotOpenEmailForm() {
        let store = NavigationStore(state: .initial)
        let coordinator = NavigationCoordinator(store: store)
        let router = DeepLinkRouter()
        let url = URL(string: "https://www.tradetraxs.com/reset-password?code=cold-code")!
        XCTAssertTrue(router.route(url: url, using: coordinator, store: store))
        XCTAssertEqual(store.sessionPhase, .unauthenticated)
        XCTAssertTrue(store.paths.auth.isEmpty)
        guard case .pkceCode(let code) = PasswordRecoveryInbox.shared.take() else {
            return XCTFail("Cold launch dropped the recovery code")
        }
        XCTAssertEqual(code, "cold-code")
    }

    func testWarmSignedInResetLinkDoesNotDemoteShell() {
        let store = NavigationStore(state: .initial)
        let coordinator = NavigationCoordinator(store: store)
        coordinator.markAuthenticated()
        let router = DeepLinkRouter()
        let url = URL(string: "https://www.tradetraxs.com/reset-password?code=warm-code")!
        XCTAssertTrue(router.route(url: url, using: coordinator, store: store))
        XCTAssertEqual(store.sessionPhase, .authenticated)
        XCTAssertNil(store.pendingAfterAuth)
        XCTAssertTrue(store.paths.auth.isEmpty)
        guard case .pkceCode = PasswordRecoveryInbox.shared.take() else {
            return XCTFail("Signed-in recovery link was ignored")
        }
    }

    func testPasswordMismatchDoesNotUpdate() async {
        let client = ScriptedPasswordRecoveryClient()
        let model = configuredModel(client: client)
        verifiers.value = "verifier"
        model.begin(.pkceCode("code-1"))
        await waitUntil { model.phase == .ready }
        await model.save(password: "password12", confirmation: "password13")
        XCTAssertEqual(model.formError, "Passwords do not match.")
        XCTAssertEqual(client.updateCount, 0)
        XCTAssertEqual(client.adoptCount, 0)
    }

    func testUpdateFailureStaysOnFormWithoutAdoptingSession() async {
        let client = ScriptedPasswordRecoveryClient()
        client.updateError = AuthenticationError.unknown("database error jwt secret")
        let model = configuredModel(client: client)
        verifiers.value = "verifier"
        model.begin(.pkceCode("code-1"))
        await waitUntil { model.phase == .ready }
        await model.save(password: "password12", confirmation: "password12")
        XCTAssertEqual(model.phase, .ready)
        XCTAssertEqual(model.formError, PasswordRecoveryLink.updateFailedMessage)
        XCTAssertFalse(model.formError?.contains("jwt") == true)
        XCTAssertEqual(client.adoptCount, 0)
    }

    func testSuccessfulResetAdoptsExistingSessionOnce() async {
        let client = ScriptedPasswordRecoveryClient()
        let model = configuredModel(client: client)
        verifiers.value = "verifier"
        model.begin(.pkceCode("code-1"))
        await waitUntil { model.phase == .ready }
        XCTAssertNil(verifiers.value)
        await model.save(password: "password12", confirmation: "password12")
        XCTAssertEqual(model.phase, .success(signedIn: true))
        XCTAssertEqual(client.updateCount, 1)
        XCTAssertEqual(client.adoptCount, 1)
        XCTAssertEqual(client.adoptedUserID, "user-1")
        await model.save(password: "password12", confirmation: "password12")
        XCTAssertEqual(client.updateCount, 1)
    }

    func testDoubleTapSaveUpdatesOnce() async {
        let client = ScriptedPasswordRecoveryClient()
        client.shouldHold = true
        let model = configuredModel(client: client)
        verifiers.value = "verifier"
        model.begin(.pkceCode("code-1"))
        await waitUntil { model.phase == .ready }
        let first = Task { await model.save(password: "password12", confirmation: "password12") }
        await waitUntil { client.updateCount == 1 }
        let second = Task { await model.save(password: "password12", confirmation: "password12") }
        await Task.yield()
        XCTAssertEqual(client.updateCount, 1)
        client.releaseUpdate()
        await first.value
        await second.value
        XCTAssertEqual(client.updateCount, 1)
        XCTAssertEqual(client.adoptCount, 1)
    }

    private func configuredModel(client: ScriptedPasswordRecoveryClient) -> PasswordRecoveryModel {
        let model = PasswordRecoveryModel()
        model.configure(client: client) { session in
            client.adoptCount += 1
            client.adoptedUserID = session.userID.rawValue
        }
        return model
    }

    private func waitUntil(timeout: TimeInterval = 2, _ predicate: @MainActor () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate() { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    private func jwt(subject: String) -> String {
        func encoded(_ value: String) -> String {
            Data(value.utf8).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        return "\(encoded("{\"alg\":\"none\"}")).\(encoded("{\"sub\":\"\(subject)\"}")).sig"
    }
}

private final class MemoryPasswordRecoveryVerifierStore: PasswordRecoveryVerifierStoring, @unchecked Sendable {
    var value: String?
    func save(_ verifier: String) throws { value = verifier }
    func load() throws -> String? { value }
    func clear() throws { value = nil }
}

private final class ScriptedPasswordRecoveryClient: PasswordRecoveryClient, @unchecked Sendable {
    var updateCount = 0
    var adoptCount = 0
    var adoptedUserID: String?
    var updateError: Error?
    var shouldHold = false
    private var hold: CheckedContinuation<Void, Never>?
    let session = AuthenticationSession(
        userID: UserID("user-1"),
        email: "trader@example.com",
        accessToken: "access-token",
        refreshToken: "refresh-token",
        expiresAt: Date().addingTimeInterval(3600),
        provider: .email,
        createdAt: Date(),
        lastRefreshedAt: Date()
    )

    func exchangePKCE(code: String, verifier: String) async throws -> AuthenticationSession {
        _ = (code, verifier)
        return session
    }

    func verifyTokenHash(_ tokenHash: String) async throws -> AuthenticationSession {
        _ = tokenHash
        return session
    }

    func updatePassword(accessToken: String, newPassword: String) async throws {
        _ = (accessToken, newPassword)
        updateCount += 1
        if let updateError { throw updateError }
        guard shouldHold else { return }
        await withCheckedContinuation { continuation in
            hold = continuation
        }
    }

    func releaseUpdate() {
        hold?.resume()
        hold = nil
    }
}
