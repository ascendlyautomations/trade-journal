import XCTest
@testable import TradeTraxs

final class TradeTraxsTests: XCTestCase {
    func testCompositionRootBootstrapProducesEnvironment() {
        let environment = CompositionRoot.bootstrap()
        XCTAssertEqual(
            environment.configuration.buildConfiguration,
            BuildConfiguration.current
        )
        XCTAssertNotNil(environment.navigation.store)
        XCTAssertNotNil(environment.dependencies.navigation.coordinator)
        XCTAssertNotNil(environment.networking.client)
        XCTAssertNotNil(environment.dependencies.networking.requestBuilder)
        XCTAssertNotNil(environment.data.trades)
        XCTAssertNotNil(environment.dependencies.data.feed)
        XCTAssertNotNil(environment.themeManager)
        XCTAssertNotNil(environment.authentication.manager)
        XCTAssertNotNil(environment.dependencies.authentication.coordinator)
    }

    func testUserFacingErrorMapsUnknown() {
        let mapped = UserFacingError.map(AppError.unknown(message: "probe"))
        XCTAssertEqual(mapped.title, "Something went wrong")
        XCTAssertEqual(mapped.message, "probe")
        XCTAssertEqual(mapped.action, .retry)
    }

    func testDeepLinkParserDashboard() throws {
        let parser = DeepLinkParser()
        let url = try XCTUnwrap(URL(string: "https://www.tradetraxs.com/dashboard"))
        XCTAssertEqual(parser.parse(url: url), .tab(.home))
    }

    func testDeepLinkParserTradeDetail() throws {
        let parser = DeepLinkParser()
        let url = try XCTUnwrap(URL(string: "https://www.tradetraxs.com/trade/abc-123"))
        XCTAssertEqual(parser.parse(url: url), .home(.tradeDetail(TradeID("abc-123"))))
    }

    func testDeepLinkParserMessagesThread() throws {
        let parser = DeepLinkParser()
        let url = try XCTUnwrap(URL(string: "https://www.tradetraxs.com/messages/thread-1"))
        XCTAssertEqual(parser.parse(url: url), .messages(.thread(ConversationID("thread-1"))))
    }

    func testNotificationRouterDM() {
        let router = NotificationRouter()
        let notification = NotificationDestination(
            category: .directMessage,
            threadID: nil,
            tradeID: nil,
            postID: nil,
            reelID: nil,
            profileID: nil,
            conversationID: ConversationID("c1"),
            roomID: nil,
            reportID: nil,
            rawUserInfo: [:]
        )
        XCTAssertEqual(router.destination(for: notification), .messages(.thread(ConversationID("c1"))))
    }

    func testNavigationCoordinatorAuthThenHomeTrade() {
        let store = NavigationStore(state: .initial)
        let coordinator = NavigationCoordinator(store: store)

        XCTAssertEqual(store.sessionPhase, .unauthenticated)
        coordinator.markAuthenticated()
        XCTAssertEqual(store.sessionPhase, .authenticated)
        XCTAssertEqual(store.selectedTab, .home)

        coordinator.open(.home(.tradeDetail(TradeID("t1"))))
        XCTAssertEqual(store.selectedTab, .home)
        XCTAssertEqual(store.paths.home, [.tradeDetail(TradeID("t1"))])

        coordinator.open(.tab(.feed))
        XCTAssertEqual(store.selectedTab, .feed)
        XCTAssertEqual(store.paths.home, [.tradeDetail(TradeID("t1"))], "Home stack retained")

        coordinator.open(.tab(.profile))
        coordinator.markUnauthenticated()
        XCTAssertEqual(store.sessionPhase, .unauthenticated)
        XCTAssertTrue(store.paths.home.isEmpty)
    }

    func testCreateTabInvokesSheetWithoutChangingContentTab() {
        let state = NavigationState(
            sessionPhase: .authenticated,
            selectedTab: .feed,
            previousContentTab: .feed,
            homePath: [],
            feedPath: [],
            messagesPath: [],
            profilePath: [],
            authPath: [],
            presentedSheet: nil,
            presentedFullScreen: nil,
            pendingAfterAuth: nil
        )
        let store = NavigationStore(state: state)
        let coordinator = NavigationCoordinator(store: store)

        coordinator.selectTab(.create)
        XCTAssertEqual(store.selectedTab, .feed)
        XCTAssertEqual(store.presentedSheet, .composeChooser)
    }

    func testPendingDeepLinkAfterAuth() {
        let store = NavigationStore(state: .initial)
        let coordinator = NavigationCoordinator(store: store)

        coordinator.stashForAuthentication(.messages(.thread(ConversationID("x"))))
        XCTAssertEqual(store.sessionPhase, .unauthenticated)
        coordinator.markAuthenticated()
        XCTAssertEqual(store.selectedTab, .messages)
        XCTAssertEqual(store.paths.messages, [.thread(ConversationID("x"))])
        XCTAssertNil(store.pendingAfterAuth)
    }
}
