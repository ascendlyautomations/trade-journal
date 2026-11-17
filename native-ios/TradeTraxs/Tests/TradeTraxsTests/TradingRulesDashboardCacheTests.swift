import SwiftUI
import XCTest
@testable import TradeTraxs

@MainActor
final class TradingRulesDashboardCacheTests: XCTestCase {
    private let profileA = ProfileID("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")
    private let profileB = ProfileID("bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")
    private let accountA = TradingAccountID("cccccccc-cccc-4ccc-8ccc-cccccccccccc")

    override func tearDown() {
        TradingRulesComplianceRecomputeCoordinator.resetForSessionBoundary()
        TradingRulesCompliancePreferencesCache.invalidate(profileID: profileA)
        TradingRulesCompliancePreferencesCache.invalidate(profileID: profileB)
        DashboardHomeSurfaceGate.resetForTesting()
        SessionViewerGate.shared.resetForTesting()
        BackendV2FeatureFlags.resetFlagsForTests()
        DashboardTabModelStore.clearForTesting()
        super.tearDown()
    }

    func testDashboardFeedClipsReturnDoesNotColdLoad() async {
        let preferences = CountingTradingPreferencesRepository()
        var allocations = 0
        let dashboard = DashboardTabModelStore.model(retainsTabPresentation: true) {
            allocations += 1
            return makeViewModel(preferences: preferences)
        }
        let trade = sampleTrade(owner: profileA)
        dashboard.seedLocalDashboardForTradingRules(
            profileID: profileA,
            preferences: configuredPreferences(profileID: profileA),
            trades: [trade]
        )
        dashboard.accountFilter = .account(accountA)
        dashboard.rememberScrollOffset(240)
        dashboard.recomputeTradingRulesCompliance()
        await waitUntil { TradingRulesComplianceSessionStore.shared.hasConfiguredRules }

        dashboard.setHomeTabActive(false)
        dashboard.onDisappear()

        let returned = DashboardTabModelStore.model(retainsTabPresentation: true) {
            allocations += 1
            return makeViewModel(preferences: preferences)
        }
        XCTAssertEqual(allocations, 1)
        XCTAssertTrue(dashboard === returned)

        DashboardLoadProbe.beginSession()
        XCTAssertEqual(DashboardLoadProbe.coldAttemptCountForTests(), 0)
        returned.setHomeTabActive(true)
        returned.loadIfNeeded()
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(DashboardLoadProbe.coldAttemptCountForTests(), 0)
        XCTAssertFalse(returned.hasInFlightLoad)
        XCTAssertTrue(returned.hasLoaded)
        XCTAssertEqual(preferences.fetchCount, 0)
        XCTAssertEqual(returned.accountFilter, .account(accountA))
        XCTAssertEqual(returned.retainedScrollOffset, 240)
        XCTAssertTrue(TradingRulesComplianceSessionStore.shared.hasConfiguredRules)
        let anchor = DashboardScrollAnchor(restoredOffset: returned.retainedScrollOffset)
        anchor.binding.wrappedValue = ScrollPosition(y: 480)
        XCTAssertEqual(returned.retainedScrollOffset, 240)
        if let y = anchor.binding.wrappedValue.point?.y {
            XCTAssertEqual(anchor.offset, y)
        } else {
            XCTAssertEqual(anchor.offset, 240)
        }

        DashboardSessionBoundary.resetInMemoryPresentation()
        XCTAssertFalse(returned.hasLoaded)
        XCTAssertNil(returned.retainedScrollOffset)
        XCTAssertEqual(returned.accountFilter, .all)
        DashboardLoadProbe.beginSession()
        returned.loadIfNeeded()
        await waitUntil { DashboardLoadProbe.coldAttemptCountForTests() == 1 }
        returned.resetForSessionBoundary()
    }

