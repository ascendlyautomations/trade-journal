import XCTest
@testable import TradeTraxs

@MainActor
final class SessionViewerIdentityTests: XCTestCase {
    func testNilProductionViewerDoesNotResolveToScreenshotFixture() {
        let resolution = SessionViewerIdentity.resolve(
            userID: nil,
            demoExperienceActive: false,
            screenshotFixturesEnabled: false
        )
        XCTAssertEqual(resolution, .unavailable)
    }

    func testRealAuthenticatedViewerUsesRealID() {
        let userID = UserID("11111111-1111-4111-8111-111111111111")
        let resolution = SessionViewerIdentity.resolve(
            userID: userID,
            demoExperienceActive: false,
            screenshotFixturesEnabled: false
        )
        XCTAssertEqual(resolution, .viewer(ProfileID(userID.rawValue)))
    }

    func testGuestSessionUsesRealAccountInsteadOfDemoFixture() {
        let userID = GuestShowcaseAccount.productionUserID
        let resolution = SessionViewerIdentity.resolve(
            userID: userID,
            demoExperienceActive: true,
            screenshotFixturesEnabled: false
        )
        XCTAssertEqual(resolution, .viewer(ProfileID(userID.rawValue)))
    }

    func testDemoModeUsesDemoExploreTrader() {
        let resolution = SessionViewerIdentity.resolve(
            userID: nil,
            demoExperienceActive: true,
            screenshotFixturesEnabled: false
        )
        XCTAssertEqual(resolution, .viewer(ProfileID("demo.explore.trader")))
        XCTAssertEqual(DemoExperienceSupport.profileID.rawValue, "demo.explore.trader")
    }

    func testExplicitScreenshotModeUsesFixtureIdentity() {
        let resolution = SessionViewerIdentity.resolve(
            userID: nil,
            demoExperienceActive: false,
            screenshotFixturesEnabled: true
        )
        XCTAssertEqual(resolution, .viewer(SessionViewerIdentity.screenshotFixtureProfileID))
        XCTAssertFalse(SessionViewerIdentity.shouldCommit(
            resolved: SessionViewerIdentity.screenshotFixtureProfileID,
            userID: UserID("11111111-1111-4111-8111-111111111111"),
            demoExperienceActive: false,
            screenshotFixturesEnabled: false
        ))
    }

    func testNilViewerDoesNotLoadTradingDayFixtures() async {
        let loader = CalendarDayDetailLoader(
            dayKey: "2026-08-08",
            trades: IdentityEmptyTradeRepository(),
            session: IdentityNilSession(),
            detailCache: DetailPresentationCache()
        )
        await loader.refresh()
        XCTAssertNil(loader.summary)
        XCTAssertTrue(loader.dayTrades.isEmpty)
        XCTAssertEqual(loader.errorMessage, SessionViewerIdentity.sessionUnavailableMessage)
        XCTAssertFalse(loader.isLoading)
    }

    func testNilViewerDoesNotLoadAchievementFixtures() async {
        let viewModel = AchievementDetailViewModel(
            achievementID: AchievementID("dev-achievement-1"),
            achievements: IdentityAchievementRepository(),
            profiles: IdentityProfileRepository(),
            session: IdentityNilSession(),
            imagePipeline: IdentityImagePipeline(),
            cache: DetailPresentationCache(),
            navigationCoordinator: NavigationCoordinator(store: NavigationStore())
        )
        viewModel.loadIfNeeded()
        await waitFor {
            if case .failed = viewModel.phase { return true }
            return false
        }
        XCTAssertNil(viewModel.achievement)
        XCTAssertEqual(viewModel.phase, .failed(SessionViewerIdentity.sessionUnavailableMessage))
    }

    func testStaleScreenshotIdentityDoesNotPaintAchievementFixtures() async {
        let viewModel = AchievementDetailViewModel(
            achievementID: AchievementID("dev-achievement-1"),
            achievements: IdentityAchievementRepository(),
            profiles: IdentityProfileRepository(),
            session: IdentityFlipSession(first: "dev.screenshot", then: "33333333-3333-4333-8333-333333333333"),
            imagePipeline: IdentityImagePipeline(),
            cache: DetailPresentationCache(),
            navigationCoordinator: NavigationCoordinator(store: NavigationStore())
        )
        viewModel.loadIfNeeded()
        await waitFor {
            if case .failed = viewModel.phase { return true }
            if case .loaded = viewModel.phase { return true }
            return false
        }
        XCTAssertNil(viewModel.achievement)
    }

