import XCTest
@testable import TradeTraxs

@MainActor
final class AccountDeletionExperienceTests: XCTestCase {
    func testDeleteAccountExplainerIncludesCoreWarning() async {
        let context = await makeContext(billing: freeBillingStatus())
        let viewModel = context.viewModel
        await viewModel.refresh()
        XCTAssertTrue(
            viewModel.deleteAccountExplainerMessage.contains(
                "Deleting your TradeTraxs account permanently deletes your account and associated data."
            )
        )
        XCTAssertTrue(viewModel.deleteAccountExplainerMessage.contains("This cannot be undone."))
    }

    func testDeleteAccountExplainerIncludesSubscriptionNoticeWhenProActive() async {
        let context = await makeContext(billing: SettingsFixtures.billingStatus())
        let viewModel = context.viewModel
        await viewModel.refresh()
        let message = viewModel.deleteAccountExplainerMessage
        XCTAssertTrue(message.contains("TraxPro trial"))
        XCTAssertTrue(message.contains("Stripe billing"))
    }

    func testDeleteAccountExplainerIncludesAppleNoticeWhenSignedInWithApple() async throws {
        let navigation = CompositionRoot.bootstrapNavigation()
        let auth = CompositionRoot.bootstrapAuthenticationForTests(navigation: navigation)
        try auth.sessionManager.install(
            AuthenticationSession(
                userID: UserID(SettingsFixtures.viewerID.rawValue),
                email: "trader@tradetraxs.com",
                accessToken: "access-token",
                refreshToken: "refresh-token",
                expiresAt: Date().addingTimeInterval(3600),
                provider: .apple,
                createdAt: Date(),
                lastRefreshedAt: nil
            )
        )
        _ = auth.manager.prepareColdLaunch()
        auth.coordinator.syncNavigation(with: auth.manager.state)

        let viewModel = SettingsAccountViewModel(
            profiles: AccountDeletionStubProfiles(),
            billing: AccountDeletionStubBilling(status: freeBillingStatus()),
            account: AccountDeletionSpyRepository(),
            session: auth.sessionBridge,
            authenticationCoordinator: auth.coordinator,
            navigationCoordinator: navigation.coordinator
        )
        await viewModel.refresh()
        XCTAssertTrue(viewModel.usesAppleSignIn)
        XCTAssertTrue(viewModel.deleteAccountExplainerMessage.contains("Sign in with Apple"))
    }

    func testConfirmDeleteAccountSignsOutAfterServerSuccess() async {
        let context = await makeContext(billing: freeBillingStatus())
        let viewModel = context.viewModel
        await viewModel.refresh()

        viewModel.confirmDeleteAccount()
        await waitFor { context.account.deleteCallCount == 1 }
        await waitFor { context.navigation.store.sessionPhase == .unauthenticated }
        XCTAssertEqual(context.account.deleteCallCount, 1)
        XCTAssertEqual(context.navigation.store.sessionPhase, .unauthenticated)
        XCTAssertFalse(context.auth.manager.state.isAuthenticated)
    }

    func testConfirmDeleteAccountSurfacesServerError() async {
        let account = AccountDeletionSpyRepository(error: .serverMessage("Could not delete."))
        let context = await makeContext(billing: freeBillingStatus(), account: account)
        let viewModel = context.viewModel
        await viewModel.refresh()

        viewModel.confirmDeleteAccount()
        await waitFor { viewModel.deleteErrorMessage != nil }
        XCTAssertEqual(viewModel.deleteErrorMessage, "Could not delete.")
        XCTAssertTrue(context.auth.manager.state.isAuthenticated)
    }

    func testConfirmDeleteAccountSurfacesUnauthorized() async {
        let account = AccountDeletionSpyRepository(error: .notAuthenticated)
        let context = await makeContext(billing: freeBillingStatus(), account: account)
        let viewModel = context.viewModel
        await viewModel.refresh()

        viewModel.confirmDeleteAccount()
        await waitFor { viewModel.deleteErrorMessage != nil }
        XCTAssertEqual(viewModel.deleteErrorMessage, "Your session expired. Sign in again and retry.")
        XCTAssertTrue(context.auth.manager.state.isAuthenticated)
    }

    private struct TestContext {
        let auth: AuthenticationEnvironment
        let navigation: NavigationEnvironment
        let account: AccountDeletionSpyRepository
        let viewModel: SettingsAccountViewModel
    }

