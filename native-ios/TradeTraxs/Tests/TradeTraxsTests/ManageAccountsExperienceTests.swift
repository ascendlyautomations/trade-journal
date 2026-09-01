import XCTest
@testable import TradeTraxs

@MainActor
final class ManageAccountsExperienceTests: XCTestCase {
    override func setUp() {
        super.setUp()
        SessionAccountsStore.shared.invalidate()
        AccountMutationStore.shared.invalidate()
    }

    override func tearDown() {
        SessionAccountsStore.shared.invalidate()
        AccountMutationStore.shared.invalidate()
        super.tearDown()
    }

    func testTradingAccountsRouteTitleIsManageAccounts() {
        XCTAssertEqual(SettingsRoute.tradingAccounts.title, "Manage Accounts")
    }

    func testDashboardOpenManageAccountsPreservesAccountFilter() async {
        let store = NavigationStore()
        store.sessionPhase = .authenticated
        let coordinator = NavigationCoordinator(store: store)
        let viewModel = DashboardViewModel(
            home: ManageAccountsStubHomeRepository(),
            trades: ManageAccountsStubTradeRepository(),
            achievements: ManageAccountsStubAchievementRepository(),
            session: ManageAccountsStubSession(userID: "dev.manage.accounts"),
            detailCache: DetailPresentationCache(),
            navigationCoordinator: coordinator
        )
        viewModel.loadIfNeeded()
        await waitFor { viewModel.phase == .loaded }

        let accountID = viewModel.accounts.first!.id
        viewModel.setAccountFilter(.account(accountID))
        XCTAssertEqual(viewModel.accountFilter, .account(accountID))

        viewModel.openManageAccounts()

        XCTAssertEqual(store.selectedTab, .home)
        XCTAssertEqual(homeSettingsRoutes(in: store), [.tradingAccounts])
        XCTAssertTrue(store.paths.profile.isEmpty)
        XCTAssertEqual(viewModel.accountFilter, .account(accountID))
    }

    func testCalendarOpenManageAccountsPreservesAccountFilter() async {
        let store = NavigationStore()
        store.sessionPhase = .authenticated
        let coordinator = NavigationCoordinator(store: store)
        let viewModel = CalendarViewModel(
            trades: ManageAccountsStubTradeRepository(),
            session: ManageAccountsStubSession(userID: "dev.manage.accounts"),
            detailCache: DetailPresentationCache(),
            navigationCoordinator: coordinator
        )
        viewModel.loadIfNeeded()
        await waitFor { viewModel.phase == .loaded }

        let accountID = viewModel.accounts.first!.id
        viewModel.setAccountFilter(.account(accountID))
        viewModel.openManageAccounts()

        XCTAssertEqual(store.selectedTab, .home)
        XCTAssertEqual(homeSettingsRoutes(in: store), [.tradingAccounts])
        XCTAssertTrue(store.paths.profile.isEmpty)
        XCTAssertEqual(viewModel.accountFilter, .account(accountID))
    }

    func testManageAccountsCreateUpdateActivateBroadcastsMutation() async {
        let repository = ManageAccountsMutatingTradeRepository()
        let cache = DetailPresentationCache()
        let viewModel = ManageAccountsViewModel(
            trades: repository,
            session: ManageAccountsStubSession(userID: SettingsFixtures.viewerID.rawValue),
            detailCache: cache
        )
        viewModel.loadIfNeeded()
        await waitFor { !viewModel.accounts.isEmpty }

        let beforeRevision = AccountMutationStore.shared.revision
        let draft = TradingAccountDraft(
            name: "Apex 50K",
            sizeDigits: "50000",
            accountNumber: "APX-1",
            category: .propFirm,
            mode: .evaluation,
            note: "Eval",
            propFirmRules: PropFirmAccountRules(maxDrawdown: 2_000, profitTarget: 3_000)
        )
        let created = await viewModel.create(draft)
        XCTAssertTrue(created)
        XCTAssertEqual(AccountMutationStore.shared.revision, beforeRevision + 1)
        XCTAssertTrue(viewModel.accounts.contains { $0.name == "Apex 50K" })
        XCTAssertEqual(cache.accounts(for: SettingsFixtures.viewerID)?.count, viewModel.accounts.count)

        let id = viewModel.accounts.first { $0.name == "Apex 50K" }!.id
        var edit = draft
        edit.name = "Apex 50K Funded"
        edit.mode = .funded
        let updated = await viewModel.update(id: id, draft: edit)
        XCTAssertTrue(updated)
        XCTAssertEqual(AccountMutationStore.shared.revision, beforeRevision + 2)
        XCTAssertTrue(viewModel.accounts.contains { $0.name == "Apex 50K Funded" && $0.mode == .funded })

        await viewModel.setActive(id: id, isActive: false)
        XCTAssertEqual(AccountMutationStore.shared.revision, beforeRevision + 3)
        XCTAssertEqual(viewModel.accounts.first { $0.id == id }?.isActive, false)
    }

