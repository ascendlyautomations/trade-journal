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

    // MARK: - Flow E (Profile → Activity → Notifications)

    func testFlowE_ProfileActivityNotificationsBackChain() {
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
