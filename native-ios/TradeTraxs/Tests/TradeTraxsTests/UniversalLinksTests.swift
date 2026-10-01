import XCTest
@testable import TradeTraxs

final class UniversalLinksTests: XCTestCase {
    private let parser = DeepLinkParser()

    func testProfileLinkOpensFeedProfile() throws {
        let url = try XCTUnwrap(URL(string: "https://www.tradetraxs.com/profile/nrltrades"))
        XCTAssertEqual(parser.parse(url: url), .feed(.profile(ProfileID("nrltrades"))))
    }

    func testTradeDetailLink() throws {
        let url = try XCTUnwrap(URL(string: "https://tradetraxs.com/trade/abc-123"))
        XCTAssertEqual(parser.parse(url: url), .home(.tradeDetail(TradeID("abc-123"))))
    }

    func testPostAndReelLinks() throws {
        let post = try XCTUnwrap(URL(string: "https://www.tradetraxs.com/post/post-1"))
        XCTAssertEqual(parser.parse(url: post), .feed(.post(PostID("post-1"))))

        let reel = try XCTUnwrap(URL(string: "https://www.tradetraxs.com/reel/reel-1"))
        XCTAssertEqual(parser.parse(url: reel), .feed(.reel(ReelID("reel-1"))))
    }

    func testRoomShortLinkOpensMessagesTab() throws {
        let url = try XCTUnwrap(URL(string: "https://www.tradetraxs.com/room/futures-lounge"))
        XCTAssertEqual(parser.parse(url: url), .messages(.room(RoomID("futures-lounge"))))
    }

    func testCommunityRoomQueryOpensMessagesTab() throws {
        let url = try XCTUnwrap(
            URL(string: "https://www.tradetraxs.com/community?room=futures-lounge&section=gold")
        )
        XCTAssertEqual(parser.parse(url: url), .messages(.room(RoomID("futures-lounge"))))
    }

    func testMessagesThreadLink() throws {
        let url = try XCTUnwrap(URL(string: "https://www.tradetraxs.com/messages/thread-1"))
        XCTAssertEqual(parser.parse(url: url), .messages(.thread(ConversationID("thread-1"))))
    }

    func testUnsupportedMarketingPathReturnsNil() throws {
        let url = try XCTUnwrap(URL(string: "https://www.tradetraxs.com/pricing"))
        XCTAssertNil(parser.parse(url: url))
    }

    func testAnalystAndAILinksOpenHomeDashboard() throws {
        let analyst = try XCTUnwrap(URL(string: "https://www.tradetraxs.com/analyst"))
        XCTAssertEqual(parser.parse(url: analyst), .tab(.home))

        let ai = try XCTUnwrap(URL(string: "https://tradetraxs.com/ai"))
        XCTAssertEqual(parser.parse(url: ai), .tab(.home))

        let custom = try XCTUnwrap(URL(string: "tradetraxs://analyst"))
        XCTAssertEqual(parser.parse(url: custom), .tab(.home))
    }

    func testUniversalLinkPolicyMatchesDomains() throws {
        let www = try XCTUnwrap(URL(string: "https://www.tradetraxs.com/trade/t1"))
        let apex = try XCTUnwrap(URL(string: "https://tradetraxs.com/trade/t1"))
        XCTAssertTrue(UniversalLinkPolicy.isSupportedHTTPSHost(www))
        XCTAssertTrue(UniversalLinkPolicy.isSupportedHTTPSHost(apex))
        XCTAssertFalse(UniversalLinkPolicy.isSupportedHTTPSHost(URL(string: "https://example.com")!))
    }

    @MainActor
    func testPendingUniversalLinkAfterAuth() {
        DeepLinkLaunchTrace.resetDuplicateGuardForTesting()
        let store = NavigationStore(state: .initial)
        let coordinator = NavigationCoordinator(store: store)
        let router = DeepLinkRouter()

        let url = URL(string: "https://www.tradetraxs.com/trade/pending-1")!
        XCTAssertTrue(router.route(url: url, using: coordinator, store: store))
        XCTAssertEqual(store.pendingAfterAuth?.asAppDestination, .home(.tradeDetail(TradeID("pending-1"))))

        coordinator.markAuthenticated()
        XCTAssertEqual(store.selectedTab, .home)
        XCTAssertEqual(store.paths.home, [.tradeDetail(TradeID("pending-1"))])
        XCTAssertEqual(store.sessionPhase, .authenticated)
    }

    @MainActor
    func testWarmUniversalLinkRoutesWithoutLeavingAuthenticatedShell() {
        DeepLinkLaunchTrace.resetDuplicateGuardForTesting()
        let store = NavigationStore(state: .initial)
        let coordinator = NavigationCoordinator(store: store)
        let router = DeepLinkRouter()
        coordinator.markAuthenticated()

        let url = URL(string: "https://www.tradetraxs.com/trade/warm-1")!
        XCTAssertTrue(router.route(url: url, using: coordinator, store: store))
        XCTAssertEqual(store.sessionPhase, .authenticated)
        XCTAssertNil(store.pendingAfterAuth)
        XCTAssertEqual(store.paths.home, [.tradeDetail(TradeID("warm-1"))])
    }

    @MainActor
    func testColdUniversalLinkStaysPendingUntilSessionRestore() {
        DeepLinkLaunchTrace.resetDuplicateGuardForTesting()
        let store = NavigationStore(state: .initial)
        let coordinator = NavigationCoordinator(store: store)
        let router = DeepLinkRouter()

        let url = URL(string: "https://www.tradetraxs.com/profile/cold-user")!
        XCTAssertTrue(router.route(url: url, using: coordinator, store: store))
        XCTAssertEqual(store.sessionPhase, .unauthenticated)
        XCTAssertEqual(store.pendingAfterAuth?.asAppDestination, .feed(.profile(ProfileID("cold-user"))))

        coordinator.markAuthenticated()
        XCTAssertEqual(store.sessionPhase, .authenticated)
        XCTAssertNil(store.pendingAfterAuth)
        XCTAssertEqual(store.paths.feed, [.profile(ProfileID("cold-user"))])
    }