    private func waitFor(timeout: TimeInterval = 2, _ condition: @escaping () -> Bool) async {
        let start = Date()
        while !condition() {
            if Date().timeIntervalSince(start) > timeout {
                XCTFail("Timed out")
                return
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}

private struct IdentityNilSession: SessionProviding {
    var currentUserID: UserID? { get async { nil } }
    var accessToken: String? { get async { nil } }
}

private final class IdentityFlipSession: SessionProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var upcoming: [String?]
    private var current: String?

    init(first: String?, then: String?) {
        upcoming = [first, then]
        current = first
    }

    var currentUserID: UserID? {
        get async {
            lock.lock()
            let value = upcoming.isEmpty ? current : upcoming.removeFirst()
            current = value
            lock.unlock()
            guard let value else { return nil }
            return UserID(value)
        }
    }

    var accessToken: String? { get async { nil } }
}

private struct IdentityEmptyTradeRepository: TradeRepository {
    func trade(id: TradeID) async throws -> Trade { throw AppError.unknown(message: "stub") }
    func trades(
        ownedBy profileID: ProfileID,
        accountID: TradingAccountID?,
        page: PageRequest,
        publicOnly: Bool
    ) async throws -> CursorPage<Trade> {
        CursorPage(items: [], nextCursor: nil)
    }
    func save(_ draft: TradeDraft) async throws -> Trade { throw AppError.unknown(message: "stub") }
    func update(_ trade: Trade) async throws -> Trade { trade }
    func delete(id: TradeID) async throws {}
    func images(for tradeID: TradeID) async throws -> [TradeImage] { [] }
    func notes(for tradeID: TradeID) async throws -> [TradeNote] { [] }
    func statistics(for profileID: ProfileID, interval: DateIntervalValue) async throws -> TradeStatistics {
        TradeStatistics(
            tradeCount: 0, winCount: 0, lossCount: 0,
            totalPnL: Money(amount: 0), averagePnL: Money(amount: 0),
            averageRiskReward: nil, winRate: 0
        )
    }
    func accounts(for profileID: ProfileID) async throws -> [TradingAccount] { [] }
}

private struct IdentityAchievementRepository: AchievementRepository {
    func achievement(id: AchievementID) async throws -> Achievement {
        throw AppError.unknown(message: "stub")
    }
    func achievements(
        for profileID: ProfileID,
        page: PageRequest,
        publicOnly: Bool
    ) async throws -> CursorPage<Achievement> {
        CursorPage(items: [], nextCursor: nil)
    }
    func save(_ achievement: Achievement, metadata: JSONValue?) async throws -> Achievement { achievement }
    func withdrawalAchievementLinks(for profileID: ProfileID) async throws -> [WithdrawalAchievementLinkRow] { [] }
}

private struct IdentityProfileRepository: ProfileRepository {
    func currentUser() async throws -> User { throw AppError.unknown(message: "stub") }
    func profile(id: ProfileID) async throws -> Profile { throw AppError.unknown(message: "stub") }
    func profile(username: String) async throws -> Profile { throw AppError.unknown(message: "stub") }
    func updateProfile(_ profile: Profile) async throws -> Profile { profile }
    func stats(for profileID: ProfileID) async throws -> ProfileStats { throw AppError.unknown(message: "stub") }
    func wallPosts(for profileID: ProfileID, page: PageRequest) async throws -> CursorPage<Post> {
        CursorPage(items: [], nextCursor: nil)
    }
    func wallPost(id: PostID) async throws -> Post { throw AppError.unknown(message: "stub") }
    func followState(from viewer: ProfileID, to target: ProfileID) async throws -> FollowState { .none }
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

private struct IdentityImagePipeline: ImagePipeline {
    func data(for request: ImageRequest) async throws -> Data { Data() }
    func prefetch(_ requests: [ImageRequest]) async {}
    func invalidate(reference: MediaReference) async {}
}
