import Foundation

struct PsychologyAnalyticsLoadDependencies {
    let detailCache: DetailPresentationCache
    let dailyCheckIns: any TraderDailyCheckInRepository
    let tradesRepository: any TradeRepository
    let rpc: (any RPCClient)?
}

enum PsychologyAnalyticsLoadOutcome: Equatable {
    case ready
    case empty
    case failed(String)
}

@MainActor
enum PsychologyAnalyticsSessionLoader {
    private static var inFlightProfileID: ProfileID?
    private static var inFlightTask: Task<PsychologyAnalyticsLoadOutcome, Never>?

    static func refresh(
        dependencies: PsychologyAnalyticsLoadDependencies,
        dashboardViewModel: DashboardViewModel?
    ) async -> PsychologyAnalyticsLoadOutcome {
        guard let profileID = SessionBootstrapStore.shared.last.map({ ProfileID($0.data.viewer.id) })
        else {
            PsychologyAnalyticsSessionStore.shared.clearSession()
            return .empty
        }

        PsychologyAnalyticsSessionStore.shared.clearIfProfileMismatch(profileID)

        if let dashboardViewModel,
           dashboardViewModel.isPsychologyAnalyticsDashboardSource(profileID: profileID)
        {
            await dashboardViewModel.ensurePsychologyAnalyticsReportForPresentation()
            return PsychologyAnalyticsSessionStore.shared.report == nil ? .empty : .ready
        }

        if let inFlightTask, inFlightProfileID == profileID {
            return await inFlightTask.value
        }

        let task = Task { () -> PsychologyAnalyticsLoadOutcome in
            await performColdRefresh(dependencies: dependencies, profileID: profileID)
        }
        inFlightProfileID = profileID
        inFlightTask = task
        defer {
            inFlightTask = nil
            inFlightProfileID = nil
        }
        return await task.value
    }