    func testRulesRemainVisibleAfterLeavingAndReturningToDashboard() async {
        let preferences = CountingTradingPreferencesRepository()
        let viewModel = makeViewModel(preferences: preferences)
        let trade = sampleTrade(owner: profileA)
        viewModel.seedLocalDashboardForTradingRules(
            profileID: profileA,
            preferences: configuredPreferences(profileID: profileA),
            trades: [trade]
        )
        viewModel.recomputeTradingRulesCompliance()
        await waitUntil { TradingRulesComplianceSessionStore.shared.result != nil }

        let store = TradingRulesComplianceSessionStore.shared
        let adherence = store.dashboardAdherencePercent
        XCTAssertTrue(store.hasConfiguredRules)
        XCTAssertNotNil(store.result)
        XCTAssertEqual(preferences.fetchCount, 0)

        viewModel.setHomeTabActive(false)
        viewModel.onDisappear()
        viewModel.setHomeTabActive(true)
        viewModel.loadIfNeeded()

        XCTAssertTrue(store.hasConfiguredRules)
        XCTAssertNotNil(store.result)
        XCTAssertEqual(store.profileID, profileA)
        XCTAssertEqual(store.dashboardAdherencePercent, adherence)
        XCTAssertEqual(preferences.fetchCount, 0)
    }

    func testNilPreferenceContextDoesNotReplaceConfiguredRules() async {
        let viewModel = makeViewModel(preferences: CountingTradingPreferencesRepository())
        viewModel.seedLocalDashboardForTradingRules(
            profileID: profileA,
            preferences: configuredPreferences(profileID: profileA),
            trades: [sampleTrade(owner: profileA)]
        )
        viewModel.recomputeTradingRulesCompliance()
        await waitUntil { TradingRulesComplianceSessionStore.shared.result != nil }

        let store = TradingRulesComplianceSessionStore.shared
        let revision = store.contentRevision
        let adherence = store.dashboardAdherencePercent
        TradingRulesCompliancePreferencesCache.invalidate(profileID: profileA)
        viewModel.forgetInMemoryTradingRulesPreferences()
        viewModel.recomputeTradingRulesCompliance()

        XCTAssertTrue(store.retainsConfiguredRules(for: profileA))
        XCTAssertNotNil(store.result)
        XCTAssertEqual(store.dashboardAdherencePercent, adherence)
        XCTAssertEqual(store.contentRevision, revision)
    }

    func testSameTimeframeRecomputeRestoresInvalidSnapshot() async {
        let viewModel = makeViewModel(preferences: CountingTradingPreferencesRepository())
        viewModel.seedLocalDashboardForTradingRules(
            profileID: profileA,
            preferences: configuredPreferences(profileID: profileA),
            trades: [sampleTrade(owner: profileA)]
        )
        let timeframe = viewModel.dateRange
        viewModel.recomputeTradingRulesCompliance()
        await waitUntil { TradingRulesComplianceSessionStore.shared.result != nil }

        let store = TradingRulesComplianceSessionStore.shared
        store.publish(
            ready: true,
            profileID: profileA,
            scopeFingerprint: store.scopeFingerprint,
            scopeLabel: store.scopeLabel,
            hasConfiguredRules: false,
            result: nil,
            error: nil
        )
        XCTAssertFalse(store.hasConfiguredRules)

        viewModel.recomputeTradingRulesCompliance()
        await waitUntil { TradingRulesComplianceSessionStore.shared.hasConfiguredRules && store.result != nil }

        XCTAssertEqual(viewModel.dateRange, timeframe)
        XCTAssertTrue(store.hasConfiguredRules)
        XCTAssertNotNil(store.result)
        XCTAssertEqual(store.profileID, profileA)
    }

