import Foundation
import Observation

@Observable
@MainActor
final class StatsContainerViewModel {
    private(set) var state: ProfileSectionLoadState = .idle
    private(set) var metrics: ProfileStatisticsMetrics.Result?
    /// Web overview `overviewPayoutTotal` — `sumPayoutAchievementTotals`.
    private(set) var payoutTotal: Decimal?
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

    /// Cached public trades + account-type map (web analyticsTradeRows).
    private var tradeInputs: [ProfileStatisticsMetrics.TradeInput] = []
    private var loadTask: Task<Void, Never>?
    private var hasLoaded = false

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
        guard hasLoaded, metrics?.filteredTradeCount == 0 else { return nil }
        return "No trades for this filter selection"
    }

    func loadIfNeeded() {
        guard !hasLoaded, loadTask == nil else { return }
        loadTask = Task { await performLoad() }
    }

    func refresh() async {
        loadTask?.cancel()
        isRefreshing = true
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

    private func performLoad(forceNetwork: Bool = false) async {
        if ProfileSectionSupport.isLocalDevelopmentProfile(profileID) {
            applyFixtures()
            hasLoaded = true
            loadTask = nil
            return
        }

        state = metrics == nil ? .loading : state
        do {
            // Stats needs up to 500 rows — do not reuse the paginated Trades list cache.
            async let tradesTask = trades.trades(
                ownedBy: profileID,
                accountID: nil,
                page: PageRequest(limit: 500),
                publicOnly: true
            )
            // Web overview payouts: visible (public) achievements → sumPayoutAchievementTotals.
            async let achievementsTask = achievements.achievements(
                for: profileID,
                page: PageRequest(limit: 500),
                publicOnly: true
            )

            let page = try await tradesTask
            detailCache.seed(publicTrades: page.items, for: profileID)

            if let achievementPage = try? await achievementsTask {
                detailCache.seed(achievements: achievementPage.items)
                applyPayoutTotal(ProfilePayoutTotals.sum(from: achievementPage.items))
            } else if let cached = detailCache.stats(for: profileID)?.payoutTotal {
                payoutTotal = cached
            }

            // Accounts are session-scoped — reuse Trades/Detail cache when present.
            let accounts: [TradingAccount]
            if !forceNetwork, let cachedAccounts = detailCache.accounts(for: profileID) {
                accounts = cachedAccounts
            } else if let fetched = try? await trades.accounts(for: profileID) {
                accounts = fetched
                detailCache.seed(accounts: fetched, for: profileID)
            } else {
                accounts = []
            }

            guard !Task.isCancelled else { return }

            let accountTypes = Dictionary(
                uniqueKeysWithValues: accounts.map {
                    ($0.id, ProfileStatisticsMetrics.accountTypeString(for: $0.mode))
                }
            )
            tradeInputs = page.items.map { trade in
                ProfileStatisticsMetrics.TradeInput(
                    pnl: trade.realizedPnL?.amount,
                    createdAt: trade.createdAt,
                    isLong: trade.side == .long,
                    session: trade.sessionLabel,
                    mode: trade.mode.rawValue,
                    accountType: trade.accountID.flatMap { accountTypes[$0] }
                )
            }

            hasLoaded = true
            recompute()
        } catch {
            guard !Task.isCancelled else { return }
            if metrics == nil {
                state = .failed(message: ProfileSectionSupport.message(for: error))
            }
        }
        loadTask = nil
    }

    private func applyFixtures() {
        let samples = ProfileTradeFixtures.samples(owner: profileID)
            .filter { $0.visibility == .public }
        let modes = ProfileTradeFixtures.accountModes()
        tradeInputs = samples.map { trade in
            ProfileStatisticsMetrics.TradeInput(
                pnl: trade.realizedPnL?.amount,
                createdAt: trade.createdAt,
                isLong: trade.side == .long,
                session: trade.sessionLabel,
                mode: trade.mode.rawValue,
                accountType: trade.accountID.flatMap {
                    modes[$0].map(ProfileStatisticsMetrics.accountTypeString(for:))
                }
            )
        }
        applyPayoutTotal(
            ProfilePayoutTotals.sum(from: ProfileAchievementFixtures.samples(owner: profileID))
        )
        recompute()
    }

    private func applyPayoutTotal(_ total: Decimal) {
        payoutTotal = total
        if var stats = detailCache.stats(for: profileID) {
            stats.payoutTotal = total
            detailCache.seed(stats: stats)
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
            state = .empty
        } else {
            state = .loaded(itemCount: max(result.filteredTradeCount, 1))
        }
    }
}
