import XCTest
@testable import TradeTraxs

@MainActor
final class SettingsExperienceTests: XCTestCase {
    func testSettingsHomeSectionsAreDirectoryNotFlatDashboard() {
        let sections = SettingsHomeModel.sections
        XCTAssertFalse(sections.isEmpty)
        XCTAssertTrue(sections.contains { $0.id == "account" })
        XCTAssertTrue(sections.contains { $0.id == "tradetraxs" })
        XCTAssertTrue(sections.contains { $0.id == "legal" })
        let supportItems = sections.first { $0.id == "support" }?.items.map(\.route) ?? []
        XCTAssertTrue(supportItems.contains(.support))
        XCTAssertTrue(supportItems.contains(.productFeedback))
        let allRoutes = sections.flatMap(\.items).map(\.route)
        XCTAssertTrue(allRoutes.contains(.account))
        XCTAssertTrue(allRoutes.contains(.privacy))
        XCTAssertTrue(allRoutes.contains(.notifications))
        XCTAssertTrue(allRoutes.contains(.appearance))
        XCTAssertEqual(
            allRoutes.contains(.subscription),
            IosSubscriptionReleaseConfiguration.iosPaidSubscriptionsEnabled
        )
        XCTAssertEqual(
            allRoutes.contains(.affiliate),
            IosSubscriptionReleaseConfiguration.iosReferralProgramEnabled
        )
        XCTAssertFalse(allRoutes.contains(.security))
        XCTAssertFalse(allRoutes.contains(.home))
    }

    func testAppearanceSelectionOnlyRecolorsViaThemeManager() {
        let defaults = UserDefaults(suiteName: "settings.appearance.tests.\(UUID().uuidString)")!
        let manager = ThemeManager(
            persistence: UserDefaultsThemePersistence(defaults: defaults)
        )
        manager.select(.system)
        let viewModel = SettingsAppearanceViewModel(themeManager: manager)
        XCTAssertEqual(viewModel.model.options.map(\.id), [.system, .light, .dark])
        viewModel.select(.dark, reduceMotion: true)
        XCTAssertEqual(manager.selectedIdentifier, .dark)
        XCTAssertEqual(viewModel.model.selectedTheme, .dark)
    }

    func testProfileSettingsAppendSingleHomeRoute() {
        let store = NavigationStore()
        store.sessionPhase = .authenticated
        store.selectedTab = .profile
        let coordinator = NavigationCoordinator(store: store)

        coordinator.pushProfileSettingsHome(source: "test")
        XCTAssertEqual(store.selectedTab, .profile)
        XCTAssertEqual(profileSettingsRoutes(in: store), [.home])
    }

    func testRepeatedProfileSettingsHomeOpenIsIdempotent() {
        let store = NavigationStore()
        store.sessionPhase = .authenticated
        store.selectedTab = .profile
        let coordinator = NavigationCoordinator(store: store)

        coordinator.pushProfileSettingsHome(source: "test")
        coordinator.pushProfileSettingsHome(source: "test")
        XCTAssertEqual(store.paths.profile, [.settings(.home)])

        store.paths.profile = [.settings(.home), .settings(.account)]
        coordinator.pushProfileSettingsHome(source: "test")
        XCTAssertEqual(store.paths.profile, [.settings(.home)])
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
        if IosSubscriptionReleaseConfiguration.iosPaidSubscriptionsEnabled {
            XCTAssertEqual(routes, [.home, .subscription])
        } else {
            XCTAssertEqual(routes, [.home])
        }
    }

