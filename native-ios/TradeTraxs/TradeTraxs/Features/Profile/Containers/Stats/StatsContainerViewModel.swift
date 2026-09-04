import Foundation
import Observation

@Observable
@MainActor
final class StatsContainerViewModel {
    private(set) var state: ProfileSectionLoadState = .idle
    private(set) var metrics: ProfileStatisticsMetrics.Result?
    private(set) var isRefreshing = false

    var selectedMode: ProfileStatisticsMetrics.Mode = .all {
        didSet {
            guard oldValue != selectedMode else { return }
            recompute()
        }
    }

    private let profileID: ProfileID
    private let trades: any TradeRepository
    private let achievements: any AchievementRepository
    private let detailCache: DetailPresentationCache

    /// Cached public trades + authoritative account-mode map.
    private var tradeInputs: [ProfileStatisticsMetrics.TradeInput] = []
    private var accountModes: [TradingAccountID: TradingAccountMode] = [:]
    private var analyticsTask: Task<Void, Never>?
    private var hasLoadedAnalytics = false
    private var analyticsFetchedAt: Date?
    private var canViewContent = true
    private var isScreenOwned = false

    init(
        profileID: ProfileID,
        trades: any TradeRepository,
        achievements: any AchievementRepository,
        detailCache: DetailPresentationCache
    ) {
        self.profileID = profileID
        self.trades = trades
        self.achievements = achievements
        self.detailCache = detailCache
    }

    var filterEmptyMessage: String? {
        guard metrics != nil else { return nil }
        guard hasLoadedAnalytics || !tradeInputs.isEmpty else { return nil }
        guard metrics?.filteredTradeCount == 0 else { return nil }
        return "No trades for this filter selection"
    }

    /// Applies shared trades when Stage 2 has filled them; always schedules full analytics fetch.
    func applyBootstrap(_ snapshot: ProfileState) {
        if snapshot.didBootstrap || snapshot.phase == .loaded {
            isScreenOwned = true
        }
        if snapshot.isContentLocked {
            canViewContent = false
            state = .empty
            return
        }
        canViewContent = true
        accountModes = snapshot.accountModes

        if let updated = snapshot.lastUpdated,
           let fetchedAt = analyticsFetchedAt,
           updated > fetchedAt
        {
            hasLoadedAnalytics = false
        }

        let cachedTrades = detailCache.publicTrades(for: profileID)
        let sourceTrades = preferredTradeSource(cached: cachedTrades, bootstrap: snapshot.trades)
        let hasTrades = snapshot.didLoadTrades || !sourceTrades.isEmpty

        if hasTrades {
            applyTradeInputs(from: sourceTrades)
        } else if (snapshot.phase == .loading || snapshot.didBootstrap), metrics == nil {
            state = .loading
        }

        scheduleAnalyticsLoadIfNeeded()
    }

    func loadIfNeeded() {
        scheduleAnalyticsLoadIfNeeded()
    }

    func refresh() async {
        if isScreenOwned {
            hasLoadedAnalytics = false
            analyticsTask?.cancel()
            analyticsTask = nil
            scheduleAnalyticsLoadIfNeeded(force: true)
            return
        }
        analyticsTask?.cancel()
        isRefreshing = true
        hasLoadedAnalytics = false
        await performLoad(forceNetwork: true)
        isRefreshing = false
    }

    func setMode(_ mode: ProfileStatisticsMetrics.Mode) {
        guard selectedMode != mode else { return }
        ExperienceHaptics.play(.selection)
        selectedMode = mode
    }

    func loadMoreIfNeeded() async {
        // Stats are a single aggregate — no pagination.
    }

    // MARK: - Load

    private func scheduleAnalyticsLoadIfNeeded(force: Bool = false) {
        guard canViewContent else {
            state = .empty
            return
        }
        if !force, hasLoadedAnalytics { return }
        guard analyticsTask == nil else { return }
        analyticsTask = Task { await performLoad(forceNetwork: force) }
    }

    private func performLoad(forceNetwork: Bool = false) async {
        defer { analyticsTask = nil }

        if ProfileSectionSupport.isLocalDevelopmentProfile(profileID) {
            applyFixtures()
            hasLoadedAnalytics = true
            analyticsFetchedAt = Date()
            return
        }

        state = metrics == nil ? .loading : state
        do {
            // Stats needs up to 500 rows — do not reuse the paginated Trades list cache alone.
            let page = try await trades.trades(
                ownedBy: profileID,
                accountID: nil,
                page: PageRequest(limit: 500),
                publicOnly: true
            )
            detailCache.seed(publicTrades: page.items, for: profileID)

            applyTradeInputs(from: page.items)
            hasLoadedAnalytics = true
            analyticsFetchedAt = Date()
            recompute()
        } catch {
            guard !Task.isCancelled else { return }
            if metrics == nil {
                state = .failed(message: ProfileSectionSupport.message(for: error))
            }
        }
    }

    private func applyFixtures() {
        let samples = ProfileTradeFixtures.samples(owner: profileID)
            .filter { $0.visibility == .public }
        accountModes = ProfileTradeFixtures.accountModes()
        applyTradeInputs(from: samples)
    }

    private func applyTradeInputs(from trades: [Trade]) {
        tradeInputs = trades.map {
            ProfileStatisticsMetrics.tradeInput(from: $0, accountModes: accountModes)
        }
        recompute()
    }

    private func preferredTradeSource(cached: [Trade]?, bootstrap: [Trade]) -> [Trade] {
        switch (cached?.count ?? 0, bootstrap.count) {
        case let (cachedCount, bootstrapCount) where cachedCount >= bootstrapCount:
            return cached ?? bootstrap
        default:
            return bootstrap
        }
    }

    private func recompute() {
        let result = ProfileStatisticsMetrics.compute(
            from: tradeInputs,
            selectedMode: selectedMode
        )
        metrics = result

        let allModes = ProfileStatisticsMetrics.compute(from: tradeInputs, selectedMode: .all)
        if allModes.filteredTradeCount == 0 {
            if tradeInputs.isEmpty, !hasLoadedAnalytics, case .failed = state {
                // Keep failure state until analytics retry succeeds.
            } else if tradeInputs.isEmpty, !hasLoadedAnalytics {
                state = .loading
            } else {
                state = .empty
            }
        } else {
            state = .loaded(itemCount: max(result.filteredTradeCount, 1))
        }
    }
}
