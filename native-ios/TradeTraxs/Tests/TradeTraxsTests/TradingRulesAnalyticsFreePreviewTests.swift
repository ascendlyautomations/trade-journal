import XCTest
@testable import TradeTraxs

@MainActor
final class TradingRulesAnalyticsFreePreviewTests: XCTestCase {
    override func tearDown() {
        TradingRulesAnalyticsPreviewSupport.endEphemeralSampleIfNeeded(
            profileID: nil,
            detailCache: DetailPresentationCache()
        )
        TraxsProPreviewSession.shared.endActivePreview(detailCache: DetailPresentationCache())
        TradingRulesComplianceSessionStore.shared.reset()
        TradingRulesCompliancePreferencesCache.resetAll()
        super.tearDown()
    }

    func testEphemeralSampleBuildsAnalyticsWithoutOwnerStoreSeeding() async {
        let profileID = ProfileID("rules-free-preview")
        let cache = DetailPresentationCache()

        TradingRulesAnalyticsPreviewSupport.beginEphemeralSampleIfNeeded(
            profileID: profileID,
            detailCache: cache
        )
        defer {
            TradingRulesAnalyticsPreviewSupport.endEphemeralSampleIfNeeded(
                profileID: profileID,
                detailCache: cache
            )
        }

        XCTAssertTrue(TradingRulesAnalyticsPreviewSupport.showsSampleDataChrome)
        XCTAssertEqual(SessionOwnerTradesStore.shared.cached(for: profileID)?.count ?? 0, 0)

        let accounts = DemoCanonicalDataset.accounts(owner: profileID)
        let scope = PsychologyAnalyticsScopeResolver.resolve(
            filter: TradingRulesAnalyticsPreviewSupport.sampleClientScopeFilter(accounts: accounts),
            profileID: profileID,
            accounts: accounts
        )
        let dependencies = TradingRulesComplianceLoadDependencies(
            detailCache: cache,
            tradesRepository: TradingRulesFreePreviewEmptyTradeRepository()
        )
        let output = await TradingRulesComplianceSnapshotBuilder.build(
            profileID: profileID,
            scope: scope,
            accounts: accounts,
            dependencies: dependencies,
            injectedPreferences: TradingRulesAnalyticsPreviewSupport.resolvedPreferenceContext(for: profileID)
        )
        XCTAssertGreaterThan(output.scopedTradeCount, 0)
        XCTAssertTrue(TradingRulesPlanTier.hasConfiguredFreeTierRules(context: output.preferencesContext))
    }

    func testPreviewIgnoresPersistedProductionAccountFilter() async {
        let profileID = ProfileID("rules-scope-isolation")
        let productionCache = DetailPresentationCache()
        let liveAccountID = TradingAccountID("11111111-1111-4111-8111-111111111111")
        DashboardScopeFilterPersistence.save(
            profileID: profileID,
            stored: DashboardScopeFilterPersistence.Stored(
                dateRangeRaw: DashboardDateRange.thirtyDays.rawValue,
                customStart: nil,
                customEnd: nil,
                accountModeRaw: ProfileStatisticsMetrics.Mode.all.rawValue,
                showPublicOnly: false,
                hasUserSelectedDateRange: true,
                accountFilterKey: liveAccountID.rawValue
            )
        )
        defer {
            UserDefaults.standard.removeObject(
                forKey: "dashboard.scopeFilters.v1.\(profileID.rawValue)"
            )
        }

        let (dependencies, preferenceContext) = beginTradingRulesPreviewIsolated(
            profileID: profileID,
            productionCache: productionCache
        )
        defer {
            TraxsProPreviewSession.shared.endTradingRulesPreview(detailCache: productionCache)
            TraxsProPreviewSession.shared.activePreviewEnvironment?.rulesPresentationStore.reset()
        previewRulesStore().reset()
        }

        let scopeController = TradingRulesAnalyticsScopeController()
        scopeController.hydrate(
            profileID: profileID,
            accounts: DemoCanonicalDataset.accounts(owner: profileID)
        )
        XCTAssertEqual(scopeController.accountFilter, .all)
        XCTAssertEqual(scopeController.dateRange, .oneYear)

        let published = await TradingRulesAnalyticsPreviewSupport.publishBundledSampleSnapshot(
            profileID: profileID,
            dependencies: dependencies,
            preferenceContext: preferenceContext
        )
        XCTAssertTrue(published)
        guard let result = previewRulesStore().result else {
            XCTFail("Expected sample compliance result")
            return
        }
        let rulesStore = previewRulesStore()
        XCTAssertGreaterThan(rulesStore.scopedTradeCount, 0)
        XCTAssertGreaterThan(result.score.evaluated, 0)

        scopeController.dateRange = .thirtyDays
        await scopeController.recomputeImmediately(dependencies: dependencies)
        XCTAssertGreaterThan(rulesStore.scopedTradeCount, 0)
        XCTAssertGreaterThan(rulesStore.result?.score.evaluated ?? 0, 0)
        XCTAssertTrue(rulesStore.hasConfiguredRules)
        XCTAssertNotNil(rulesStore.result)
    }