    @MainActor
    func testLoggedOutUniversalLinkPreservesDestination() {
        DeepLinkLaunchTrace.resetDuplicateGuardForTesting()
        let store = NavigationStore(state: .initial)
        let coordinator = NavigationCoordinator(store: store)
        let router = DeepLinkRouter()

        let url = URL(string: "https://www.tradetraxs.com/post/logged-out-post")!
        XCTAssertTrue(router.route(url: url, using: coordinator, store: store))
        XCTAssertEqual(store.sessionPhase, .unauthenticated)
        XCTAssertEqual(store.pendingAfterAuth?.asAppDestination, .feed(.post(PostID("logged-out-post"))))
        XCTAssertTrue(store.paths.feed.isEmpty)
    }

    @MainActor
    func testAuthenticatedAuthRouteDoesNotDemoteShell() {
        DeepLinkLaunchTrace.resetDuplicateGuardForTesting()
        let store = NavigationStore(state: .initial)
        let coordinator = NavigationCoordinator(store: store)
        let router = DeepLinkRouter()
        coordinator.markAuthenticated()

        let url = URL(string: "https://www.tradetraxs.com/login")!
        XCTAssertTrue(router.route(url: url, using: coordinator, store: store))
        XCTAssertEqual(store.sessionPhase, .authenticated)
        XCTAssertNil(store.pendingAfterAuth)
    }

    @MainActor
    func testUnsupportedUniversalLinkDoesNotBlockAuthenticatedShell() {
        DeepLinkLaunchTrace.resetDuplicateGuardForTesting()
        let store = NavigationStore(state: .initial)
        let coordinator = NavigationCoordinator(store: store)
        let router = DeepLinkRouter()
        coordinator.markAuthenticated()

        let url = URL(string: "https://www.tradetraxs.com/pricing")!
        XCTAssertFalse(router.route(url: url, using: coordinator, store: store))
        XCTAssertEqual(store.sessionPhase, .authenticated)
        XCTAssertTrue(store.paths.home.isEmpty)
        XCTAssertNil(store.pendingAfterAuth)
    }

    @MainActor
    func testDeletedDestinationStillLeavesAuthenticatedShell() {
        DeepLinkLaunchTrace.resetDuplicateGuardForTesting()
        let store = NavigationStore(state: .initial)
        let coordinator = NavigationCoordinator(store: store)
        let router = DeepLinkRouter()
        coordinator.markAuthenticated()

        let url = URL(string: "https://www.tradetraxs.com/trade/deleted-trade")!
        XCTAssertTrue(router.route(url: url, using: coordinator, store: store))
        XCTAssertEqual(store.sessionPhase, .authenticated)
        XCTAssertEqual(store.paths.home, [.tradeDetail(TradeID("deleted-trade"))])
    }

    @MainActor
    func testDuplicateUniversalLinkDoesNotDemoteOrDoublePush() {
        DeepLinkLaunchTrace.resetDuplicateGuardForTesting()
        let store = NavigationStore(state: .initial)
        let coordinator = NavigationCoordinator(store: store)
        let router = DeepLinkRouter()
        coordinator.markAuthenticated()

        let url = URL(string: "https://www.tradetraxs.com/reel/reel-dup")!
        XCTAssertTrue(router.route(url: url, using: coordinator, store: store))
        XCTAssertTrue(router.route(url: url, using: coordinator, store: store))
        XCTAssertEqual(store.sessionPhase, .authenticated)
        XCTAssertEqual(store.paths.feed, [.reel(ReelID("reel-dup"))])
    }

    @MainActor
    func testRepairRestoresShellAfterAuthRouteDemotion() {
        let store = NavigationStore(state: .initial)
        let coordinator = NavigationCoordinator(store: store)
        coordinator.markAuthenticated()
        coordinator.openAuth(.login)
        XCTAssertEqual(store.sessionPhase, .unauthenticated)

        coordinator.restoreAuthenticatedShellAfterDeepLink()
        XCTAssertEqual(store.sessionPhase, .authenticated)
    }

    @MainActor
    func testRepairDoesNotSkipSignInBeforeSessionRestore() {
        let store = NavigationStore(state: .initial)
        let coordinator = NavigationCoordinator(store: store)
        coordinator.openAuth(.login)
        coordinator.restoreAuthenticatedShellAfterDeepLink()
        XCTAssertEqual(store.sessionPhase, .unauthenticated)
    }

    func testAchievementUniversalLinkParses() throws {
        let url = try XCTUnwrap(URL(string: "https://www.tradetraxs.com/feed?achievement=ach-1"))
        XCTAssertEqual(parser.parse(url: url), .feed(.achievement(AchievementID("ach-1"))))
    }

    func testAuthenticatedShellGateOnlyRepairsAfterShellEntry() {
        XCTAssertFalse(AuthenticatedShellGate.shouldRepairShell(
            didEnterAuthenticatedShell: false,
            sessionPhase: .unauthenticated
        ))
        XCTAssertTrue(AuthenticatedShellGate.shouldRepairShell(
            didEnterAuthenticatedShell: true,
            sessionPhase: .unauthenticated
        ))
        XCTAssertFalse(AuthenticatedShellGate.shouldRepairShell(
            didEnterAuthenticatedShell: true,
            sessionPhase: .authenticated
        ))
    }
}
