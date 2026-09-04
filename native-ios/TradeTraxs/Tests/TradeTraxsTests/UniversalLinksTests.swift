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
        let store = NavigationStore(state: .initial)
        let coordinator = NavigationCoordinator(store: store)
        let router = DeepLinkRouter()

        let url = URL(string: "https://www.tradetraxs.com/trade/pending-1")!
        XCTAssertTrue(router.route(url: url, using: coordinator, store: store))
        XCTAssertEqual(store.pendingAfterAuth?.asAppDestination, .home(.tradeDetail(TradeID("pending-1"))))

        coordinator.markAuthenticated()
        XCTAssertEqual(store.selectedTab, .home)
        XCTAssertEqual(store.paths.home, [.tradeDetail(TradeID("pending-1"))])
    }
}