    func testPublishBundledSampleSnapshotMarksSessionReady() async {
        let profileID = ProfileID("rules-sample-publish")
        let productionCache = DetailPresentationCache()
        let (dependencies, preferenceContext) = beginTradingRulesPreviewIsolated(
            profileID: profileID,
            productionCache: productionCache
        )
        defer {
            TraxsProPreviewSession.shared.endTradingRulesPreview(detailCache: productionCache)
            TraxsProPreviewSession.shared.activePreviewEnvironment?.rulesPresentationStore.reset()
        previewRulesStore().reset()
        }

        let published = await TradingRulesAnalyticsPreviewSupport.publishBundledSampleSnapshot(
            profileID: profileID,
            dependencies: dependencies,
            preferenceContext: preferenceContext
        )

        XCTAssertTrue(published)
        XCTAssertTrue(previewRulesStore().ready)
        XCTAssertEqual(previewRulesStore().profileID, profileID)
        XCTAssertTrue(previewRulesStore().hasConfiguredRules)
        XCTAssertNotNil(previewRulesStore().result)
    }

    func testPreferencesCacheNeverFetchesProductionRulesInSampleMode() async {
        let profileID = ProfileID("rules-prefs-isolation")
        let cache = DetailPresentationCache()

        TradingRulesAnalyticsPreviewSupport.beginEphemeralSampleIfNeeded(
            profileID: profileID,
            detailCache: cache
        )
        defer {
            TradingRulesAnalyticsPreviewSupport.endEphemeralSampleIfNeeded(
                profileID: profileID,
                detailCache: cache
            )
        }

        TradingRulesCompliancePreferencesCache.invalidate(profileID: profileID)

        let preferences = TradingRulesFreePreviewCountingPreferencesRepository()
        let dependencies = TradingRulesComplianceLoadDependencies(
            detailCache: cache,
            tradesRepository: TradingRulesFreePreviewEmptyTradeRepository(),
            tradingPreferences: preferences
        )
        let outcome = await TradingRulesCompliancePreferencesCache.load(
            for: profileID,
            repository: dependencies.tradingPreferences,
            injected: nil
        )

        guard case .loaded(let context) = outcome else {
            XCTFail("Expected sample preferences to load")
            return
        }
        XCTAssertEqual(preferences.fetchCount, 0)
        XCTAssertTrue(TradingRulesPlanTier.hasConfiguredFreeTierRules(context: context))
        XCTAssertFalse(context.global?.primaryInstruments.isEmpty ?? true)
    }