    func testStaleCompletionCannotOverwriteNewerSnapshot() async {
        TradingRulesComplianceRecomputeCoordinator.resetForSessionBoundary()
        let scope = PsychologyAnalyticsScopeResolver.resolve(
            filter: DashboardClientScopeFilter(
                accountFilter: .all,
                dateRange: .thirtyDays,
                customInterval: nil,
                accountMode: .all,
                showPublicOnly: false
            ),
            profileID: profileA
        )
        let payload = TradingRulesComplianceCompute.computeScopedSync(
            trades: [sampleTrade(owner: profileA)],
            context: configuredPreferences(profileID: profileA),
            dashboardInsights: nil,
            preferDashboardInsightsCache: false
        )
        let hold = RulesCacheHold()
        let store = TradingRulesComplianceSessionStore.shared
        var olderLanded = false
        var newerLanded = false

        TradingRulesComplianceRecomputeCoordinator.request(
            profileID: profileA,
            scopeFingerprint: scope.fingerprint,
            fingerprint: "older"
        ) {
            await hold.wait()
            return payload
        } onComplete: { _ in
            olderLanded = true
        }

        await hold.entered()
        TradingRulesComplianceRecomputeCoordinator.request(
            profileID: profileA,
            scopeFingerprint: scope.fingerprint,
            fingerprint: "newer"
        ) {
            payload
        } onComplete: { _ in
            newerLanded = true
            let output = TradingRulesComplianceSnapshotBuilder.outputFromComputedPayload(
                payload: payload,
                preferences: self.configuredPreferences(profileID: self.profileA),
                scopedTradeCount: 1,
                ownerTradeCount: 1,
                historyComplete: true
            )
            store.commit(
                output: output,
                profileID: self.profileA,
                scope: scope,
                ready: true,
                inputFingerprint: "newer",
                generation: TradingRulesComplianceRecomputeCoordinator.currentGeneration,
                preferencesUnavailable: false
            )
        }

        await waitUntil { newerLanded }
        hold.release()
        await Task.yield()

        XCTAssertTrue(newerLanded)
        XCTAssertFalse(olderLanded)
        XCTAssertEqual(store.inputFingerprint, "newer")
        XCTAssertTrue(store.hasConfiguredRules)

        let staleToken = TradingRulesComplianceRecomputeCoordinator.currentGeneration
        let latest = TradingRulesComplianceRecomputeCoordinator.beginPublish()
        let kept = TradingRulesComplianceSnapshotBuilder.outputFromComputedPayload(
            payload: payload,
            preferences: configuredPreferences(profileID: profileA),
            scopedTradeCount: 1,
            ownerTradeCount: 1,
            historyComplete: true
        )
        XCTAssertTrue(
            store.commit(
                output: kept,
                profileID: profileA,
                scope: scope,
                ready: true,
                inputFingerprint: "kept",
                generation: latest,
                preferencesUnavailable: false
            )
        )
        let erased = TradingRulesComplianceSnapshotBuilder.Output(
            result: nil,
            hasConfiguredRules: false,
            scopedTradeCount: 1,
            ownerTradeCount: 1,
            preferencesContext: nil,
            preferencesError: "Couldn't load your trading rules.",
            tradesError: nil,
            insufficientScope: false,
            historyComplete: true,
            eligibility: nil
        )
        XCTAssertFalse(
            store.commit(
                output: erased,
                profileID: profileA,
                scope: scope,
                ready: true,
                inputFingerprint: "stale",
                generation: staleToken,
                preferencesUnavailable: true
            )
        )
        XCTAssertEqual(store.inputFingerprint, "kept")
        XCTAssertTrue(store.retainsConfiguredRules(for: profileA))

        var repeated = false
        TradingRulesComplianceRecomputeCoordinator.request(
            profileID: profileA,
            scopeFingerprint: scope.fingerprint,
            fingerprint: "kept"
        ) {
            payload
        } onComplete: { _ in
            repeated = true
        }
        await Task.yield()
        XCTAssertFalse(repeated)
    }