    func testWriteBodyMatchesWebAccountFields() {
        let body = TradingAccountMapper.writeBody(
            ownerID: ProfileID("user-1"),
            draft: TradingAccountDraft(
                name: "Personal Live",
                sizeDigits: "25000",
                accountNumber: "ACC-9",
                category: .personal,
                mode: .live,
                note: "Main",
                propFirmRules: nil
            ),
            isActive: true,
            canAddTrades: true
        )
        XCTAssertEqual(body.user_id, "user-1")
        XCTAssertEqual(body.name, "Personal Live")
        XCTAssertEqual(body.account_size, "25000")
        XCTAssertEqual(body.account_number, "ACC-9")
        XCTAssertEqual(body.category, "Personal")
        XCTAssertEqual(body.mode, "Live")
        XCTAssertEqual(body.is_active, true)
        XCTAssertEqual(body.can_add_trades, true)
        XCTAssertEqual(body.note, "Main")
        XCTAssertNil(body.max_drawdown)

        let prop = TradingAccountMapper.writeBody(
            ownerID: nil,
            draft: TradingAccountDraft(
                name: "Alpha",
                sizeDigits: "50000",
                accountNumber: "",
                category: .propFirm,
                mode: .funded,
                note: "",
                propFirmRules: PropFirmAccountRules(
                    consistencyPercent: 40,
                    maxDrawdown: 2_000,
                    dailyDrawdown: 1_000,
                    profitTarget: 3_000,
                    winningDaysRequired: 5,
                    winningDayThreshold: 100
                )
            )
        )
        XCTAssertEqual(prop.category, "Prop Firm")
        XCTAssertEqual(prop.mode, "Funded")
        XCTAssertEqual(prop.consistency, 40)
        XCTAssertEqual(prop.max_drawdown, 2_000)
        XCTAssertEqual(prop.daily_drawdown, 1_000)
        XCTAssertEqual(prop.profit_target, 3_000)
        XCTAssertEqual(prop.winning_days, 5)
        XCTAssertEqual(prop.winning_day_threshold, 100)
    }

    func testSubtitleSurfacesReadOnlyAndInactive() {
        let viewModel = ManageAccountsViewModel(
            trades: ManageAccountsStubTradeRepository(),
            session: ManageAccountsStubSession(userID: SettingsFixtures.viewerID.rawValue),
            detailCache: DetailPresentationCache()
        )
        var account = SettingsFixtures.accounts()[0]
        account.canAddTrades = false
        account.isActive = false
        let subtitle = viewModel.subtitle(for: account)
        XCTAssertTrue(subtitle.contains("Read Only"))
        XCTAssertTrue(subtitle.contains("Inactive"))
    }

    // MARK: - Helpers

