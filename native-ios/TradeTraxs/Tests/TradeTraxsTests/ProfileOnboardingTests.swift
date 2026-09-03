import XCTest
@testable import TradeTraxs

final class ProfileOnboardingTests: XCTestCase {
    func testOnboardingCompletedTrueBypassesGate() {
        let snapshot = ProfileOnboardingSnapshot(
            profileID: ProfileID(UUID().uuidString),
            username: nil,
            onboardingCompleted: true
        )
        XCTAssertFalse(ProfileOnboardingPolicy.profileNeedsOnboarding(snapshot))
    }

    func testFalseRequiresOnboardingEvenWithGeneratedUsername() {
        let profileID = ProfileID(UUID().uuidString)
        let generated = ProfileUsernamePolicy.generatedShellUsername(for: profileID)
        let snapshot = ProfileOnboardingSnapshot(
            profileID: profileID,
            username: generated,
            onboardingCompleted: false
        )
        XCTAssertTrue(ProfileOnboardingPolicy.profileNeedsOnboarding(snapshot))
    }

    func testMissingRequiredFieldsRequireOnboarding() {
        let snapshot = ProfileOnboardingSnapshot(
            profileID: ProfileID(UUID().uuidString),
            username: "trader1",
            onboardingCompleted: false,
            traderType: nil,
            tradingStyle: "Scalping",
            startedTrading: "2020-01-01"
        )
        XCTAssertTrue(ProfileOnboardingPolicy.profileNeedsOnboarding(snapshot))
    }

    func testCompleteFieldsStillRequireOnboardingFlag() {
        let snapshot = ProfileOnboardingSnapshot(
            profileID: ProfileID(UUID().uuidString),
            username: "trader1",
            onboardingCompleted: false,
            traderType: "Futures",
            tradingStyle: "Scalping",
            startedTrading: "2020-01-01"
        )
        XCTAssertTrue(ProfileOnboardingPolicy.profileNeedsOnboarding(snapshot))
    }

    func testUsernameValidation() {
        XCTAssertEqual(ProfileUsernamePolicy.validateNotEmpty(""), "Please choose a username.")
        XCTAssertEqual(ProfileUsernamePolicy.normalize("Bad-Name"), "badname")
        XCTAssertTrue(ProfileUsernamePolicy.isGeneratedShellUsername("user_ab12cd34", profileID: ProfileID("ab12cd34-0000-0000-0000-000000000000")))
    }

    func testGeneratedUsernameNotUsedAsPrefill() {
        let profileID = ProfileID("ab12cd34-0000-0000-0000-000000000000")
        let prefill = ProfileUsernamePolicy.onboardingPrefillUsername(
            current: ProfileUsernamePolicy.generatedShellUsername(for: profileID),
            profileID: profileID
        )
        XCTAssertEqual(prefill, "")
    }

    func testFutureStartedTradingDateRejected() {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        XCTAssertTrue(StartedTradingDatePolicy.isFuture(formatter.string(from: tomorrow)))
    }

    func testCompleteProfileOnboardingSetsFlag() async throws {
        let repo = RecordingOnboardingProfileRepository()
        let profileID = ProfileID(UUID().uuidString)
        repo.storedSnapshot = ProfileOnboardingSnapshot(
            profileID: profileID,
            username: "user_abcd1234",
            displayName: "Alex",
            onboardingCompleted: false
        )

        let profile = try await repo.completeProfileOnboarding(
            ProfileOnboardingSubmission(
                profileID: profileID,
                username: "alex_m",
                displayName: "Alex Morgan",
                bio: nil,
                tradingStyle: "Scalping",
                traderType: .futures,
                startedTrading: "2020-05-01",
                avatarURL: nil,
                primaryMarket: nil
            )
        )

        XCTAssertEqual(profile.username, "alex_m")
        XCTAssertEqual(repo.lastCompletedUsername, "alex_m")
        XCTAssertTrue(repo.storedSnapshot?.onboardingCompleted == true)
    }

    func testUsernameConflictDetectsPostgRESTValidation() {
        let error = NetworkError.validation(
            statusCode: 409,
            message: #"{"code":"23505","details":"Key (username)=(alex) already exists."}"#
        )
        XCTAssertTrue(ProfileUsernamePolicy.isProfilesUsernameConflict(error))
        XCTAssertTrue(ProfileUsernamePolicy.isProfilesUsernameConflict(AppError.transport(error)))
    }

    func testUsernameConflictMessage() {
        XCTAssertEqual(
            ProfileOnboardingErrorMapping.usernameConflictMessage,
            "That username is already taken. Try another one."
        )
    }

