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
    private let session: any SessionProviding
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
    private var didScheduleLockedProfileShadow = false
    private var visibilityIdentity = ProfileAnalyticsVisibilityIdentity(token: "")

    init(
        profileID: ProfileID,
        trades: any TradeRepository,
        rpc: (any RPCClient)? = nil,
        session: any SessionProviding,
        achievements: any AchievementRepository,
        detailCache: DetailPresentationCache
    ) {
        self.profileID = profileID
        self.trades = trades
        self.rpc = rpc
        self.session = session
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
        visibilityIdentity = ProfileAnalyticsVisibilityIdentity.from(
            snapshot: snapshot,
            subjectProfileID: profileID
        )
        if snapshot.isContentLocked {
            canViewContent = false
            state = .empty
            scheduleLockedProfileShadowIfNeeded()
            Task {
                await ProfileAnalyticsPresentationCoordinator.handleLockedProfile(
                    subjectProfileID: profileID,
                    session: session
                )
            }
            return
        }
        canViewContent = true
        accountModes = snapshot.accountModes

        awaitingScreenBootstrap = isScreenOwned
            && metrics == nil
            && !hasLoadedAnalytics
            && snapshot.phase == .loading

        if !hasLoadedAnalytics,
           let updated = snapshot.lastUpdated,
           let fetchedAt = analyticsFetchedAt,
           updated > fetchedAt
        {
            modeResults = [:]
        }

        if hasLoadedAnalytics {
            if snapshot.phase == .loaded || metrics != nil {
                awaitingScreenBootstrap = false
                initialLoadFailureGrace.cancel()
            }
            recompute()
            return
        }

        var nextState: ProfileSectionLoadState?
        if (snapshot.phase == .loading || snapshot.didBootstrap), metrics == nil {
            nextState = .loading
        }

        let bootstrapSettled = snapshot.phase == .loaded || metrics != nil
        if bootstrapSettled {
            awaitingScreenBootstrap = false
            initialLoadFailureGrace.cancel()
        }

        let kickDeferredLoad = canViewContent && !awaitingScreenBootstrap

        ProfileSectionInitialLoad.applyBootstrapMissingSectionPlan(
            ProfileSectionInitialLoad.BootstrapMissingSectionPlan(
                nextState: nextState,
                kickDeferredLoad: kickDeferredLoad
            ),
            setState: { [self] next in state = next },
            kickDeferredLoad: { [self] in scheduleAnalyticsLoadIfNeeded() }
        )
    }

    func loadIfNeeded() {
        scheduleAnalyticsLoadIfNeeded()
    }

    func refresh() async {
        if isScreenOwned {
            hasLoadedAnalytics = false
            modeResults = [:]
            didScheduleLockedProfileShadow = false
            analyticsTask?.cancel()
            analyticsTask = nil
            Task {
                await ProfileAnalyticsV2ShadowSession.shared.clearShadowKeys(
                    forSubjectProfile: profileID.rawValue
                )
            }
            scheduleAnalyticsLoadIfNeeded(force: true)
            return
        }
        analyticsTask?.cancel()
        isRefreshing = true
        hasLoadedAnalytics = false
        modeResults = [:]
        didScheduleLockedProfileShadow = false
        Task {
            await ProfileAnalyticsV2ShadowSession.shared.clearShadowKeys(
                forSubjectProfile: profileID.rawValue
            )
        }
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

        let loadGeneration = await ProfileAnalyticsGRDBSession.shared.currentGeneration()
        await ProfileAnalyticsGRDBSession.shared.setActiveSubjectProfile(profileID.rawValue)

        if ProfileAnalyticsPresentationCoordinator.usesProfileAnalyticsV2, let rpc {
            do {
                if ProfileAnalyticsPresentationCoordinator.usesProfileAnalyticsGRDB,
                   !forceNetwork,
                   canViewContent {
                    let viewerScope = await ProfileAnalyticsV2ShadowCoordinator.viewerScopeID(session: session)
                    let store = AnalyticsLocalStore()
                    let cacheKey = store.profileAnalyticsCacheKey(
                        viewerScopeID: viewerScope,
                        subjectProfileID: profileID,
                        visibility: visibilityIdentity
                    )
                    if let cached = try await store.readProfileAnalyticsSnapshot(key: cacheKey),
                       !cached.modeResults.isEmpty {
                        modeResults = cached.modeResults
                        recompute()
                    }
                }

                if let presentation = try await ProfileAnalyticsPresentationCoordinator.load(
                    request: ProfileAnalyticsPresentationCoordinator.Request(
                        subjectProfileID: profileID,
                        visibility: visibilityIdentity,
                        canViewStatistics: canViewContent,
                        forceNetwork: forceNetwork,
                        loadGeneration: loadGeneration
                    ),
                    session: session,
                    rpc: rpc
                ) {
                    guard !Task.isCancelled else { return }
                    guard await ProfileAnalyticsGRDBSession.shared.isActiveSubjectProfile(
                        profileID.rawValue
                    ) else { return }
                    modeResults = presentation.modeResults
                    hasLoadedAnalytics = true
                    analyticsFetchedAt = Date()
                    initialLoadFailureGrace.cancel()
                    recompute()
                    return
                }
                ProfileAnalyticsGRDBProbe.logFallback(
                    viewer: profileID.rawValue,
                    subject: profileID.rawValue,
                    reason: "v2_unavailable_or_locked"
                )
            } catch {
                guard !Task.isCancelled else { return }
                ProfileAnalyticsGRDBProbe.logFallback(
                    viewer: profileID.rawValue,
                    subject: profileID.rawValue,
                    reason: "v2_error"
                )
            }
        }

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
                scheduleProfileAnalyticsV2Shadow(v1ModeResults: applied.modeResults)
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
                ProfileAnalyticsGRDBProbe.logFallback(
                    viewer: profileID.rawValue,
                    subject: profileID.rawValue,
                    reason: "v1_rpc_error"
                )
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
            scheduleProfileAnalyticsV2Shadow(v1ModeResults: v1ModeResultsForShadow())
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

    private func v1ModeResultsForShadow() -> [ProfileStatisticsMetrics.Mode: ProfileStatisticsMetrics.Result] {
        if !modeResults.isEmpty {
            return modeResults
        }
        var computed: [ProfileStatisticsMetrics.Mode: ProfileStatisticsMetrics.Result] = [:]
        for mode in ProfileStatisticsMetrics.Mode.allCases {
            computed[mode] = ProfileStatisticsMetrics.compute(from: tradeInputs, selectedMode: mode)
        }
        return computed
    }

    private func scheduleLockedProfileShadowIfNeeded() {
        guard !didScheduleLockedProfileShadow else { return }
        didScheduleLockedProfileShadow = true
        scheduleProfileAnalyticsV2Shadow(v1ModeResults: [:])
    }

    private func scheduleProfileAnalyticsV2Shadow(
        v1ModeResults: [ProfileStatisticsMetrics.Mode: ProfileStatisticsMetrics.Result],
        force: Bool = false
    ) {
        guard BackendV2FeatureFlags.isEnabled(.profileAnalyticsV2Shadow) else { return }
        guard !ProfileAnalyticsPresentationCoordinator.usesProfileAnalyticsV2 else { return }
        guard let rpc else { return }
        let subjectID = profileID
        Task {
            let viewerScope = await ProfileAnalyticsV2ShadowCoordinator.viewerScopeID(session: session)
            let generation = await ProfileAnalyticsV2ShadowSession.shared.currentGeneration()
            ProfileAnalyticsV2ShadowCoordinator.schedule(
                rpc: rpc,
                session: session,
                request: ProfileAnalyticsV2ShadowCoordinator.Request(
                    subjectProfileID: subjectID,
                    viewerScopeID: viewerScope,
                    shadowGeneration: generation,
                    v1CanViewStatistics: canViewContent,
                    v1ModeResults: v1ModeResults,
                    force: force
                )
            )
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
