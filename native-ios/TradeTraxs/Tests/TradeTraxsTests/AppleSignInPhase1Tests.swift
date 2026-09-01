import XCTest
@testable import TradeTraxs

final class AppleSignInPhase1Tests: XCTestCase {
    func testFirstLoginCredentialCapturesNameAndEmail() async throws {
        let payload = AppleIDCredentialPayload(
            idToken: "token.first",
            nonce: "raw-nonce",
            fullName: "Alex Morgan",
            email: "alex@privaterelay.appleid.com"
        )
        let result = try await makeAppleProvider().signIn(credential: payload)
        XCTAssertEqual(result.firstLoginHint?.fullName, "Alex Morgan")
        XCTAssertEqual(result.firstLoginHint?.email, "alex@privaterelay.appleid.com")
        XCTAssertEqual(result.session.provider, .apple)
    }

    func testReturningCredentialWithoutNameProducesNoHint() async throws {
        let payload = AppleIDCredentialPayload(
            idToken: "token.returning",
            nonce: "raw-nonce",
            fullName: nil,
            email: nil
        )
        let result = try await makeAppleProvider().signIn(credential: payload)
        XCTAssertNil(result.firstLoginHint)
    }

    func testSuccessfulIDTokenAuthentication() async throws {
        let backend = InMemoryAuthenticationBackend()
        let provider = AppleSignInProvider(
            backend: backend,
            credentialSource: StaticAppleCredentialSource(
                payload: AppleIDCredentialPayload(
                    idToken: "valid-token",
                    nonce: "nonce",
                    fullName: nil,
                    email: nil
                )
            )
        )
        let session = try await provider.signIn()
        XCTAssertEqual(session.provider, .apple)
        XCTAssertFalse(session.accessToken.isEmpty)
    }

    func testBootstrapDoesNotOverwriteExistingRealProfileName() async throws {
        let profileID = ProfileID(UUID().uuidString)
        let profiles = RecordingProfileRepository(
            existing: makeProfile(
                id: profileID,
                username: "alex_m",
                displayName: "Alex Morgan"
            )
        )
        let backend = InMemoryAuthenticationBackend()
        let bootstrap = AuthenticatedSessionBootstrap(profiles: profiles, backend: backend)
        let session = AuthenticationSession(
            userID: UserID(profileID.rawValue),
            email: "alex@privaterelay.appleid.com",
            accessToken: "access-token",
            refreshToken: "refresh-token",
            expiresAt: Date().addingTimeInterval(3600),
            provider: .apple,
            createdAt: Date(),
            lastRefreshedAt: Date()
        )

        try await bootstrap.finalize(
            session: session,
            firstLoginHint: OAuthFirstLoginHint.normalized(fullName: "Different Name", email: nil)
        )

        XCTAssertEqual(profiles.ensureCallCount, 1)
        XCTAssertEqual(profiles.updateCallCount, 0)
        XCTAssertTrue(backend.recordedMetadataUpdates.isEmpty)
    }

    func testBootstrapPersistsAppleNameForPlaceholderProfile() async throws {
        let profileID = ProfileID(UUID().uuidString)
        let profiles = RecordingProfileRepository(
            existing: makeProfile(
                id: profileID,
                username: "user_abcd1234",
                displayName: "New User"
            )
        )
        let backend = InMemoryAuthenticationBackend()
        let bootstrap = AuthenticatedSessionBootstrap(profiles: profiles, backend: backend)
        let session = AuthenticationSession(
            userID: UserID(profileID.rawValue),
            email: "alex@privaterelay.appleid.com",
            accessToken: "access-token",
            refreshToken: "refresh-token",
            expiresAt: Date().addingTimeInterval(3600),
            provider: .apple,
            createdAt: Date(),
            lastRefreshedAt: Date()
        )

        try await bootstrap.finalize(
            session: session,
            firstLoginHint: OAuthFirstLoginHint.normalized(fullName: "Alex Morgan", email: nil)
        )

        XCTAssertEqual(profiles.updateCallCount, 1)
        XCTAssertEqual(profiles.lastUpdatedName, "Alex Morgan")
        XCTAssertEqual(backend.recordedMetadataUpdates.count, 1)
        XCTAssertEqual(backend.recordedMetadataUpdates.first?.metadata["full_name"], "Alex Morgan")
    }

    func testProfileEnsureIsIdempotent() async throws {
        let profileID = ProfileID(UUID().uuidString)
        let profiles = RecordingProfileRepository(
            existing: makeProfile(
                id: profileID,
                username: "user_abcd1234",
                displayName: "New User"
            )
        )
        let bootstrap = AuthenticatedSessionBootstrap(
            profiles: profiles,
            backend: InMemoryAuthenticationBackend()
        )
        let session = AuthenticationSession(
            userID: UserID(profileID.rawValue),
            email: nil,
            accessToken: "access-token",
            refreshToken: "refresh-token",
            expiresAt: Date().addingTimeInterval(3600),
            provider: .apple,
            createdAt: Date(),
            lastRefreshedAt: Date()
        )

        try await bootstrap.finalize(session: session, firstLoginHint: nil)
        try await bootstrap.finalize(session: session, firstLoginHint: nil)

        XCTAssertEqual(profiles.ensureCallCount, 2)
        XCTAssertEqual(profiles.insertCallCount, 0)
    }

    func testAppleCancellationMapsToSilentAuthError() {
        let mapped = UserFacingError.map(AuthenticationError.cancelled)
        XCTAssertEqual(mapped.title, "Cancelled")
    }

