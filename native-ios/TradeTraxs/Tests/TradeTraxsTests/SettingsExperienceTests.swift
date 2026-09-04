import XCTest
@testable import TradeTraxs

@MainActor
final class SettingsExperienceTests: XCTestCase {
    func testSettingsHomeSectionsAreDirectoryNotFlatDashboard() {
        let sections = SettingsHomeModel.sections
        XCTAssertFalse(sections.isEmpty)
        XCTAssertTrue(sections.contains { $0.id == "account" })
        XCTAssertTrue(sections.contains { $0.id == "preferences" })
        XCTAssertTrue(sections.contains { $0.id == "legal" })
        let allRoutes = sections.flatMap(\.items).map(\.route)
        XCTAssertTrue(allRoutes.contains(.account))
        XCTAssertTrue(allRoutes.contains(.notifications))
        XCTAssertTrue(allRoutes.contains(.appearance))
        XCTAssertTrue(allRoutes.contains(.subscription))
        XCTAssertFalse(allRoutes.contains(.home))
    }

    func testAppearanceSelectionOnlyRecolorsViaThemeManager() {
        let defaults = UserDefaults(suiteName: "settings.appearance.tests.\(UUID().uuidString)")!
        let manager = ThemeManager(
            persistence: UserDefaultsThemePersistence(defaults: defaults)
        )
        manager.select(.system)
        let viewModel = SettingsAppearanceViewModel(themeManager: manager)
        XCTAssertEqual(viewModel.model.options.map(\.id), [.system, .tradeTraxs])
        viewModel.select(.tradeTraxs, reduceMotion: true)
        XCTAssertEqual(manager.selectedIdentifier, .tradeTraxs)
        XCTAssertEqual(viewModel.model.selectedTheme, .tradeTraxs)
    }

    func testProfileSettingsAppendSingleHomeRoute() {
        let store = NavigationStore()
        store.sessionPhase = .authenticated
        store.selectedTab = .profile
        let coordinator = NavigationCoordinator(store: store)

        coordinator.pushProfile(.settings(.home))
        XCTAssertEqual(store.selectedTab, .profile)
        XCTAssertEqual(profileSettingsRoutes(in: store), [.home])
    }

    func testRepeatedSettingsOpenAppendsWithoutReplacingActivity() {
        let store = NavigationStore()
        store.sessionPhase = .authenticated
        store.selectedTab = .profile
        store.paths.profile = [.activity]
        let coordinator = NavigationCoordinator(store: store)

        coordinator.pushProfile(.settings(.home))
        XCTAssertEqual(store.paths.profile, [.activity, .settings(.home)])
    }

    func testMessagesSettingsAppendSingleHomeRoute() {
        let store = NavigationStore()
        store.sessionPhase = .authenticated
        store.selectedTab = .messages
        let coordinator = NavigationCoordinator(store: store)

        coordinator.pushMessages(.settings(.home))
        XCTAssertEqual(store.selectedTab, .messages)
        XCTAssertEqual(messagesSettingsRoutes(in: store), [.home])
    }

    func testDeepLinkSettingsNotificationsMessages() {
        let parser = DeepLinkParser()
        let destination = parser.parse(url: URL(string: "tradetraxs://settings/notifications/messages")!)
        guard case .settingsStack(let routes) = destination else {
            return XCTFail("Expected settingsStack, got \(String(describing: destination))")
        }
        XCTAssertEqual(routes, [.home, .notifications, .notificationsMessages])
    }

    func testDeepLinkSettingsSubscription() {
        let parser = DeepLinkParser()
        let destination = parser.parse(url: URL(string: "https://www.tradetraxs.com/settings/subscription")!)
        guard case .settingsStack(let routes) = destination else {
            return XCTFail("Expected settingsStack")
        }
        XCTAssertEqual(routes, [.home, .subscription])
    }

    func testNotificationPreferenceDefaultsAndMasterGate() {
        var prefs = NotificationPreferences.defaults(for: SettingsFixtures.viewerID)
        XCTAssertTrue(prefs.isEnabled(.directMessagesEnabled))
        prefs.set(.notificationsEnabled, enabled: false)
        XCTAssertFalse(prefs.isEnabled(.directMessagesEnabled))
        XCTAssertFalse(prefs.isEnabled(.notificationsEnabled))
    }