    func testSessionResetDoesNotLeakPreviousProfile() async {
        let viewModel = makeViewModel(preferences: CountingTradingPreferencesRepository())
        viewModel.seedLocalDashboardForTradingRules(
            profileID: profileA,
            preferences: configuredPreferences(profileID: profileA),
            trades: [sampleTrade(owner: profileA)]
        )
        viewModel.recomputeTradingRulesCompliance()
        await waitUntil { TradingRulesComplianceSessionStore.shared.profileID == self.profileA && TradingRulesComplianceSessionStore.shared.result != nil }

        DashboardSessionBoundary.resetInMemoryPresentation()
        let store = TradingRulesComplianceSessionStore.shared
        XCTAssertNil(store.profileID)
        XCTAssertNil(store.result)
        XCTAssertFalse(store.hasConfiguredRules)
        XCTAssertFalse(store.retainsConfiguredRules(for: profileA))
        XCTAssertNil(store.inputFingerprint)

        SessionViewerGate.shared.bind(profileB.rawValue)
        viewModel.seedLocalDashboardForTradingRules(
            profileID: profileB,
            preferences: configuredPreferences(profileID: profileB, maxTrades: 4),
            trades: [sampleTrade(owner: profileB)]
        )
        viewModel.recomputeTradingRulesCompliance()
        await waitUntil {
            TradingRulesComplianceSessionStore.shared.profileID == self.profileB
                && TradingRulesComplianceSessionStore.shared.result != nil
        }
        XCTAssertEqual(store.profileID, profileB)
        XCTAssertFalse(store.retainsConfiguredRules(for: profileA))
        XCTAssertTrue(store.retainsConfiguredRules(for: profileB))
    }

    private func makeViewModel(preferences: any TradingPreferencesRepository) -> DashboardViewModel {
        BackendV2FeatureFlags.resetFlagsForTests()
        DashboardHomeSurfaceGate.resetForTesting()
        SessionViewerGate.shared.resetForTesting()
        SessionViewerGate.shared.bind(profileA.rawValue)
        TradingRulesComplianceRecomputeCoordinator.resetForSessionBoundary()
        return DashboardViewModel(
            home: RulesCacheHomeRepository(),
            trades: RulesCacheTradeRepository(),
            achievements: RulesCacheAchievementRepository(),
            dailyCheckIns: EmptyTraderDailyCheckInRepository(),
            session: PlaceholderSessionProvider(),
            detailCache: DetailPresentationCache(),
            navigationCoordinator: NavigationCoordinator(store: NavigationStore()),
            tradingPreferences: preferences
        )
    }

    private func configuredPreferences(profileID: ProfileID, maxTrades: Int = 3) -> PreferenceRuleContext {
        var global = TradingPreferenceGlobal.empty(userID: profileID)
        global.maxTradesPerDay = maxTrades
        return PreferenceRuleContext(revisions: [], global: global, overrides: [])
    }

    private func sampleTrade(owner: ProfileID) -> Trade {
        let now = Date()
        return Trade(
            id: TradeID("rules-cache-\(owner.rawValue)"),
            ownerProfileID: owner,
            accountID: accountA,
            symbol: Symbol(ticker: "ES"),
            side: .long,
            mode: .live,
            quantity: 1,
            entryPrice: 100,
            exitPrice: 101,
            entryAt: now,
            exitAt: now.addingTimeInterval(60),
            realizedPnL: Money(amount: 25),
            sessionLabel: "NY AM",
            visibility: .private,
            createdAt: now,
            updatedAt: now
        )
    }

    private func waitUntil(timeout: TimeInterval = 2, _ condition: @escaping () -> Bool) async {
        let start = Date()
        while !condition() {
            if Date().timeIntervalSince(start) > timeout {
                XCTFail("Timed out waiting for trading rules snapshot")
                return
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}

private final class RulesCacheHold: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?
    private var enteredContinuation: CheckedContinuation<Void, Never>?
    private var isEntered = false

    func wait() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            lock.lock()
            continuation = cont
            isEntered = true
            let entered = enteredContinuation
            enteredContinuation = nil
            lock.unlock()
            entered?.resume()
        }
    }