    func testAuthenticationFailureSurfacesUsefulCopy() {
        let misconfigured = UserFacingError.map(AuthenticationError.providerMisconfigured(.apple))
        XCTAssertTrue(misconfigured.message.contains("not configured"))

        let invalidToken = UserFacingError.map(AuthenticationError.providerTokenInvalid(.apple))
        XCTAssertTrue(invalidToken.message.contains("verify"))
    }

    func testManagerSignInWithAppleCredentialRunsBootstrap() async throws {
        let navigation = CompositionRoot.bootstrapNavigation()
        let backend = InMemoryAuthenticationBackend()
        let auth = CompositionRoot.bootstrapAuthenticationForTests(
            navigation: navigation,
            backend: backend
        )
        let profiles = RecordingProfileRepository(existing: nil)
        auth.manager.sessionBootstrap = AuthenticatedSessionBootstrap(
            profiles: profiles,
            backend: backend
        )

        let apple = auth.appleProvider as! AppleSignInProvider
        _ = apple

        try await auth.manager.signInWithApple(
            credential: AppleIDCredentialPayload(
                idToken: "token",
                nonce: "nonce",
                fullName: "Jamie Lee",
                email: "jamie@privaterelay.appleid.com"
            )
        )

        XCTAssertTrue(auth.manager.state.isAuthenticated)
        XCTAssertEqual(profiles.ensureCallCount, 1)
        XCTAssertEqual(profiles.insertCallCount, 1)
        XCTAssertEqual(profiles.lastUpdatedName, "Jamie Lee")
    }

    func testProfileDisplayNamePolicyTreatsNewUserAsPlaceholder() {
        XCTAssertTrue(ProfileDisplayNamePolicy.isPlaceholder("New User"))
        XCTAssertTrue(ProfileDisplayNamePolicy.isPlaceholder(""))
        XCTAssertFalse(ProfileDisplayNamePolicy.isPlaceholder("Alex Morgan"))
    }

    // MARK: - Helpers

    private func makeAppleProvider() -> AppleSignInProvider {
        AppleSignInProvider(backend: InMemoryAuthenticationBackend())
    }

    private func makeProfile(
        id: ProfileID,
        username: String,
        displayName: String
    ) -> Profile {
        Profile(
            id: id,
            userID: UserID(id.rawValue),
            username: username,
            displayName: displayName,
            bio: nil,
            avatar: nil,
            traderType: nil,
            tradingStyle: nil,
            primaryMarket: nil,
            startedTradingAt: nil,
            isPrivate: false,
            isCreator: false,
            createdAt: Date()
        )
    }
}

private final class RecordingProfileRepository: ProfileRepository, @unchecked Sendable {
    private var stored: Profile?
    private(set) var ensureCallCount = 0
    private(set) var insertCallCount = 0
    private(set) var updateCallCount = 0
    private(set) var lastUpdatedName: String?

    init(existing: Profile?) {
        stored = existing
    }

    func currentUser() async throws -> User {
        throw AppError.notImplemented(feature: "currentUser")
    }

    func profile(id: ProfileID) async throws -> Profile {
        guard let stored, stored.id == id else {
            throw AppError.domain(.notFound(entity: "profile", id: id.rawValue))
        }
        return stored
    }

    func profile(username: String) async throws -> Profile {
        throw AppError.notImplemented(feature: "profile(username:)")
    }

    func ensureProfileExists(for profileID: ProfileID) async throws -> Profile {
        ensureCallCount += 1
        if let stored, stored.id == profileID {
            return stored
        }
        insertCallCount += 1
        let created = makeProfile(
            id: profileID,
            username: "user_\(profileID.rawValue.prefix(8))",
            displayName: "New User"
        )
        stored = created
        return created
    }

    func updateProfile(_ profile: Profile) async throws -> Profile {
        updateCallCount += 1
        lastUpdatedName = profile.displayName
        stored = profile
        return profile
    }

    func stats(for profileID: ProfileID) async throws -> ProfileStats {
        throw AppError.notImplemented(feature: "stats")
    }

    func wallPosts(for profileID: ProfileID, page: PageRequest) async throws -> CursorPage<Post> {
        throw AppError.notImplemented(feature: "wallPosts")
    }

    func wallPost(id: PostID) async throws -> Post {
        throw AppError.notImplemented(feature: "wallPost")
    }

    func followState(from viewer: ProfileID, to target: ProfileID) async throws -> FollowState {
        throw AppError.notImplemented(feature: "followState")
    }

    func follow(from viewer: ProfileID, to target: ProfileID) async throws {
        throw AppError.notImplemented(feature: "follow")
    }

    func unfollow(from viewer: ProfileID, to target: ProfileID) async throws {
        throw AppError.notImplemented(feature: "unfollow")
    }

    func followers(of profileID: ProfileID, page: PageRequest) async throws -> CursorPage<Profile> {
        throw AppError.notImplemented(feature: "followers")
    }

    func following(of profileID: ProfileID, page: PageRequest) async throws -> CursorPage<Profile> {
        throw AppError.notImplemented(feature: "following")
    }

    func creator(for profileID: ProfileID) async throws -> Creator? {
        nil
    }

    private func makeProfile(
        id: ProfileID,
        username: String,
        displayName: String
    ) -> Profile {
        Profile(
            id: id,
            userID: UserID(id.rawValue),
            username: username,
            displayName: displayName,
            bio: nil,
            avatar: nil,
            traderType: nil,
            tradingStyle: nil,
            primaryMarket: nil,
            startedTradingAt: nil,
            isPrivate: false,
            isCreator: false,
            createdAt: Date()
        )
    }
}