    func testDeepLinkSettingsBrokerIntegrations() {
        let parser = DeepLinkParser()
        let destination = parser.parse(
            url: URL(string: "tradetraxs://settings/broker-integrations/tradovate?status=success")!
        )
        guard case .settingsStack(let routes) = destination else {
            return XCTFail("Expected settingsStack")
        }
        XCTAssertEqual(routes, [.home, .tradingAccounts, .brokerIntegrations])
        XCTAssertTrue(NativeOAuthConfiguration.isTradovateBrokerOAuthCallbackURL(
            URL(string: "tradetraxs://settings/broker-integrations/tradovate?status=success")!
        ))
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
            storeKit: SettingsStubStoreKit(),
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

    func testTraderTypeAndTradingStyleChangesPreserveUnsavedDraftUntilSave() async {
        let profileID = SettingsFixtures.viewerID
        let repository = SettingsProfileDraftTestRepository(profile: SettingsFixtures.profile())
        let viewModel = SettingsProfileViewModel(
            profiles: repository,
            session: SettingsStubSession(userID: profileID.rawValue)
        )

        await viewModel.refresh()

        viewModel.draftDisplayName = "New Name"
        viewModel.draftUsername = "newusername"
        viewModel.draftBio = "New Bio"

        viewModel.setTraderType(.options)

        XCTAssertEqual(viewModel.draftDisplayName, "New Name")
        XCTAssertEqual(viewModel.draftUsername, "newusername")
        XCTAssertEqual(viewModel.draftBio, "New Bio")
        XCTAssertEqual(viewModel.draftTraderType, .options)
        XCTAssertEqual(repository.updateProfileCalls, 0)

        viewModel.draftTradingStyle = "Scalping"

        XCTAssertEqual(viewModel.draftDisplayName, "New Name")
        XCTAssertEqual(viewModel.draftUsername, "newusername")
        XCTAssertEqual(viewModel.draftBio, "New Bio")
        XCTAssertEqual(viewModel.draftTraderType, .options)

        viewModel.save()
        await waitFor { !viewModel.isSaving && !repository.updateProfileSettingsCalls.isEmpty }

        XCTAssertEqual(repository.updateProfileSettingsCalls.count, 1)
        let update = repository.updateProfileSettingsCalls[0]
        XCTAssertEqual(update.displayName, "New Name")
        XCTAssertEqual(update.username, "newusername")
        XCTAssertEqual(update.bio, "New Bio")
        XCTAssertEqual(update.traderType, .options)
        XCTAssertEqual(update.tradingStyle, "Scalping")
        XCTAssertEqual(repository.updateProfileCalls, 0)
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

private struct SettingsStubStoreKit: StoreKitSubscriptionServicing {
    func loadProducts() async throws -> [StoreKitTraxProProduct] { [] }
    func purchase(productID: String, appAccountToken: UUID?) async -> StoreKitPurchaseOutcome { .userCancelled }
    func restorePurchases() async throws -> Bool { false }
    func syncVerifiedTransactionsToServer() async throws {}
    func startTransactionListenerIfNeeded() async {}
    func presentOfferCodeRedemption() async throws {}
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

private final class SettingsProfileDraftTestRepository: ProfileRepository, @unchecked Sendable {
    var ownerProfile: Profile
    private(set) var updateProfileSettingsCalls: [ProfileSettingsUpdate] = []
    private(set) var updateProfileCalls = 0

    init(profile: Profile) {
        ownerProfile = profile
    }

    func currentUser() async throws -> User {
        User(id: UserID(ownerProfile.id.rawValue), email: nil, createdAt: .now)
    }

    func profile(id: ProfileID) async throws -> Profile {
        ownerProfile
    }

    func profile(username: String) async throws -> Profile {
        ownerProfile
    }

    func updateProfile(_ profile: Profile) async throws -> Profile {
        updateProfileCalls += 1
        ownerProfile = profile
        return profile
    }

    func ownerProfileForSettings(id: ProfileID) async throws -> Profile {
        ownerProfile
    }

    func updateProfileSettings(_ update: ProfileSettingsUpdate) async throws -> Profile {
        updateProfileSettingsCalls.append(update)
        ownerProfile.displayName = update.displayName
        ownerProfile.bio = update.bio
        ownerProfile.tradingStyle = update.tradingStyle
        ownerProfile.primaryMarket = update.primaryMarket
        ownerProfile.isPrivate = update.isPrivate
        ownerProfile.username = update.username
        ownerProfile.usernameChangeCount = update.usernameChangeCount
        if let traderType = update.traderType {
            ownerProfile.traderType = traderType
        }
        return ownerProfile
    }

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
        throw AppError.notImplemented(feature: "wallPost")
    }

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