    @MainActor
    func testGateStoreMarksCompleteAfterSubmit() async {
        let profileID = ProfileID(UUID().uuidString)
        let repo = RecordingOnboardingProfileRepository()
        repo.storedSnapshot = ProfileOnboardingSnapshot(
            profileID: profileID,
            displayName: "Jamie",
            onboardingCompleted: false
        )
        let gate = ProfileOnboardingGateStore(
            profiles: repo,
            session: FixedSessionProvider(userID: UserID(profileID.rawValue)),
            rpc: nil,
            detailCache: nil,
            realtimeHub: nil,
            profileStore: CurrentUserProfileStore(
                profiles: repo,
                session: FixedSessionProvider(userID: UserID(profileID.rawValue)),
                imagePipeline: PlaceholderImagePipeline()
            )
        )

        let vm = makeOnboardingViewModel(snapshot: repo.storedSnapshot!, profiles: repo, gateStore: gate)
        vm.username = "jamie_t"
        vm.tradingStyle = "Swing"
        vm.traderType = .options
        vm.startedTrading = "2019-01-01"

        await vm.submit()

        if case .complete = gate.phase {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected gate complete, got \(gate.phase)")
        }
    }

    @MainActor
    func testFailedSubmitDoesNotCompleteGate() async {
        let profileID = ProfileID(UUID().uuidString)
        let repo = RecordingOnboardingProfileRepository()
        repo.shouldFailCompletion = true
        repo.storedSnapshot = ProfileOnboardingSnapshot(
            profileID: profileID,
            onboardingCompleted: false
        )
        let gate = ProfileOnboardingGateStore(
            profiles: repo,
            session: FixedSessionProvider(userID: UserID(profileID.rawValue)),
            rpc: nil,
            detailCache: nil,
            realtimeHub: nil,
            profileStore: CurrentUserProfileStore(
                profiles: repo,
                session: FixedSessionProvider(userID: UserID(profileID.rawValue)),
                imagePipeline: PlaceholderImagePipeline()
            )
        )

        let vm = makeOnboardingViewModel(snapshot: repo.storedSnapshot!, profiles: repo, gateStore: gate)
        vm.username = "jamie_t"
        vm.tradingStyle = "Swing"
        vm.traderType = .options
        vm.startedTrading = "2019-01-01"

        await vm.submit()

        if case .complete = gate.phase {
            XCTFail("Gate should remain incomplete after failed submit")
        } else {
            XCTAssertNotNil(vm.errorMessage)
        }
    }

    @MainActor
    func testUsernameConflictPreservesFormAndShowsFieldError() async {
        let profileID = ProfileID(UUID().uuidString)
        let repo = RecordingOnboardingProfileRepository()
        repo.shouldFailWithUsernameConflict = true
        repo.storedSnapshot = ProfileOnboardingSnapshot(
            profileID: profileID,
            onboardingCompleted: false
        )
        let gate = ProfileOnboardingGateStore(
            profiles: repo,
            session: FixedSessionProvider(userID: UserID(profileID.rawValue)),
            rpc: nil,
            detailCache: nil,
            realtimeHub: nil,
            profileStore: CurrentUserProfileStore(
                profiles: repo,
                session: FixedSessionProvider(userID: UserID(profileID.rawValue)),
                imagePipeline: PlaceholderImagePipeline()
            )
        )

        let vm = makeOnboardingViewModel(snapshot: repo.storedSnapshot!, profiles: repo, gateStore: gate)
        vm.username = "taken_name"
        vm.tradingStyle = "Swing"
        vm.traderType = .options
        vm.startedTrading = "2019-01-01"
        vm.bio = "Still here"

        await vm.submit()

        if case .complete = gate.phase {
            XCTFail("Gate should remain incomplete after username conflict")
        }
        XCTAssertEqual(vm.usernameError, ProfileOnboardingErrorMapping.usernameConflictMessage)
        XCTAssertNil(vm.errorMessage)
        XCTAssertEqual(vm.tradingStyle, "Swing")
        XCTAssertEqual(vm.traderType, .options)
        XCTAssertEqual(vm.startedTrading, "2019-01-01")
        XCTAssertEqual(vm.bio, "Still here")
        XCTAssertFalse(repo.storedSnapshot?.onboardingCompleted == true)
    }

    func testWebCompletedUserBypassesGate() {
        let snapshot = ProfileOnboardingSnapshot(
            profileID: ProfileID(UUID().uuidString),
            username: "web_user",
            onboardingCompleted: true,
            traderType: "Futures",
            tradingStyle: "Scalping",
            startedTrading: "2020-01-01"
        )
        XCTAssertFalse(ProfileOnboardingPolicy.profileNeedsOnboarding(snapshot))
    }
}

private final class RecordingOnboardingProfileRepository: ProfileRepository, @unchecked Sendable {
    var storedSnapshot: ProfileOnboardingSnapshot?
    var shouldFailCompletion = false
    var shouldFailWithUsernameConflict = false
    var lastCompletedUsername: String?