    private func makeContext(
        billing: BillingStatus,
        account: AccountDeletionSpyRepository = AccountDeletionSpyRepository()
    ) async -> TestContext {
        let navigation = CompositionRoot.bootstrapNavigation()
        let auth = CompositionRoot.bootstrapAuthenticationForTests(navigation: navigation)
        _ = auth.manager.prepareColdLaunch()
        try? await auth.coordinator.signIn(email: "trader@tradetraxs.com", password: "password1")
        let viewModel = SettingsAccountViewModel(
            profiles: AccountDeletionStubProfiles(),
            billing: AccountDeletionStubBilling(status: billing),
            account: account,
            session: auth.sessionBridge,
            authenticationCoordinator: auth.coordinator,
            navigationCoordinator: navigation.coordinator
        )
        return TestContext(
            auth: auth,
            navigation: navigation,
            account: account,
            viewModel: viewModel
        )
    }

    private func freeBillingStatus() -> BillingStatus {
        BillingStatus(
            profileID: SettingsFixtures.viewerID,
            plan: .free,
            lifecycle: .none,
            isProEntitled: false,
            dailyTradeLimit: 10,
            dailyPostLimit: 5,
            dailyMessageLimit: 50,
            maxTradeEntryAccounts: 3
        )
    }

    private func waitFor(
        timeout: TimeInterval = 2,
        _ condition: @escaping () -> Bool
    ) async {
        let start = Date()
        while !condition() {
            if Date().timeIntervalSince(start) > timeout {
                XCTFail("Timed out waiting for condition")
                return
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}

// MARK: - Stubs

private final class AccountDeletionSpyRepository: AccountRepository, @unchecked Sendable {
    private(set) var deleteCallCount = 0
    let error: AccountDeletionError?

    init(error: AccountDeletionError? = nil) {
        self.error = error
    }

    func deleteAuthenticatedAccount() async throws {
        deleteCallCount += 1
        if let error { throw error }
    }
}

private struct AccountDeletionStubBilling: BillingRepository {
    let status: BillingStatus

    func status(for profileID: ProfileID) async throws -> BillingStatus {
        var copy = status
        copy.profileID = profileID
        return copy
    }

    func subscription(for profileID: ProfileID) async throws -> Subscription? { nil }

    func refreshEntitlements(for profileID: ProfileID) async throws -> BillingStatus {
        try await status(for: profileID)
    }
}

private struct AccountDeletionStubProfiles: ProfileRepository {
    func currentUser() async throws -> User {
        User(
            id: UserID(SettingsFixtures.viewerID.rawValue),
            email: "trader@tradetraxs.com",
            createdAt: SettingsFixtures.profile().createdAt ?? .now
        )
    }

    func profile(id: ProfileID) async throws -> Profile {
        SettingsFixtures.profile(owner: id)
    }

    func profile(username: String) async throws -> Profile {
        try await profile(id: ProfileID(username))
    }

    func updateProfile(_ profile: Profile) async throws -> Profile { profile }

    func stats(for profileID: ProfileID) async throws -> ProfileStats {
        ProfileStats(
            profileID: profileID,
            followerCount: 0,
            followingCount: 0,
            postCount: 0,
            tradeCount: 0,
            publicTradeCount: 0
        )
    }

    func wallPosts(for profileID: ProfileID, page: PageRequest) async throws -> CursorPage<Post> {
        CursorPage(items: [], nextCursor: nil)
    }

    func wallPost(id: PostID) async throws -> Post {
        throw AppError.unknown(message: "not found")
    }

    func followState(from viewer: ProfileID, to target: ProfileID) async throws -> FollowState {
        .none
    }

    func follow(from viewer: ProfileID, to target: ProfileID) async throws {}

    func unfollow(from viewer: ProfileID, to target: ProfileID) async throws {}

    func followers(of profileID: ProfileID, page: PageRequest) async throws -> CursorPage<Profile> {
        CursorPage(items: [], nextCursor: nil)
    }

    func following(of profileID: ProfileID, page: PageRequest) async throws -> CursorPage<Profile> {
        CursorPage(items: [], nextCursor: nil)
    }

    func creator(for profileID: ProfileID) async throws -> Creator? { nil }
}