    /// Publishes immediately from session/disk caches when available (no network).
    static func revealCachedReportIfPossible(profileID: ProfileID) -> Bool {
        PsychologyAnalyticsSessionStore.shared.clearIfProfileMismatch(profileID)
        let accounts = SessionAccountsStore.shared.cached(for: profileID) ?? []
        let linked = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.mode) })
        let scope = PsychologyAnalyticsScopeResolver.resolve(
            profileID: profileID,
            linkedAccountModes: linked
        )
        if PsychologyAnalyticsSessionStore.shared.matchesCachedPresentation(
            profileID: profileID,
            scopeFingerprint: scope.fingerprint
        ) {
            return PsychologyAnalyticsSessionStore.shared.report != nil
        }

        guard let ownerTrades = SessionOwnerTradesStore.shared.cached(for: profileID) else {
            return false
        }
        let checkIns = PsychologyAnalyticsCheckInGate.mergedCheckIns(profileID: profileID)
        guard !ownerTrades.isEmpty || !checkIns.isEmpty else { return false }

        let scoped = PsychologyAnalyticsTradeScope.scopedTrades(
            ownerTrades: ownerTrades,
            accounts: accounts,
            scope: scope.filter
        )
        PsychologyAnalyticsReportComposer.publish(
            scopedTrades: scoped,
            checkIns: checkIns,
            profileID: profileID,
            scope: scope
        )
        return true
    }

    private static func performColdRefresh(
        dependencies: PsychologyAnalyticsLoadDependencies,
        profileID: ProfileID
    ) async -> PsychologyAnalyticsLoadOutcome {
        await SessionNetworkGate.shared.awaitReady()

        let accounts = await loadAccounts(profileID: profileID, dependencies: dependencies)
        let scope = PsychologyAnalyticsScopeResolver.resolve(
            profileID: profileID,
            linkedAccountModes: Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.mode) })
        )

        _ = SessionOwnerTradesStore.shared.hydrateFromDiskIfNeeded(
            for: profileID,
            detailCache: dependencies.detailCache
        )

        if let cachedTrades = SessionOwnerTradesStore.shared.cached(for: profileID) {
            let checkIns = PsychologyAnalyticsCheckInGate.mergedCheckIns(profileID: profileID)
            let scoped = PsychologyAnalyticsTradeScope.scopedTrades(
                ownerTrades: cachedTrades,
                accounts: accounts,
                scope: scope.filter
            )
            PsychologyAnalyticsReportComposer.publish(
                scopedTrades: scoped,
                checkIns: checkIns,
                profileID: profileID,
                scope: scope
            )
        }

        await hydrateCheckInsIfNeeded(
            profileID: profileID,
            dependencies: dependencies
        )
        let tradesLoadFailed = await hydrateOwnerTradesIfNeeded(
            profileID: profileID,
            scope: scope.filter,
            dependencies: dependencies
        )

        guard let ownerTrades = SessionOwnerTradesStore.shared.cached(for: profileID) else {
            PsychologyAnalyticsSessionStore.shared.clearSession()
            if tradesLoadFailed {
                return .failed("Check your connection and try again.")
            }
            return .empty
        }

        let checkIns = PsychologyAnalyticsCheckInGate.mergedCheckIns(profileID: profileID)
        let scoped = PsychologyAnalyticsTradeScope.scopedTrades(
            ownerTrades: ownerTrades,
            accounts: accounts,
            scope: scope.filter
        )

        if scoped.isEmpty, checkIns.isEmpty {
            PsychologyAnalyticsSessionStore.shared.clearSession()
            return .empty
        }

        PsychologyAnalyticsReportComposer.publish(
            scopedTrades: scoped,
            checkIns: checkIns,
            profileID: profileID,
            scope: scope
        )
        return .ready
    }

    private static func loadAccounts(
        profileID: ProfileID,
        dependencies: PsychologyAnalyticsLoadDependencies
    ) async -> [TradingAccount] {
        if let cached = SessionAccountsStore.shared.cached(for: profileID), !cached.isEmpty {
            return cached
        }
        if let seeded = dependencies.detailCache.accounts(for: profileID), !seeded.isEmpty {
            return seeded
        }
        do {
            return try await SessionAccountsStore.shared.accounts(
                for: profileID,
                detailCache: dependencies.detailCache,
                repository: dependencies.tradesRepository,
                forceNetwork: false,
                viewerProfileID: profileID
            )
        } catch {
            return SessionAccountsStore.shared.cached(for: profileID) ?? []
        }
    }

    private static func hydrateCheckInsIfNeeded(
        profileID: ProfileID,
        dependencies: PsychologyAnalyticsLoadDependencies
    ) async {
        let range = PsychologyDashboardCheckInsLoader.dashboardWindow()
        guard SessionDailyCheckInsStore.shared.needsLoad(
            for: profileID,
            startDate: range.start,
            endDate: range.end
        ) else { return }

        do {
            let items = try await PsychologyDashboardCheckInsLoader.load(
                profileID: profileID,
                dailyCheckIns: dependencies.dailyCheckIns,
                rpc: dependencies.rpc
            )
            commitCheckIns(items, profileID: profileID, window: range)
        } catch {
            if let rows = try? await PsychologyDashboardCheckInsLoader.loadHistoryWindow(
                profileID: profileID,
                dailyCheckIns: dependencies.dailyCheckIns
            ), !rows.isEmpty {
                commitCheckIns(rows, profileID: profileID, window: range)
            }
        }
    }

    private static func commitCheckIns(
        _ items: [TraderDailyCheckIn],
        profileID: ProfileID,
        window range: (start: String, end: String)
    ) {
        var merged = items
        if let today = TraderDailyCheckInStore.shared.todayCheckIn,
           today.ownerProfileID == profileID
        {
            merged = TraderDailyCheckInMerge.preferNewer(primary: merged, secondary: [today])
        }
        let seededRange: (start: String, end: String)
        if merged.isEmpty {
            seededRange = range
        } else {
            let dates = merged.map(\.checkInDate)
            seededRange = (dates.min() ?? range.start, dates.max() ?? range.end)
        }
        SessionDailyCheckInsStore.shared.seed(merged, for: profileID, range: seededRange)
    }

    private static func hydrateOwnerTradesIfNeeded(
        profileID: ProfileID,
        scope: DashboardClientScopeFilter,
        dependencies: PsychologyAnalyticsLoadDependencies
    ) async -> Bool {
        let cached = SessionOwnerTradesStore.shared.cached(for: profileID) ?? []
        let covers = DashboardScopeFilterSupport.cachedOwnerTradesCoverAnalyticsScope(
            trades: cached,
            scope: scope,
            historyComplete: SessionOwnerTradesStore.shared.isCompleteSnapshot(for: profileID)
        )
        if covers, SessionOwnerTradesStore.shared.isFresh(for: profileID), !cached.isEmpty {
            return false
        }
        do {
            _ = try await SessionOwnerTradesStore.shared.trades(
                for: profileID,
                detailCache: dependencies.detailCache,
                repository: dependencies.tradesRepository,
                forceNetwork: false
            )
            return false
        } catch {
            return cached.isEmpty
        }
    }
}
