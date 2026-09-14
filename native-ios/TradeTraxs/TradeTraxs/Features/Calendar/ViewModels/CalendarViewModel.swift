import Foundation
import Observation

/// Trading Calendar — bounded month load → aggregate → Realtime idle.
@Observable
@MainActor
final class CalendarViewModel {
    private(set) var phase: CalendarLoadPhase = .idle
    private(set) var month: TradingCalendarMonth?
    private(set) var accounts: [TradingAccount] = []
    private(set) var accountNames: [TradingAccountID: String] = [:]
    private(set) var isRefreshing = false
    private(set) var isMonthTransitioning = false

    var accountFilter: DashboardAccountFilter = .all
    private(set) var visibleMonth: CalendarMonthID = .current()

    private let trades: any TradeRepository
    private let session: any SessionProviding
    private let detailCache: DetailPresentationCache
    private let navigationCoordinator: NavigationCoordinator
    private let realtimeHub: RealtimeHub?
    private let rpc: (any RPCClient)?

    private var profileID: ProfileID?
    private var allTrades: [Trade] = []
    /// Session cache: month id → trades that fall in that month's fetch window.
    private var monthTradeCache: [String: [Trade]] = [:]
    private var loadTask: Task<Void, Never>?
    private var watchedChannel: RealtimeChannelID?
    private var hasLoadedAccounts = false
    #if DEBUG
    private var monthProbeStart: Date?
    #endif

    init(
        trades: any TradeRepository,
        session: any SessionProviding,
        detailCache: DetailPresentationCache,
        navigationCoordinator: NavigationCoordinator,
        realtimeHub: RealtimeHub? = nil,
        rpc: (any RPCClient)? = nil
    ) {
        self.trades = trades
        self.session = session
        self.detailCache = detailCache
        self.navigationCoordinator = navigationCoordinator
        self.realtimeHub = realtimeHub
        self.rpc = rpc
    }

    var accountFilterTitle: String {
        switch accountFilter {
        case .all: return "All Accounts"
        case .account(let id):
            if let account = accounts.first(where: { $0.id == id }) {
                return TradingAccountDisplay.ownerDropdownLine(for: account)
            }
            return accountNames[id] ?? "Account"
        }
    }

    /// Compact label for the top-right toolbar (same filter semantics).
    var accountFilterToolbarTitle: String {
        let full = accountFilterTitle
        guard full.count > 18 else { return full }
        return String(full.prefix(17)) + "…"
    }

    func accountMenuTitle(for account: TradingAccount) -> String {
        TradingAccountDisplay.ownerDropdownLine(for: account)
    }

    func menuAccounts(viewerID: ProfileID?, detailCache: DetailPresentationCache?) -> [TradingAccount] {
        let effectiveProfileID = profileID ?? viewerID
        if let effectiveProfileID {
            seedAccountsFromCache(profileID: effectiveProfileID)
        }
        let selectedID: TradingAccountID? = {
            if case .account(let id) = accountFilter { return id }
            return nil
        }()
        return OwnerAccountDropdownSupport.menuAccounts(
            profileID: effectiveProfileID,
            fallback: accounts,
            preservingSelection: selectedID,
            detailCache: detailCache
        )
    }

    var accountsForMenu: [TradingAccount] {
        menuAccounts(viewerID: profileID, detailCache: detailCache)
    }

    var ownerAccountsProfileID: ProfileID? { profileID }

