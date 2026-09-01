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

    /// Cached public trades + account-type map (web analyticsTradeRows).
    private var tradeInputs: [ProfileStatisticsMetrics.TradeInput] = []
    private var loadTask: Task<Void, Never>?
    private var hasLoaded = false
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
        guard hasLoaded, metrics?.filteredTradeCount == 0 else { return nil }
        return "No trades for this filter selection"
    }

    /// Applies shared trades when Stage 2 has filled them; otherwise loads on demand.
    /// Prefers ``DetailPresentationCache`` when section data was mutated after bootstrap.
    func applyBootstrap(_ snapshot: ProfileState) {
        if snapshot.didBootstrap || snapshot.phase == .loaded {
            isScreenOwned = true
        }
        if snapshot.isContentLocked {
            canViewContent = false
            hasLoaded = true
            state = .empty
            return
        }
        canViewContent = true
        let hasTrades = snapshot.didLoadTrades || !snapshot.trades.isEmpty
            || detailCache.publicTrades(for: profileID) != nil
        guard hasTrades else {
            if (snapshot.phase == .loading || snapshot.didBootstrap), metrics == nil {
                state = .loading
            }
            return
        }
        hasLoaded = true
        let sourceTrades = detailCache.publicTrades(for: profileID) ?? snapshot.trades
        let accountTypes = Dictionary(
            uniqueKeysWithValues: snapshot.accountModes.map {
                ($0.key, ProfileStatisticsMetrics.accountTypeString(for: $0.value))
            }
        )
        tradeInputs = sourceTrades.map { trade in
            ProfileStatisticsMetrics.TradeInput(
                pnl: trade.realizedPnL?.amount,
                createdAt: trade.createdAt,
                isLong: trade.side == .long,
                session: trade.sessionLabel,
                mode: trade.mode.rawValue,
                accountType: trade.accountID.flatMap { accountTypes[$0] }
            )
        }
        recompute()
    }

    func loadIfNeeded() {
        guard !hasLoaded, loadTask == nil else { return }
        guard canViewContent else {
            hasLoaded = true
            state = .empty
            return
        }
        loadTask = Task { await performLoad() }
    }

    func refresh() async {
        if isScreenOwned {
            // Screen pull-to-refresh re-bootstraps; local mode filter stays client-side.
            return
        }
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
            let page = try await trades.trades(
                ownedBy: profileID,
                accountID: nil,
                page: PageRequest(limit: 500),
                publicOnly: true
            )
            detailCache.seed(publicTrades: page.items, for: profileID)

            tradeInputs = page.items.map { trade in
                ProfileStatisticsMetrics.TradeInput(
                    pnl: trade.realizedPnL?.amount,
                    createdAt: trade.createdAt,
                    isLong: trade.side == .long,
                    session: trade.sessionLabel,
                    mode: trade.mode.rawValue,
                    accountType: trade.mode.rawValue
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
        recompute()
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
