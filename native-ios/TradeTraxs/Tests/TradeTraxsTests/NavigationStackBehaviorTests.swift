import XCTest
@testable import TradeTraxs

/// Verifies append-only tab paths — the same mutations SwiftUI `NavigationStack` bindings use.
@MainActor
final class NavigationStackBehaviorTests: XCTestCase {
    private func simulateSystemBack<T>(_ path: inout [T]) {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    // MARK: - Flow A/B (Messages → Settings)

    func testFlowA_MessagesSettingsBack() {
        let store = NavigationStore()
        store.sessionPhase = .authenticated
        store.selectedTab = .messages
        let coordinator = NavigationCoordinator(store: store)

        XCTAssertEqual(store.paths.messages, [])
        coordinator.pushMessages(.settings(.home))
        XCTAssertEqual(store.selectedTab, .messages)
        XCTAssertEqual(store.paths.messages, [.settings(.home)])

        simulateSystemBack(&store.paths.messages)
        XCTAssertEqual(store.paths.messages, [])
    }

    func testFlowB_MessagesSettingsNotificationsBackChain() {
        let store = NavigationStore()
        store.sessionPhase = .authenticated
        store.selectedTab = .messages
        let router = StackNavigation.messages(store: store)

        coordinatorPushMessagesSettings(store: store)
        router.pushSettings(.notifications)
        router.pushSettings(.notificationsMessages)

        XCTAssertEqual(
            messagesSettingsRoutes(in: store),
            [.home, .notifications, .notificationsMessages]
        )

        simulateSystemBack(&store.paths.messages)
        XCTAssertEqual(messagesSettingsRoutes(in: store), [.home, .notifications])

        simulateSystemBack(&store.paths.messages)
        XCTAssertEqual(messagesSettingsRoutes(in: store), [.home])

        simulateSystemBack(&store.paths.messages)
        XCTAssertTrue(store.paths.messages.isEmpty)
    }

    // MARK: - Flow C/D (Dashboard → Trades)

    func testFlowC_DashboardTradesBack() {
        let store = NavigationStore()
        store.sessionPhase = .authenticated
        store.selectedTab = .home
        let coordinator = NavigationCoordinator(store: store)

        coordinator.pushHome(.trades)
        XCTAssertEqual(store.selectedTab, .home)
        XCTAssertEqual(store.paths.home, [.trades])

        simulateSystemBack(&store.paths.home)
        XCTAssertTrue(store.paths.home.isEmpty)
    }

    func testFlowD_DashboardTradesManageAccountsBackChain() {
        let store = NavigationStore()
        store.sessionPhase = .authenticated
        store.selectedTab = .home
        let coordinator = NavigationCoordinator(store: store)

        coordinator.pushHome(.trades)
        coordinator.pushHome(.settings(.tradingAccounts))

        XCTAssertEqual(store.paths.home, [.trades, .settings(.tradingAccounts)])
        XCTAssertFalse(store.paths.home.contains(.settings(.home)))

        simulateSystemBack(&store.paths.home)
        XCTAssertEqual(store.paths.home, [.trades])

        simulateSystemBack(&store.paths.home)
        XCTAssertTrue(store.paths.home.isEmpty)
    }

    // MARK: - Flow E (Dashboard → Activity → Back)

    func testFlowE_DashboardActivityBack() {
        let store = NavigationStore()
        store.sessionPhase = .authenticated
        store.selectedTab = .home
        let coordinator = NavigationCoordinator(store: store)

        coordinator.pushHome(.activity)
        XCTAssertEqual(store.paths.home, [.activity])
        XCTAssertTrue(store.paths.profile.isEmpty)

        simulateSystemBack(&store.paths.home)
        XCTAssertTrue(store.paths.home.isEmpty)
    }

    // MARK: - Flow F (Profile → Activity → Notifications)

    func testFlowF_ProfileActivityNotificationsBackChain() {
        let store = NavigationStore()
        store.sessionPhase = .authenticated
        store.selectedTab = .profile
        let coordinator = NavigationCoordinator(store: store)

        coordinator.pushProfile(.activity)
        coordinator.pushProfile(.settings(.notifications))

        XCTAssertEqual(store.paths.profile, [.activity, .settings(.notifications)])

        simulateSystemBack(&store.paths.profile)
        XCTAssertEqual(store.paths.profile, [.activity])

        simulateSystemBack(&store.paths.profile)
        XCTAssertTrue(store.paths.profile.isEmpty)
    }

    // MARK: - Tab isolation

    func testOrdinaryPushDoesNotSwitchTabs() {
        let store = NavigationStore()
        store.sessionPhase = .authenticated
        store.selectedTab = .messages
        let coordinator = NavigationCoordinator(store: store)

        coordinator.pushMessages(.settings(.home))
        XCTAssertEqual(store.selectedTab, .messages)
        XCTAssertTrue(store.paths.profile.isEmpty)
        XCTAssertTrue(store.paths.home.isEmpty)
    }

    func testManageAccountsDoesNotMutateProfilePath() {
        let store = NavigationStore()
        store.sessionPhase = .authenticated
        store.selectedTab = .home
        let coordinator = NavigationCoordinator(store: store)

        coordinator.pushHome(.settings(.tradingAccounts))
        XCTAssertTrue(store.paths.profile.isEmpty)
        XCTAssertEqual(homeSettingsRoutes(in: store), [.tradingAccounts])
    }

    func testIndependentTabStacksPreserveHistoryOnTabSwitch() {
        let store = NavigationStore()
        store.sessionPhase = .authenticated
        let coordinator = NavigationCoordinator(store: store)

        coordinator.pushMessages(.thread(ConversationID("dm-1")))
        coordinator.selectTab(.profile)
        coordinator.pushProfile(.activity)

        coordinator.selectTab(.messages)
        XCTAssertEqual(store.paths.messages.count, 1)
        XCTAssertEqual(store.paths.profile.count, 1)
    }

    func testOtherProfileChildDestinationsStayOnTheLaunchingStack() {
        let store = NavigationStore()
        store.sessionPhase = .authenticated
        store.selectedTab = .feed
        let coordinator = NavigationCoordinator(store: store)
        let userA = ProfileID("user-a")
        let userB = ProfileID("user-b")
        let roomID = RoomID("room-a")

        coordinator.pushFeed(.profile(userA))
        coordinator.pushFollowers(userA)
        XCTAssertEqual(store.selectedTab, .feed)
        XCTAssertEqual(store.paths.feed, [.profile(userA), .followers(userA)])
        XCTAssertTrue(store.paths.profile.isEmpty)

        simulateSystemBack(&store.paths.feed)
        XCTAssertEqual(store.paths.feed, [.profile(userA)])

        coordinator.pushFollowing(userA)
        simulateSystemBack(&store.paths.feed)
        XCTAssertEqual(store.paths.feed, [.profile(userA)])

        coordinator.pushRoom(roomID)
        simulateSystemBack(&store.paths.feed)
        XCTAssertEqual(store.paths.feed, [.profile(userA)])

        store.paths.feed = [.explore]
        coordinator.pushFeed(.profile(userA))
        coordinator.pushFollowers(userA)
        simulateSystemBack(&store.paths.feed)
        XCTAssertEqual(store.paths.feed, [.explore, .profile(userA)])

        store.paths.feed = [.profile(userA), .followers(userA)]
        coordinator.pushOtherProfile(userB)
        XCTAssertEqual(
            store.paths.feed,
            [.profile(userA), .followers(userA), .profile(userB)]
        )
        simulateSystemBack(&store.paths.feed)
        XCTAssertEqual(store.paths.feed, [.profile(userA), .followers(userA)])
        simulateSystemBack(&store.paths.feed)
        XCTAssertEqual(store.paths.feed, [.profile(userA)])

        store.selectedTab = .home
        store.paths.home = [.otherProfile(userA)]
        coordinator.pushFollowers(userA)
        coordinator.pushTradeRoomsHome()
        XCTAssertEqual(store.selectedTab, .home)
        XCTAssertEqual(store.paths.home, [.otherProfile(userA), .followers(userA), .rooms])
        simulateSystemBack(&store.paths.home)
        simulateSystemBack(&store.paths.home)
        XCTAssertEqual(store.paths.home, [.otherProfile(userA)])

        store.selectedTab = .messages
        store.paths.messages = [.profile(userA)]
        coordinator.pushFollowing(userA)
        coordinator.pushRoom(roomID)
        XCTAssertEqual(store.selectedTab, .messages)
        XCTAssertEqual(store.paths.messages, [.profile(userA), .following(userA), .room(roomID)])
        XCTAssertTrue(store.paths.profile.isEmpty)
    }

    func testOwnProfileChildDestinationsPopToProfileRoot() {
        let store = NavigationStore()
        store.sessionPhase = .authenticated
        store.selectedTab = .profile
        let coordinator = NavigationCoordinator(store: store)
        let me = ProfileID("me")

        coordinator.pushFollowers(me)
        coordinator.pushFollowing(me)
        coordinator.pushTradeRoomsHome()
        XCTAssertEqual(store.selectedTab, .profile)
        XCTAssertEqual(store.paths.profile, [.followers(me), .following(me), .rooms])
        XCTAssertTrue(store.paths.feed.isEmpty)

        simulateSystemBack(&store.paths.profile)
        simulateSystemBack(&store.paths.profile)
        simulateSystemBack(&store.paths.profile)
        XCTAssertTrue(store.paths.profile.isEmpty)
    }

    func testTabSwitchPreservesOtherProfileStack() {
        let store = NavigationStore()
        store.sessionPhase = .authenticated
        store.selectedTab = .feed
        let coordinator = NavigationCoordinator(store: store)
        let userA = ProfileID("user-a")

        coordinator.pushFeed(.profile(userA))
        coordinator.pushFollowers(userA)
        coordinator.selectTab(.profile)
        coordinator.pushProfile(.activity)
        coordinator.selectTab(.feed)

        XCTAssertEqual(store.paths.feed, [.profile(userA), .followers(userA)])
        XCTAssertEqual(store.paths.profile, [.activity])
        simulateSystemBack(&store.paths.feed)
        XCTAssertEqual(store.paths.feed, [.profile(userA)])
    }

    func testLogoutClearsAllPaths() {
        let store = NavigationStore()
        store.sessionPhase = .authenticated
        store.paths.home = [.trades]
        store.paths.messages = [.settings(.home)]
        let coordinator = NavigationCoordinator(store: store)

        coordinator.markUnauthenticated()
        XCTAssertTrue(store.paths.home.isEmpty)
        XCTAssertTrue(store.paths.messages.isEmpty)
        XCTAssertTrue(store.paths.profile.isEmpty)
    }

    func testLoggedOutPushStaysOffTheShell() {
        let store = NavigationStore()
        store.sessionPhase = .unauthenticated
        let coordinator = NavigationCoordinator(store: store)
        coordinator.pushHome(.calendar)
        XCTAssertTrue(store.paths.home.isEmpty)
        XCTAssertNotNil(store.pendingAfterAuth)
    }

    func testDemoModeCanPushTheAuthenticatedShell() throws {
        let launch = AppLaunchController.shared
        let wasDemo = launch.isDemoExperienceActive
        if !wasDemo {
            launch.enterBundledDemoExplore()
        }
        guard launch.isDemoExperienceActive else {
            throw XCTSkip("Demo entry requires an unauthenticated launch controller")
        }
        defer {
            if !wasDemo {
                launch.exitDemoExplore()
            }
        }

        let store = NavigationStore()
        store.sessionPhase = .unauthenticated
        let coordinator = NavigationCoordinator(store: store)
        coordinator.markExploreExperience()
        coordinator.pushHome(.calendar)
        coordinator.pushHome(.trades)
        coordinator.pushHome(.activity)
        coordinator.pushHome(.payouts)
        coordinator.pushFeed(.explore)
        coordinator.pushMessages(.thread(ConversationID("demo.thread")))
        coordinator.pushProfileSettingsHome(source: "demo-test")

        XCTAssertEqual(store.sessionPhase, .unauthenticated)
        XCTAssertEqual(store.paths.home, [.calendar, .trades, .activity, .payouts])
        XCTAssertEqual(store.paths.feed, [.explore])
        XCTAssertEqual(store.paths.messages, [.thread(ConversationID("demo.thread"))])
        XCTAssertEqual(store.paths.profile, [.settings(.home)])
        XCTAssertNil(store.pendingAfterAuth)
    }

    func testProfileWithdrawalsOpensDetailOnTheSameStack() {
        let store = NavigationStore()
        store.sessionPhase = .authenticated
        let router = StackNavigation.profile(store: store)
        router.pushSettings(.payouts)
        WithdrawalDetailSelection.stage("ledger:entry-1")
        router.pushSettings(.withdrawalDetail)

        XCTAssertEqual(
            store.paths.profile,
            [.settings(.payouts), .settings(.withdrawalDetail)]
        )
        XCTAssertEqual(WithdrawalDetailSelection.historyItemID, "ledger:entry-1")
        XCTAssertFalse(SettingsHomeModel.sections.flatMap(\.items).map(\.route).contains(.withdrawalDetail))
    }

    func testManualLedgerRowsStayEditableAndPropCyclesStayViewOnly() {
        let manual = PayoutHistoryItem(
            id: "ledger:entry-1",
            amount: 250,
            date: .now,
            accountID: TradingAccountID("account-1"),
            ledgerEntryID: AccountPayoutEntryID("entry-1"),
            source: .liveLedger,
            note: nil
        )
        let cycle = PayoutHistoryItem(
            id: "cycle:cycle-1",
            amount: 250,
            date: .now,
            accountID: TradingAccountID("account-1"),
            ledgerEntryID: nil,
            source: .fundedCycle,
            note: nil
        )
        XCTAssertTrue(manual.isEditable)
        XCTAssertFalse(cycle.isEditable)
    }

    // MARK: - Helpers

    private func coordinatorPushMessagesSettings(store: NavigationStore) {
        let coordinator = NavigationCoordinator(store: store)
        coordinator.pushMessages(.settings(.home))
    }

    private func messagesSettingsRoutes(in store: NavigationStore) -> [SettingsRoute] {
        store.paths.messages.compactMap { route in
            if case .settings(let settings) = route { return settings }
            return nil
        }
    }

    private func homeSettingsRoutes(in store: NavigationStore) -> [SettingsRoute] {
        store.paths.home.compactMap { route in
            if case .settings(let settings) = route { return settings }
            return nil
        }
    }
}