    func testTradingRulesTraxsProPreviewEntryPublishesConfiguredAnalytics() async {
        let profileID = ProfileID("rules-traxspro-preview")
        let productionCache = DetailPresentationCache()
        let (dependencies, preferenceContext) = beginTradingRulesPreviewIsolated(
            profileID: profileID,
            productionCache: productionCache
        )
        defer {
            TraxsProPreviewSession.shared.endTradingRulesPreview(detailCache: productionCache)
            TraxsProPreviewSession.shared.activePreviewEnvironment?.rulesPresentationStore.reset()
        previewRulesStore().reset()
        }

        let published = await TradingRulesAnalyticsPreviewSupport.publishBundledSampleSnapshot(
            profileID: profileID,
            dependencies: dependencies,
            preferenceContext: preferenceContext
        )
        XCTAssertTrue(published)

        let scopeController = TradingRulesAnalyticsScopeController()
        scopeController.hydrate(profileID: profileID, accounts: DemoCanonicalDataset.accounts(owner: profileID))
        await scopeController.recomputeImmediately(dependencies: dependencies)

        XCTAssertTrue(previewRulesStore().ready)
        XCTAssertTrue(previewRulesStore().hasConfiguredRules)
        XCTAssertNotNil(previewRulesStore().result)
        XCTAssertGreaterThan(previewRulesStore().result?.score.evaluated ?? 0, 0)
    }

    func testDashboardPreviewEntryPublishesConfiguredAnalytics() async {
        let profileID = ProfileID("rules-dashboard-preview")
        let productionCache = DetailPresentationCache()

        TraxsProPreviewSession.shared.beginDashboardPreview(
            detailCache: productionCache,
            viewer: profileID
        )
        defer {
            TraxsProPreviewSession.shared.endDashboardPreview(detailCache: productionCache)
            TraxsProPreviewSession.shared.activePreviewEnvironment?.rulesPresentationStore.reset()
        previewRulesStore().reset()
        }

        guard let preview = TraxsProPreviewSession.shared.activePreviewEnvironment,
              preview.viewer == profileID
        else {
            XCTFail("missing preview environment")
            return
        }
        _ = await TradingRulesCompliancePreferencesCache.load(
            for: profileID,
            repository: preview.data.tradingPreferences,
            injected: nil
        )
        XCTAssertNotNil(TradingRulesCompliancePreferencesCache.cachedContext(for: profileID))
        XCTAssertEqual(SessionOwnerTradesStore.shared.cached(for: profileID)?.count ?? 0, 0)

        let dependencies = TradingRulesComplianceLoadDependencies(
            detailCache: preview.data.detailCache,
            tradesRepository: preview.data.trades,
            tradingPreferences: preview.data.tradingPreferences
        )
        let published = await TradingRulesAnalyticsPreviewSupport.publishBundledSampleSnapshot(
            profileID: profileID,
            dependencies: dependencies,
            preferenceContext: preview.preferenceContext
        )
        XCTAssertTrue(published)
        XCTAssertTrue(previewRulesStore().hasConfiguredRules)
        XCTAssertNotNil(previewRulesStore().result)
        XCTAssertGreaterThan(previewRulesStore().scopedTradeCount, 0)
    }

    func testTradeNavigationGuardInSampleMode() {
        let sampleID = DemoCanonicalDataset.trades().first!.id
        let foreignID = TradeID("not-in-sample")

        TradingRulesAnalyticsPreviewSupport.beginEphemeralSampleIfNeeded(
            profileID: ProfileID("rules-guard"),
            detailCache: DetailPresentationCache()
        )
        defer {
            TradingRulesAnalyticsPreviewSupport.endEphemeralSampleIfNeeded(
                profileID: ProfileID("rules-guard"),
                detailCache: DetailPresentationCache()
            )
        }

        XCTAssertTrue(TradingRulesAnalyticsPreviewSupport.allowsTradeDetailNavigation(tradeID: sampleID))
        XCTAssertFalse(TradingRulesAnalyticsPreviewSupport.allowsTradeDetailNavigation(tradeID: foreignID))
    }
}

@MainActor
private func previewRulesStore() -> TradingRulesComplianceSessionStore {
    guard let preview = TraxsProPreviewSession.shared.activePreviewEnvironment else {
        XCTFail("TraxsPro preview environment required")
        return previewRulesStore()
    }
    return preview.rulesPresentationStore
}

