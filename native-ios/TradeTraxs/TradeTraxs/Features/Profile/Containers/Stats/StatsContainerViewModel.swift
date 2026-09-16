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
    private let rpc: (any RPCClient)?
    private let achievements: any AchievementRepository
    private let detailCache: DetailPresentationCache

    /// Server-side mode payloads — primary stats source when profile V2 is enabled.
    private var modeResults: [ProfileStatisticsMetrics.Mode: ProfileStatisticsMetrics.Result] = [:]
    /// Legacy fallback only when statistics RPC is unavailable.
    private var tradeInputs: [ProfileStatisticsMetrics.TradeInput] = []
    private var accountModes: [TradingAccountID: TradingAccountMode] = [:]
    private var analyticsTask: Task<Void, Never>?
    private var hasLoadedAnalytics = false
    private var analyticsFetchedAt: Date?
    private var canViewContent = true
    private var isScreenOwned = false
    private var awaitingScreenBootstrap = false
    private let initialLoadFailureGrace = ProfileSectionFailureGrace()

    init(
        profileID: ProfileID,
        trades: any TradeRepository,
        rpc: (any RPCClient)? = nil,
        achievements: any AchievementRepository,
        detailCache: DetailPresentationCache
    ) {
        self.profileID = profileID
        self.trades = trades
        self.rpc = rpc
        self.achievements = achievements
        self.detailCache = detailCache
    }

    var filterEmptyMessage: String? {
        guard metrics != nil else { return nil }
        guard hasLoadedAnalytics || !modeResults.isEmpty || !tradeInputs.isEmpty else { return nil }
        guard metrics?.filteredTradeCount == 0 else { return nil }
        return "No trades for this filter selection"
    }

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

        awaitingScreenBootstrap = isScreenOwned
            && metrics == nil
            && !hasLoadedAnalytics
            && snapshot.phase == .loading

        if let updated = snapshot.lastUpdated,
           let fetchedAt = analyticsFetchedAt,
           updated > fetchedAt
        {
            hasLoadedAnalytics = false
            modeResults = [:]
        }

        if (snapshot.phase == .loading || snapshot.didBootstrap), metrics == nil, !hasLoadedAnalytics {
            state = .loading
        }

        if snapshot.phase == .loaded || hasLoadedAnalytics || metrics != nil {
            awaitingScreenBootstrap = false
            initialLoadFailureGrace.cancel()
        }

        scheduleAnalyticsLoadIfNeeded()
    }

    func loadIfNeeded() {
        scheduleAnalyticsLoadIfNeeded()
    }

    func refresh() async {
        if isScreenOwned {
            hasLoadedAnalytics = false
            modeResults = [:]
            analyticsTask?.cancel()
            analyticsTask = nil
            scheduleAnalyticsLoadIfNeeded(force: true)
            return
        }
        analyticsTask?.cancel()
        isRefreshing = true
        hasLoadedAnalytics = false
        modeResults = [:]
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
        _ = forceNetwork
        defer { analyticsTask = nil }

        if ProfileSectionSupport.isLocalDevelopmentProfile(profileID) {
            applyFixtures()
            hasLoadedAnalytics = true
            analyticsFetchedAt = Date()
            return
        }

        state = metrics == nil ? .loading : state
        initialLoadFailureGrace.cancel()

        if BackendV2FeatureFlags.isEnabled(.profile), let rpc {
            do {
                let applied = try await ProfileStatisticsBootstrapLoader.load(
                    profileID: profileID,
                    rpc: rpc
                )
                modeResults = applied.modeResults
                hasLoadedAnalytics = true
                analyticsFetchedAt = Date()
                initialLoadFailureGrace.cancel()
                recompute()
                return
            } catch ProfileStatisticsBootstrapLoader.LoaderError.flagOff,
                    ProfileStatisticsBootstrapLoader.LoaderError.rpcUnavailable {
                // Fall through to legacy trade pagination.
            } catch {
                guard !Task.isCancelled else { return }
                #if DEBUG
                ProfileStatisticsBootstrapFailureDiagnostic.log(
                    rpcName: BackendV2Versioning.RPCName.profileStatisticsBootstrap.rawValue,
                    error: error
                )
                #endif
                modeResults = [:]
                // Fall through to legacy trade pagination when V2 fails.
            }
        }

        do {
            tradeInputs = try await ProfileStatisticsTradeLoader.loadPublicTradeInputs(
                profileID: profileID,
                trades: trades,
                rpc: rpc,
                accountModes: accountModes
            )
            hasLoadedAnalytics = true
            analyticsFetchedAt = Date()
            initialLoadFailureGrace.cancel()
            recompute()
        } catch {
            guard !Task.isCancelled else { return }
            if metrics == nil {
                if awaitingScreenBootstrap {
                    state = .loading
                } else {
                    let message = ProfileSectionSupport.message(for: error)
                    initialLoadFailureGrace.scheduleIfNeeded(message: message) { [weak self] in
                        guard let self else { return false }
                        return metrics == nil && !hasLoadedAnalytics && !awaitingScreenBootstrap
                    } present: { [weak self] message in
                        self?.state = .failed(message: message)
                    }
                }
            }
        }
    }

    private func applyFixtures() {
        let samples = ProfileTradeFixtures.samples(owner: profileID)
            .filter { $0.visibility == .public }
        accountModes = ProfileTradeFixtures.accountModes()
        tradeInputs = samples.map {
            ProfileStatisticsMetrics.tradeInput(from: $0, accountModes: accountModes)
        }
        modeResults = [:]
        recompute()
    }

    private func recompute() {
        if let server = modeResults[selectedMode] {
            metrics = server
        } else {
            metrics = ProfileStatisticsMetrics.compute(
                from: tradeInputs,
                selectedMode: selectedMode
            )
        }

        let allCount: Int = {
            if let all = modeResults[.all] { return all.filteredTradeCount }
            return ProfileStatisticsMetrics.compute(from: tradeInputs, selectedMode: .all).filteredTradeCount
        }()

        if allCount == 0 {
            if !hasLoadedAnalytics, case .failed = state {
                // Keep failure state until analytics retry succeeds.
            } else if !hasLoadedAnalytics {
                state = .loading
            } else {
                state = .empty
            }
        } else {
            state = .loaded(itemCount: max(metrics?.filteredTradeCount ?? 0, 1))
        }
    }
}