    func currentUser() async throws -> User { throw AppError.notImplemented(feature: "currentUser") }
    func profile(id: ProfileID) async throws -> Profile {
        Profile(
            id: id,
            userID: UserID(id.rawValue),
            username: storedSnapshot?.username ?? "user",
            displayName: storedSnapshot?.displayName ?? "Trader",
            bio: storedSnapshot?.bio,
            avatar: nil,
            traderType: TraderType.parse(storedSnapshot?.traderType),
            tradingStyle: storedSnapshot?.tradingStyle,
            primaryMarket: nil,
            startedTradingAt: nil,
            isPrivate: false,
            isCreator: false,
            createdAt: Date()
        )
    }

    func profile(username: String) async throws -> Profile { try await profile(id: ProfileID(UUID().uuidString)) }

    func onboardingSnapshot(for profileID: ProfileID) async throws -> ProfileOnboardingSnapshot {
        storedSnapshot ?? ProfileOnboardingSnapshot(profileID: profileID, onboardingCompleted: false)
    }

    func isUsernameTaken(_ username: String, excluding profileID: ProfileID) async throws -> Bool {
        false
    }

    func completeProfileOnboarding(_ submission: ProfileOnboardingSubmission) async throws -> Profile {
        if shouldFailWithUsernameConflict {
            throw AppError.transport(
                .validation(
                    statusCode: 409,
                    message: #"{"code":"23505","details":"Key (username)=(taken_name) already exists."}"#
                )
            )
        }
        if shouldFailCompletion {
            throw AppError.unknown(message: "Write failed")
        }
        lastCompletedUsername = submission.username
        storedSnapshot = ProfileOnboardingSnapshot(
            profileID: submission.profileID,
            username: submission.username,
            displayName: submission.displayName,
            onboardingCompleted: true,
            traderType: submission.traderType.rawValue,
            tradingStyle: submission.tradingStyle,
            startedTrading: submission.startedTrading
        )
        return try await profile(id: submission.profileID)
    }

    func updateProfile(_ profile: Profile) async throws -> Profile { profile }
    func stats(for profileID: ProfileID) async throws -> ProfileStats {
        ProfileStats(profileID: profileID, followerCount: 0, followingCount: 0, postCount: 0, tradeCount: 0, publicTradeCount: 0, winRate: nil, profitFactor: nil, netPnL: nil, averageRR: nil, payoutTotal: nil, expectancy: nil)
    }
    func wallPosts(for profileID: ProfileID, page: PageRequest) async throws -> CursorPage<Post> { throw AppError.notImplemented(feature: "wallPosts") }
    func wallPost(id: PostID) async throws -> Post { throw AppError.notImplemented(feature: "wallPost") }
    func followState(from viewer: ProfileID, to target: ProfileID) async throws -> FollowState { .none }
    func follow(from viewer: ProfileID, to target: ProfileID) async throws {}
    func unfollow(from viewer: ProfileID, to target: ProfileID) async throws {}
    func followers(of profileID: ProfileID, page: PageRequest) async throws -> CursorPage<Profile> { CursorPage(items: [], nextCursor: nil) }
    func following(of profileID: ProfileID, page: PageRequest) async throws -> CursorPage<Profile> { CursorPage(items: [], nextCursor: nil) }
    func creator(for profileID: ProfileID) async throws -> Creator? { nil }
}

private struct FixedSessionProvider: SessionProviding {
    let userID: UserID
    var currentUserID: UserID? { get async { userID } }
    var accessToken: String? { get async { "token" } }
}

@MainActor
private func makeOnboardingViewModel(
    snapshot: ProfileOnboardingSnapshot,
    profiles: any ProfileRepository,
    gateStore: ProfileOnboardingGateStore
) -> ProfileOnboardingViewModel {
    ProfileOnboardingViewModel(
        snapshot: snapshot,
        profiles: profiles,
        gateStore: gateStore,
        uploadService: OnboardingStubUploadService(),
        objectStorage: OnboardingStubObjectStorage(),
        appConfiguration: AppConfiguration.make(for: .debug)
    )
}

private struct OnboardingStubUploadService: UploadService {
    func upload(_ request: UploadRequest) async throws -> MediaReference {
        MediaReference(id: request.path, kind: .image, altText: nil)
    }
}

private struct OnboardingStubObjectStorage: ObjectStorageProviding {
    func upload(bucket: String, path: String, data: Data, contentType: String) async throws -> String {
        path
    }

    func download(bucket: String, path: String) async throws -> Data { Data() }
    func delete(bucket: String, path: String) async throws {}
    func publicURL(bucket: String, path: String) -> URL? {
        URL(string: "https://example.test/storage/v1/object/public/\(bucket)/\(path)")
    }
}