    func testNotificationsViewModelPersistsToggleAndRevertsOnFailure() async {
        let repository = SettingsStubNotificationPreferencesRepository()
        let navigation = NavigationCoordinator(store: NavigationStore())
        let viewModel = SettingsNotificationsViewModel(
            repository: repository,
            session: SettingsStubSession(userID: SettingsFixtures.viewerID.rawValue),
            navigationCoordinator: navigation
        )

        viewModel.loadIfNeeded()
        await waitFor { viewModel.phase == .loaded }
        XCTAssertEqual(viewModel.binding(for: .directMessagesEnabled), true)

        viewModel.set(.directMessagesEnabled, enabled: false)
        await waitFor { repository.lastPatch[.directMessagesEnabled] == false }
        XCTAssertEqual(viewModel.binding(for: .directMessagesEnabled), false)

        repository.shouldFailUpdates = true
        viewModel.set(.directMessagesEnabled, enabled: true)
        await waitFor { viewModel.saveError != nil }
        XCTAssertEqual(viewModel.binding(for: .directMessagesEnabled), false)
    }

    func testSubscriptionViewModelLoadsBillingStatus() async {
        let billing = SettingsStubBillingRepository(status: SettingsFixtures.billingStatus())
        let viewModel = SettingsSubscriptionViewModel(
            billing: billing,
            session: SettingsStubSession(userID: SettingsFixtures.viewerID.rawValue),
            navigationCoordinator: NavigationCoordinator(store: NavigationStore())
        )
        viewModel.loadIfNeeded()
        await waitFor { viewModel.status != nil }
        XCTAssertEqual(viewModel.planTitle, "TraxPro")
    }

    func testAboutUsesBundleVersionMetadata() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        XCTAssertNotNil(version)
        XCTAssertFalse(version?.isEmpty == true)
        XCTAssertNotNil(build)
    }

    func testLogoutClearsProfileSettingsStack() {
        let store = NavigationStore()
        store.sessionPhase = .authenticated
        store.paths.profile = [.settings(.home), .settings(.account)]
        let coordinator = NavigationCoordinator(store: store)
        coordinator.markUnauthenticated()
        XCTAssertEqual(store.sessionPhase, .unauthenticated)
        XCTAssertTrue(store.paths.profile.isEmpty)
    }

    func testLegalRoutesAreRoutable() {
        for route in [SettingsRoute.legalTerms, .legalPrivacy, .legalCommunityGuidelines, .legalRefund] {
            XCTAssertEqual(SettingsRoute.fromDeepLinkSegment(route.rawValue), route)
            XCTAssertFalse(route.title.isEmpty)
        }
    }

    func testStackNavigationAppendsToMessagesPath() {
        let store = NavigationStore()
        let router = StackNavigation.messages(store: store)
        router.pushSettings(.notifications)
        XCTAssertEqual(messagesSettingsRoutes(in: store), [.notifications])
    }

    private func profileSettingsRoutes(in store: NavigationStore) -> [SettingsRoute] {
        store.paths.profile.compactMap { route in
            if case .settings(let settings) = route { return settings }
            return nil
        }
    }

    private func messagesSettingsRoutes(in store: NavigationStore) -> [SettingsRoute] {
        store.paths.messages.compactMap { route in
            if case .settings(let settings) = route { return settings }
            return nil
        }
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

private struct SettingsStubSession: SessionProviding {
    let userID: String?
    var currentUserID: UserID? {
        get async {
            guard let userID else { return nil }
            return UserID(userID)
        }
    }

    var accessToken: String? {
        get async { userID == nil ? nil : "test-token" }
    }
}

private final class SettingsStubNotificationPreferencesRepository: NotificationPreferencesRepository, @unchecked Sendable {
    var shouldFailUpdates = false
    private(set) var lastPatch: [NotificationPreferenceKey: Bool] = [:]
    private var stored = SettingsFixtures.preferences()

    func preferences(for userID: ProfileID) async throws -> NotificationPreferences {
        stored.userID = userID
        return stored
    }

    func update(
        _ patch: [NotificationPreferenceKey: Bool],
        for userID: ProfileID
    ) async throws -> NotificationPreferences {
        lastPatch = patch
        if shouldFailUpdates {
            throw AppError.unknown(message: "forced failure")
        }
        for (key, value) in patch {
            stored.set(key, enabled: value)
        }
        stored.userID = userID
        return stored
    }
}

private struct SettingsStubBillingRepository: BillingRepository {
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