    func entered() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            lock.lock()
            if isEntered {
                lock.unlock()
                cont.resume()
                return
            }
            enteredContinuation = cont
            lock.unlock()
        }
    }

    func release() {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume()
    }
}

private final class CountingTradingPreferencesRepository: TradingPreferencesRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var fetches = 0

    var fetchCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return fetches
    }

    func globalPreferences(for userID: ProfileID) async throws -> TradingPreferenceGlobal {
        noteFetch()
        throw AppError.notImplemented(feature: "rules.cache.preferences")
    }

    func saveGlobal(_ preferences: TradingPreferenceGlobal) async throws -> TradingPreferenceGlobal {
        noteFetch()
        throw AppError.notImplemented(feature: "rules.cache.preferences")
    }

    func accountOverrides(for userID: ProfileID) async throws -> [TradingPreferenceAccountOverride] {
        noteFetch()
        throw AppError.notImplemented(feature: "rules.cache.preferences")
    }

    func saveOverride(
        _ override: TradingPreferenceAccountOverride
    ) async throws -> TradingPreferenceAccountOverride {
        noteFetch()
        throw AppError.notImplemented(feature: "rules.cache.preferences")
    }

    func revisions(for userID: ProfileID) async throws -> [TradingPreferenceRevision] {
        noteFetch()
        throw AppError.notImplemented(feature: "rules.cache.preferences")
    }

    func discovery(for userID: ProfileID) async throws -> PreferenceDiscoveryResponse? {
        noteFetch()
        throw AppError.notImplemented(feature: "rules.cache.preferences")
    }

    func recordDiscovery(
        _ response: PreferenceDiscoveryResponse,
        for userID: ProfileID
    ) async throws -> PreferenceDiscoveryResponse {
        noteFetch()
        throw AppError.notImplemented(feature: "rules.cache.preferences")
    }

    func hasJournalTrade(for userID: ProfileID) async throws -> Bool {
        noteFetch()
        throw AppError.notImplemented(feature: "rules.cache.preferences")
    }

    private func noteFetch() {
        lock.lock()
        fetches += 1
        lock.unlock()
    }
}

private struct RulesCacheHomeRepository: HomeRepository {
    func dashboard(for profileID: ProfileID) async throws -> HomeDashboard {
        throw AppError.notImplemented(feature: "rules.cache.home")
    }

    func performance(for profileID: ProfileID, interval: DateIntervalValue) async throws -> PerformanceSummary {
        throw AppError.notImplemented(feature: "rules.cache.home")
    }
}

private struct RulesCacheAchievementRepository: AchievementRepository {
    func achievement(id: AchievementID) async throws -> Achievement {
        throw AppError.notImplemented(feature: "rules.cache.achievements")
    }

    func achievements(
        for profileID: ProfileID,
        page: PageRequest,
        publicOnly: Bool
    ) async throws -> CursorPage<Achievement> {
        CursorPage(items: [], nextCursor: nil)
    }

    func save(_ achievement: Achievement, metadata: JSONValue?) async throws -> Achievement { achievement }

    func withdrawalAchievementLinks(for profileID: ProfileID) async throws -> [WithdrawalAchievementLinkRow] {
        []
    }
}

private struct RulesCacheTradeRepository: TradeRepository {
    func trade(id: TradeID) async throws -> Trade {
        throw AppError.notImplemented(feature: "rules.cache.trades")
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
        throw AppError.notImplemented(feature: "rules.cache.trades")
    }

    func update(_ trade: Trade) async throws -> Trade { trade }

    func delete(id: TradeID) async throws {}

    func images(for tradeID: TradeID) async throws -> [TradeImage] { [] }

    func notes(for tradeID: TradeID) async throws -> [TradeNote] { [] }

    func statistics(for profileID: ProfileID, interval: DateIntervalValue) async throws -> TradeStatistics {
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
}