@MainActor
private func beginTradingRulesPreviewIsolated(
    profileID: ProfileID,
    productionCache: DetailPresentationCache
) -> (dependencies: TradingRulesComplianceLoadDependencies, preferenceContext: PreferenceRuleContext) {
    TraxsProPreviewSession.shared.beginTradingRulesPreview(
        detailCache: productionCache,
        viewer: profileID
    )
    guard let preview = TraxsProPreviewSession.shared.activePreviewEnvironment else {
        fatalError("TraxsPro preview environment required")
    }
    let dependencies = TradingRulesComplianceLoadDependencies(
        detailCache: preview.data.detailCache,
        tradesRepository: preview.data.trades,
        tradingPreferences: preview.data.tradingPreferences
    )
    return (dependencies, preview.preferenceContext)
}

private final class TradingRulesFreePreviewCountingPreferencesRepository: TradingPreferencesRepository,
    @unchecked Sendable
{
    private let lock = NSLock()
    private(set) var fetchCount = 0

    func globalPreferences(for userID: ProfileID) async throws -> TradingPreferenceGlobal {
        noteFetch()
        return .empty(userID: userID)
    }

    func saveGlobal(_ preferences: TradingPreferenceGlobal) async throws -> TradingPreferenceGlobal {
        noteFetch()
        return preferences
    }

    func accountOverrides(for userID: ProfileID) async throws -> [TradingPreferenceAccountOverride] {
        noteFetch()
        return []
    }

    func saveOverride(
        _ override: TradingPreferenceAccountOverride
    ) async throws -> TradingPreferenceAccountOverride {
        noteFetch()
        return override
    }

    func revisions(for userID: ProfileID) async throws -> [TradingPreferenceRevision] {
        noteFetch()
        return []
    }

    func discovery(for userID: ProfileID) async throws -> PreferenceDiscoveryResponse? {
        noteFetch()
        return nil
    }

    func recordDiscovery(
        _ response: PreferenceDiscoveryResponse,
        for userID: ProfileID
    ) async throws -> PreferenceDiscoveryResponse {
        noteFetch()
        return response
    }

    func hasJournalTrade(for userID: ProfileID) async throws -> Bool {
        noteFetch()
        return false
    }

    private func noteFetch() {
        lock.lock()
        fetchCount += 1
        lock.unlock()
    }
}

private struct TradingRulesFreePreviewEmptyTradeRepository: TradeRepository {
    func trade(id: TradeID) async throws -> Trade {
        throw AppError.unknown(message: "not found")
    }

    func trades(ids: [TradeID]) async throws -> [Trade] { [] }

    func trades(
        ownedBy profileID: ProfileID,
        accountID: TradingAccountID?,
        page: PageRequest,
        publicOnly: Bool
    ) async throws -> CursorPage<Trade> {
        CursorPage(items: [], nextCursor: nil)
    }

    func trades(
        ownedBy profileID: ProfileID,
        accountID: TradingAccountID?,
        entryFrom: Date,
        entryTo: Date,
        limit: Int
    ) async throws -> [Trade] {
        []
    }

    func tradeHistory(
        ownedBy profileID: ProfileID,
        query: TradeHistoryQuery,
        page: PageRequest
    ) async throws -> CursorPage<Trade> {
        CursorPage(items: [], nextCursor: nil)
    }

    func save(_ draft: TradeDraft) async throws -> Trade {
        throw AppError.unknown(message: "stub")
    }

    func saveCopyTraded(_ draft: TradeDraft) async throws -> [Trade] { [] }
    func update(_ trade: Trade) async throws -> Trade { trade }
    func update(id: TradeID, draft: TradeDraft, previous: Trade) async throws -> Trade { previous }
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

    func accounts(for profileID: ProfileID) async throws -> [TradingAccount] { [] }
    func createAccount(ownerID: ProfileID, draft: TradingAccountDraft) async throws -> TradingAccount {
        throw AppError.unknown(message: "stub")
    }
}