    /// Synchronous warm-path before async load — accounts + owner-trade month seed.
    func primeFromKnownViewer(_ profileID: ProfileID?) {
        guard let profileID else { return }
        self.profileID = profileID
        if SessionAccountsStore.shared.cached(for: profileID) == nil,
           let disk = SessionDiskCache.loadAccounts(for: profileID),
           !disk.isEmpty,
           !TradingAccountOwnerDiagnostics.looksLikeSessionSummaryStub(disk)
        {
            SessionAccountsStore.shared.seed(
                disk,
                for: profileID,
                detailCache: detailCache,
                kind: .rest
            )
        }
        seedAccountsFromCache(profileID: profileID)
        if accounts.isEmpty {
            let resolved = OwnerAccountDropdownSupport.resolvedAccounts(
                profileID: profileID,
                fallback: [],
                detailCache: detailCache
            )
            if !resolved.isEmpty {
                accounts = resolved.sorted {
                    $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                accountNames = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.name) })
                hasLoadedAccounts = true
            }
        }
        _ = SessionOwnerTradesStore.shared.hydrateFromDiskIfNeeded(
            for: profileID,
            detailCache: detailCache
        )
        if trySeedVisibleMonthFromOwnerCache(profileID: profileID) {
            phase = .loaded
        }
    }

    func loadIfNeeded() {
        if phase == .loaded, month != nil {
            SessionNetworkProbe.record(.cacheHit, resource: "calendar.navigationReturn")
            if let profileID {
                Task { await startRealtime(profileID: profileID) }
            }
            return
        }
        guard loadTask == nil else { return }
        loadTask = Task {
            await performLoad(forceNetwork: false)
            loadTask = nil
        }
    }

    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        monthTradeCache.removeAll()
        CalendarMonthSessionStore.shared.invalidate()
        await performLoad(forceNetwork: true)
    }

    func handleJournalMutation() {
        switch TradeJournalMutationStore.shared.latest {
        case .created(let trade), .updated(let trade):
            applyRealtimeUpsert(trade)
        case .deleted(let id, _):
            applyRealtimeDelete(id: id)
        case .bulkImport, .none:
            Task { await refresh() }
        }
    }

    func handleAccountMutation() {
        guard let profileID else { return }
        if let cached = SessionAccountsStore.shared.cached(for: profileID)
            ?? detailCache.accounts(for: profileID)
        {
            accounts = cached.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            accountNames = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.name) })
            hasLoadedAccounts = true
            recompute()
        }
    }

    func goToPreviousMonth() {
        ExperienceHaptics.play(.selection)
        visibleMonth = visibleMonth.advancing(by: -1)
        Task { await loadVisibleMonth() }
    }

    func goToNextMonth() {
        ExperienceHaptics.play(.selection)
        visibleMonth = visibleMonth.advancing(by: 1)
        Task { await loadVisibleMonth() }
    }

    func goToCurrentMonth() {
        ExperienceHaptics.play(.selection)
        visibleMonth = .current()
        Task { await loadVisibleMonth() }
    }

    func setAccountFilter(_ filter: DashboardAccountFilter) {
        guard accountFilter != filter else { return }
        ExperienceHaptics.play(.selection)
        accountFilter = filter
        recompute()
    }

    func openManageAccounts() {
        ExperienceHaptics.play(.selection)
        navigationCoordinator.pushHome(.settings(.tradingAccounts))
    }

    func selectDay(_ dayKey: String) {
        ExperienceHaptics.play(.selection)
        navigationCoordinator.open(.home(.tradingDay(dayKey)))
    }

    func openTrade(_ trade: Trade) {
        ExperienceHaptics.play(.selection)
        detailCache.seed(trade)
        navigationCoordinator.open(.home(.tradeDetail(trade.id)))
    }

    func onDisappear() {
        Task { await stopRealtime() }
    }

    /// Trades for a day detail screen (uses session cache).
    func trades(for dayKey: String) -> [Trade] {
        TradingCalendarAggregator.trades(
            for: dayKey,
            from: allTrades,
            accountFilter: accountFilter
        )
    }

    func daySummary(for dayKey: String) -> TradingDaySummary? {
        month?.days[dayKey] ?? TradingCalendarAggregator.daySummaries(
            from: allTrades,
            accountFilter: accountFilter
        )[dayKey]
    }

    // MARK: - Load

    private func seedAccountsFromCache(profileID: ProfileID) {
        guard accounts.isEmpty else { return }
        guard let cached = SessionAccountsStore.shared.cached(for: profileID)
            ?? detailCache.accounts(for: profileID),
            !cached.isEmpty
        else { return }
        accounts = cached.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        accountNames = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.name) })
        hasLoadedAccounts = true
    }

    @discardableResult
    private func trySeedVisibleMonthFromOwnerCache(profileID: ProfileID) -> Bool {
        let id = visibleMonth
        let cacheKey = id.cacheKey
        if let cached = monthTradeCache[cacheKey] {
            mergeTrades(cached)
            recompute()
            return true
        }
        let metadata = SessionOwnerTradesStore.shared.snapshotMetadata(for: profileID)
        let complete = SessionOwnerTradesStore.shared.isCompleteSnapshot(for: profileID)
        guard OwnerTradeCacheCompleteness.canSeedCalendarMonth(metadata: metadata),
              let ownerTrades = SessionOwnerTradesStore.shared.cached(for: profileID),
              let monthTrades = OwnerTradeCalendarSeed.trades(
                  from: ownerTrades,
                  year: id.year,
                  month: id.month
              )
        else { return false }
        CacheDecisionProbe.log(
            surface: "calendar",
            cacheExists: true,
            cacheUsable: true,
            historyComplete: complete,
            action: "renderCache",
            reason: "ownerTradesCompleteSyncPrime"
        )
        monthTradeCache[cacheKey] = monthTrades
        CalendarMonthSessionStore.shared.store(monthTrades, year: id.year, month: id.month)
        mergeTrades(monthTrades)
        recompute()
        return true
    }

    private func performLoad(forceNetwork: Bool) async {
        let userID = await session.currentUserID
        let profileID = ProfileID(userID?.rawValue ?? "dev.screenshot")
        self.profileID = profileID

        if month == nil { phase = .loading }

        if ProfileSectionSupport.isLocalDevelopmentProfile(profileID) {
            applyFixtures(profileID: profileID)
            phase = .loaded
            await startRealtime(profileID: profileID)
            return
        }

        do {
            seedAccountsFromCache(profileID: profileID)
            _ = SessionOwnerTradesStore.shared.hydrateFromDiskIfNeeded(
                for: profileID,
                detailCache: detailCache
            )

            if !hasLoadedAccounts || forceNetwork {
                if !forceNetwork,
                   let cached = SessionAccountsStore.shared.cached(for: profileID)
                    ?? detailCache.accounts(for: profileID),
                   !cached.isEmpty
                {
                    seedAccountsFromCache(profileID: profileID)
                } else {
                    let fetched = try await SessionAccountsStore.shared.accounts(
                        for: profileID,
                        detailCache: detailCache,
                        repository: trades,
                        forceNetwork: forceNetwork,
                        requiresFullOwnerSnapshot: false
                    )
                    accounts = fetched.sorted {
                        $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                    }
                    accountNames = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.name) })
                    hasLoadedAccounts = true
                }
            }

            await loadVisibleMonth(forceNetwork: forceNetwork)
            phase = .loaded
            await startRealtime(profileID: profileID)
        } catch {
            if month == nil {
                phase = .failed(ProfileSectionSupport.message(for: error))
            }
        }
    }

    private func loadVisibleMonth(forceNetwork: Bool = false) async {
        let id = visibleMonth
        let cacheKey = id.cacheKey
        #if DEBUG
        monthProbeStart = Date()
        #endif

        if !forceNetwork, let cached = monthTradeCache[cacheKey] {
            SessionNetworkProbe.record(.cacheHit, resource: "calendar.month.vm", detail: cacheKey)
            mergeTrades(cached)
            recompute()
            return
        }

        if !forceNetwork,
           let shared = CalendarMonthSessionStore.shared.trades(year: id.year, month: id.month),
           CalendarMonthSessionStore.shared.isFresh(year: id.year, month: id.month)
        {
            monthTradeCache[cacheKey] = shared
            mergeTrades(shared)
            recompute()
            return
        }

        if !forceNetwork, let profileID {
            _ = SessionOwnerTradesStore.shared.hydrateFromDiskIfNeeded(
                for: profileID,
                detailCache: detailCache
            )
            let metadata = SessionOwnerTradesStore.shared.snapshotMetadata(for: profileID)
            let complete = SessionOwnerTradesStore.shared.isCompleteSnapshot(for: profileID)
            if OwnerTradeCacheCompleteness.canSeedCalendarMonth(metadata: metadata),
               let ownerTrades = SessionOwnerTradesStore.shared.cached(for: profileID),
               let monthTrades = OwnerTradeCalendarSeed.trades(
                   from: ownerTrades,
                   year: id.year,
                   month: id.month
               )
            {
                CacheDecisionProbe.log(
                    surface: "calendar",
                    cacheExists: true,
                    cacheUsable: true,
                    historyComplete: complete,
                    action: "renderCache",
                    reason: "ownerTradesComplete"
                )
                monthTradeCache[cacheKey] = monthTrades
                CalendarMonthSessionStore.shared.store(monthTrades, year: id.year, month: id.month)
                mergeTrades(monthTrades)
                recompute()
                SessionNetworkProbe.record(
                    .cacheHit,
                    resource: "calendar.month",
                    detail: "ownerTradesSeed complete count=\(monthTrades.count)"
                )
                #if DEBUG
                let probeMs = monthProbeStart.map {
                    Int(Date().timeIntervalSince($0) * 1000)
                } ?? 0
                CalendarCacheProbe.recordDiskHit(
                    month: cacheKey,
                    complete: complete,
                    trades: monthTrades.count,
                    firstRenderMs: probeMs
                )
                #endif
                return
            }
            CacheDecisionProbe.log(
                surface: "calendar",
                cacheExists: SessionOwnerTradesStore.shared.cached(for: profileID) != nil,
                cacheUsable: false,
                historyComplete: complete,
                action: "networkRequired",
                reason: complete ? "monthCoverageUncertain" : "incompleteOwnerSnapshot"
            )
            #if DEBUG
            CalendarCacheProbe.recordNetworkRequired(
                month: cacheKey,
                reason: complete ? "monthCoverageUncertain" : "incompleteOwnerSnapshot"
            )
            #endif
        }

        isMonthTransitioning = month != nil
        defer { isMonthTransitioning = false }

        guard let window = TradingCalendarDay.fetchWindow(year: id.year, month: id.month) else {
            recompute()
            return
        }

        if ProfileSectionSupport.isLocalDevelopmentProfile(profileID ?? ProfileID("")) {
            recompute()
            return
        }

        #if DEBUG
        if !CalendarCacheProbe.networkRequired {
            CalendarCacheProbe.recordNetworkRequired(month: cacheKey, reason: "authoritativeFetch")
        }
        #endif

        if let profileID, let rpc,
           let applied = try? await CalendarBootstrapLoader.load(
               viewerID: profileID,
               rpc: rpc,
               detailCache: detailCache,
               year: id.year,
               month: id.month,
               accountID: calendarAccountFilterID(),
               entryFrom: window.start,
               entryTo: window.end
           )
        {
            SessionNetworkProbe.record(.networkFetch, resource: "calendar.month.rpc", detail: cacheKey)
            if !hasLoadedAccounts {
                accounts = applied.accounts.sorted {
                    $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                accountNames = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.name) })
                hasLoadedAccounts = true
            }
            monthTradeCache[cacheKey] = applied.trades
            CalendarMonthSessionStore.shared.store(applied.trades, year: id.year, month: id.month)
            mergeTrades(applied.trades)
            recompute()
            return
        }

        do {
            #if DEBUG
            if !CalendarCacheProbe.networkRequired {
                CalendarCacheProbe.recordNetworkRequired(month: cacheKey, reason: "repositoryFetch")
            }
            #endif
            SessionNetworkProbe.record(.networkFetch, resource: "calendar.month", detail: cacheKey)
            let fetched = try await trades.trades(
                ownedBy: profileID ?? ProfileID(""),
                accountID: nil,
                entryFrom: window.start,
                entryTo: window.end,
                limit: 500
            )
            monthTradeCache[cacheKey] = fetched
            CalendarMonthSessionStore.shared.store(fetched, year: id.year, month: id.month)
            detailCache.seed(trades: fetched)
            mergeTrades(fetched)
            recompute()
        } catch {
            if month == nil {
                phase = .failed(ProfileSectionSupport.message(for: error))
            }
        }
    }

    private func applyFixtures(profileID: ProfileID) {
        let samples = CalendarFixtures.trades(owner: profileID)
        accounts = CalendarFixtures.accounts(owner: profileID)
        accountNames = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.name) })
        detailCache.seed(accounts: accounts, for: profileID)
        detailCache.seed(trades: samples)
        allTrades = samples
        let id = visibleMonth
        monthTradeCache[id.cacheKey] = samples
        recompute()
    }

    private func mergeTrades(_ trades: [Trade]) {
        var map = Dictionary(uniqueKeysWithValues: allTrades.map { ($0.id, $0) })
        for trade in trades {
            map[trade.id] = trade
        }
        allTrades = Array(map.values)
    }

    private func recompute() {
        let cacheKey = visibleMonth.cacheKey
        let scopedTrades = monthTradeCache[cacheKey].flatMap { $0.isEmpty ? nil : $0 } ?? allTrades
        month = MainThreadWorkProbe.measure("calendar.recompute", surface: "calendar") {
            TradingCalendarAggregator.buildMonth(
                year: visibleMonth.year,
                month: visibleMonth.month,
                trades: scopedTrades,
                accountFilter: accountFilter
            )
        }
    }

    // MARK: - Realtime

    private func startRealtime(profileID: ProfileID) async {
        guard let realtimeHub else { return }
        let channel = RealtimeChannelID(kind: .profile, topic: "calendar:\(profileID.rawValue)")
        if watchedChannel == channel { return }
        await stopRealtime()
        watchedChannel = channel
        try? await realtimeHub.subscriptions.subscribe(channel)
    }

    private func stopRealtime() async {
        guard let realtimeHub, let channel = watchedChannel else { return }
        try? await realtimeHub.subscriptions.unsubscribe(channel)
        watchedChannel = nil
    }

    // MARK: - Incremental updates (for tests / future postgres_changes)

    private func calendarAccountFilterID() -> TradingAccountID? {
        if case .account(let id) = accountFilter { return id }
        return nil
    }

    func applyRealtimeUpsert(_ trade: Trade) {
        SessionNetworkProbe.record(.localMutation, resource: "calendar.trades", detail: trade.id.rawValue)
        mergeTrades([trade])
        CalendarMonthSessionStore.shared.noteCreated(trade)
        // Patch in-memory month buckets that already contain this month.
        let comps = Calendar.current.dateComponents([.year, .month], from: trade.entryAt)
        if let year = comps.year, let month = comps.month {
            let key = CalendarMonthID(year: year, month: month).cacheKey
            if var bucket = monthTradeCache[key] {
                bucket.removeAll { $0.id == trade.id }
                bucket.append(trade)
                monthTradeCache[key] = bucket
            }
        }
        recompute()
    }

    func applyRealtimeDelete(id: TradeID) {
        allTrades.removeAll { $0.id == id }
        for key in monthTradeCache.keys {
            monthTradeCache[key]?.removeAll { $0.id == id }
        }
        recompute()
    }
}