    private func homeSettingsRoutes(in store: NavigationStore) -> [SettingsRoute] {
        store.paths.home.compactMap { route in
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

private struct ManageAccountsStubSession: SessionProviding {
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

private final class ManageAccountsStubTradeRepository: TradeRepository, @unchecked Sendable {
    func trade(id: TradeID) async throws -> Trade {
        throw AppError.unknown(message: "not found")
    }

    func trades(
        ownedBy profileID: ProfileID,
        accountID: TradingAccountID?,
        page: PageRequest,
        publicOnly: Bool
    ) async throws -> CursorPage<Trade> {
        CursorPage(items: ProfileTradeFixtures.samples(owner: profileID), nextCursor: nil)
    }

    func save(_ draft: TradeDraft) async throws -> Trade {
        throw AppError.unknown(message: "stub")
    }

    func update(_ trade: Trade) async throws -> Trade { trade }
    func delete(id: TradeID) async throws {}
    func images(for tradeID: TradeID) async throws -> [TradeImage] { [] }
    func notes(for tradeID: TradeID) async throws -> [TradeNote] { [] }

    func statistics(
        for profileID: ProfileID,
        interval: DateIntervalValue
    ) async throws -> TradeStatistics {
        TradeStatistics(
            tradeCount: 0,
            winCount: 0,
            lossCount: 0,
            totalPnL: Money(amount: 0),
            averagePnL: Money(amount: 0),
            averageRiskReward: nil,
            winRate: 0
        )
    }

    func accounts(for profileID: ProfileID) async throws -> [TradingAccount] {
        SettingsFixtures.accounts(owner: profileID)
    }
}

private final class ManageAccountsMutatingTradeRepository: TradeRepository, @unchecked Sendable {
    private var stored: [TradingAccount] = SettingsFixtures.accounts()

    func trade(id: TradeID) async throws -> Trade {
        throw AppError.unknown(message: "not found")
    }

    func trades(
        ownedBy profileID: ProfileID,
        accountID: TradingAccountID?,
        page: PageRequest,
        publicOnly: Bool
    ) async throws -> CursorPage<Trade> {
        CursorPage(items: [], nextCursor: nil)
    }

    func save(_ draft: TradeDraft) async throws -> Trade {
        throw AppError.unknown(message: "stub")
    }

    func update(_ trade: Trade) async throws -> Trade { trade }
    func delete(id: TradeID) async throws {}
    func images(for tradeID: TradeID) async throws -> [TradeImage] { [] }
    func notes(for tradeID: TradeID) async throws -> [TradeNote] { [] }

    func statistics(
        for profileID: ProfileID,
        interval: DateIntervalValue
    ) async throws -> TradeStatistics {
        TradeStatistics(
            tradeCount: 0,
            winCount: 0,
            lossCount: 0,
            totalPnL: Money(amount: 0),
            averagePnL: Money(amount: 0),
            averageRiskReward: nil,
            winRate: 0
        )
    }

    func accounts(for profileID: ProfileID) async throws -> [TradingAccount] {
        stored.map { account in
            var copy = account
            copy.ownerProfileID = profileID
            return copy
        }
    }

    func createAccount(ownerID: ProfileID, draft: TradingAccountDraft) async throws -> TradingAccount {
        let created = TradingAccount(
            id: TradingAccountID(UUID().uuidString),
            ownerProfileID: ownerID,
            name: draft.name,
            category: draft.category,
            mode: draft.mode,
            size: Decimal(string: draft.sizeDigits).map { Money(amount: $0) },
            isActive: true,
            canAddTrades: true,
            accountNumber: draft.accountNumber.isEmpty ? nil : draft.accountNumber,
            note: draft.note.isEmpty ? nil : draft.note,
            propFirmRules: draft.propFirmRules
        )
        stored.append(created)
        return created
    }

    func updateAccount(
        id: TradingAccountID,
        ownerID: ProfileID,
        draft: TradingAccountDraft
    ) async throws -> TradingAccount {
        guard let index = stored.firstIndex(where: { $0.id == id }) else {
            throw AppError.unknown(message: "Account not found")
        }
        var account = stored[index]
        account.name = draft.name
        account.category = draft.category
        account.mode = draft.mode
        account.size = Decimal(string: draft.sizeDigits).map { Money(amount: $0) }
        account.accountNumber = draft.accountNumber.isEmpty ? nil : draft.accountNumber
        account.note = draft.note.isEmpty ? nil : draft.note
        account.propFirmRules = draft.category == .propFirm ? draft.propFirmRules : nil
        account.ownerProfileID = ownerID
        stored[index] = account
        return account
    }

    func setAccountActive(id: TradingAccountID, isActive: Bool) async throws {
        guard let index = stored.firstIndex(where: { $0.id == id }) else { return }
        stored[index].isActive = isActive
    }
}

private final class ManageAccountsStubHomeRepository: HomeRepository, @unchecked Sendable {
    func dashboard(for profileID: ProfileID) async throws -> HomeDashboard {
        HomeDashboard(
            summary: PerformanceSummary(
                interval: DateIntervalValue(start: Date(), end: Date()),
                statistics: TradeStatistics(
                    tradeCount: 0,
                    winCount: 0,
                    lossCount: 0,
                    totalPnL: Money(amount: 0),
                    averagePnL: Money(amount: 0),
                    averageRiskReward: nil,
                    winRate: 0
                ),
                bestTradeID: nil,
                worstTradeID: nil,
                currentStreakDays: 0
            ),
            widgets: [],
            insights: [],
            shortcutDestinations: [],
            refreshedAt: Date()
        )
    }

    func performance(
        for profileID: ProfileID,
        interval: DateIntervalValue
    ) async throws -> PerformanceSummary {
        try await dashboard(for: profileID).summary
    }
}

private final class ManageAccountsStubAchievementRepository: AchievementRepository, @unchecked Sendable {
    func achievement(id: AchievementID) async throws -> Achievement {
        throw AppError.unknown(message: "not found")
    }

    func achievements(
        for profileID: ProfileID,
        page: PageRequest,
        publicOnly: Bool
    ) async throws -> CursorPage<Achievement> {
        CursorPage(items: [], nextCursor: nil)
    }

    func save(_ achievement: Achievement) async throws -> Achievement { achievement }
}
