import Foundation
import Observation
import OSLog

@Observable
@MainActor
final class TradeHistoryViewModel {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private let trades: any TradeRepository
    private let session: any SessionProviding
    private let detailCache: DetailPresentationCache
    private let navigationCoordinator: NavigationCoordinator
    private let rpc: (any RPCClient)?

    private(set) var phase: Phase = .idle
    private(set) var items: [Trade] = []
    private(set) var nextCursor: String?
    private(set) var accounts: [TradingAccount] = []
    private(set) var accountNames: [TradingAccountID: String] = [:]
    private(set) var isRefreshing = false
    private(set) var isLoadingMore = false
    private(set) var paginationErrorMessage: String?
    var searchText = ""
    var filters = TradeHistoryFilters()
    var draftFilters = TradeHistoryFilters()
    var showsFilterSheet = false
    var pendingDelete: Trade?
    var sharePayload: SharePayload?

    /// Local-only constraints seeded from Dashboard chart taps (not server filter fields).
    private var localWeekday: Int?
    private var localHour: Int?
    private var localSessionLabel: String?
    private var localHoldRange: TradeHistoryLaunchSeed.HoldSecondsRange?

    struct SharePayload: Identifiable, Equatable {
        let id = UUID()
        let text: String
    }

    private var profileID: ProfileID?
    private var loadTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var hasLoaded = false
    private var lastQueryKey: String?
    private var loadGeneration: UInt64 = 0
    private var coldLoadFinished = false
    #if DEBUG
    private var stageCorrelation: String?
    #endif

    init(
        trades: any TradeRepository,
        session: any SessionProviding,
        detailCache: DetailPresentationCache,
        navigationCoordinator: NavigationCoordinator,
        rpc: (any RPCClient)? = nil
    ) {
        self.trades = trades
        self.session = session
        self.detailCache = detailCache
        self.navigationCoordinator = navigationCoordinator
        self.rpc = rpc
    }

    var summary: TradeHistorySummary {
        TradeHistorySummary.from(trades: items)
    }

    var activeChips: [TradeHistoryFilterChip] {
        filters.activeChips { displayAccountTitle(for: $0) ?? accountNames[$0] }
    }

    var showsClearAllChips: Bool {
        activeChips.count >= 2
    }

    var showsFilterIndicator: Bool {
        filters.hasActiveFilterConstraints
    }

    var resultCountLabel: String {
        let count = summary.tradeCount
        return count == 1 ? "1 trade" : "\(count) trades"
    }

    var accountMenuTitle: String {
        switch filters.account {
        case .all:
            return "All Accounts"
        case .account(let id):
            if let account = accounts.first(where: { $0.id == id }) {
                return TradingAccountDisplay.ownerDropdownLine(for: account)
            }
            return displayAccountTitle(for: id) ?? "Account"
        }
    }

    var accountsForMenu: [TradingAccount] {
        let selectedID: TradingAccountID? = {
            if case .account(let id) = filters.account { return id }
            return nil
        }()
        return OwnerAccountDropdownSupport.menuAccounts(
            profileID: profileID,
            fallback: accounts,
            preservingSelection: selectedID
        )
    }

    var ownerAccountsProfileID: ProfileID? { profileID }

    /// Owner journal / filter labels — `Name • Number`.
    func displayAccountTitle(for accountID: TradingAccountID?) -> String? {
        guard let accountID else { return nil }
        if let account = accounts.first(where: { $0.id == accountID }) {
            return TradingAccountDisplay.optionalTitle(
                name: account.name,
                accountNumber: account.accountNumber,
                audience: .owner
            )
        }
        return TradingAccountDisplay.optionalTitle(
            name: accountNames[accountID],
            audience: .owner
        )
    }

    var isEmptyJournal: Bool {
        phase == .loaded && items.isEmpty && !hasActiveQuery
    }

    var isEmptyFiltered: Bool {
        phase == .loaded && items.isEmpty && hasActiveQuery
    }

    var hasActiveQuery: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || filters.hasActiveFilterConstraints
    }

    private var matchContext: TradeHistoryMatchContext {
        var context = TradeHistoryMatchContext()
        context.accountTitles = accountNames
        context.accountModes = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.mode) })
        return context
    }

    private var hasLocalBrowseConstraints: Bool {
        localWeekday != nil || localHour != nil
            || localSessionLabel != nil || localHoldRange != nil
    }

    var canLoadMore: Bool { nextCursor != nil && !isLoadingMore }

    func loadIfNeeded() {
        if hasLoaded, loadTask == nil {
            #if DEBUG
            TradeHistoryLoadProbe.beginLoad()
            TradeHistoryLoadProbe.markCacheHit()
            TradeHistoryLoadProbe.markFirstUsefulRender()
            #endif
            SessionNetworkProbe.record(.cacheHit, resource: "trades.history.vm")
            return
        }
        if coldLoadFinished, !hasLoaded {
            return
        }
        guard loadTask == nil else { return }
        loadGeneration &+= 1
        let generation = loadGeneration
        loadTask = Task { await performLoad(reason: "open", preserveScroll: false, generation: generation) }
    }

    func refresh() async {
        coldLoadFinished = false
        loadGeneration &+= 1
        await reload(reason: "refresh", preserveScroll: false, generation: loadGeneration)
    }

    func searchChanged() {
        searchTask?.cancel()
        #if DEBUG
        TradeHistoryLoadProbe.markCancelled()
        #endif
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 280_000_000)
            guard !Task.isCancelled else { return }
            await reload(reason: "search")
        }
    }

    func setAccountFilter(_ filter: DashboardAccountFilter) {
        guard filters.account != filter else { return }
        ExperienceHaptics.play(.selection)
        filters.account = filter
        Task { await reload(reason: "account") }
    }

    func openManageAccounts() {
        ExperienceHaptics.play(.selection)
        navigationCoordinator.pushHome(.settings(.tradingAccounts))
    }

    func openFilters() {
        ExperienceHaptics.play(.selection)
        draftFilters = filters
        showsFilterSheet = true
    }

    func applyDraftFilters() {
        ExperienceHaptics.play(.selection)
        filters = draftFilters
        showsFilterSheet = false
        Task { await reload(reason: "filters") }
    }

    func resetDraftFilters() {
        draftFilters.reset()
    }

    func clearAllFilters() {
        ExperienceHaptics.play(.selection)
        filters.reset()
        searchText = ""
        clearLocalBrowseConstraints()
        Task { await reload(reason: "clear") }
    }

    func removeChip(_ chip: TradeHistoryFilterChip) {
        ExperienceHaptics.play(.selection)
        filters.clearChip(id: chip.id)
        Task { await reload(reason: "chip") }
    }

    private func clearLocalBrowseConstraints() {
        localWeekday = nil
        localHour = nil
        localSessionLabel = nil
        localHoldRange = nil
    }

    private func applyLaunchSeedIfNeeded() {
        guard let seed = TradeHistoryLaunchSeed.consume() else { return }
        filters = seed.filters
        searchText = seed.searchText
        localWeekday = seed.weekday
        localHour = seed.hour
        localSessionLabel = {
            guard let raw = seed.sessionLabel?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty
            else { return nil }
            return raw
        }()
        localHoldRange = seed.holdSecondsRange
        hasLoaded = false
        lastQueryKey = nil
    }

    private func matchesLocalBrowseConstraints(_ trade: Trade) -> Bool {
        if let weekday = localWeekday {
            let value = Calendar.current.component(.weekday, from: trade.entryAt)
            if value != weekday { return false }
        }
        if let hour = localHour {
            let value = Calendar.current.component(.hour, from: trade.entryAt)
            if value != hour { return false }
        }
        if let session = localSessionLabel {
            let label = trade.sessionLabel ?? ""
            if !label.localizedCaseInsensitiveContains(session) { return false }
        }
        if let range = localHoldRange {
            guard let exit = trade.exitAt else { return false }
            let seconds = exit.timeIntervalSince(trade.entryAt)
            if !range.contains(seconds) { return false }
        }
        return true
    }

    func loadMoreIfNeeded(currentTradeID: TradeID?) async {
        guard hasLoaded, !isLoadingMore, let cursor = nextCursor else { return }
        guard let currentTradeID, items.last?.id == currentTradeID else { return }
        guard let profileID else { return }

        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            #if DEBUG
            TradeHistoryLoadProbe.markRequest()
            #endif

            if !hasLocalBrowseConstraints,
               let ownerTrades = SessionOwnerTradesStore.shared.cached(for: profileID),
               SessionOwnerTradesStore.shared.isFresh(for: profileID)
            {
                let seeded = TradeHistoryOwnerSeed.page(
                    from: ownerTrades,
                    query: currentQuery,
                    limit: items.count + 40,
                    context: matchContext
                )
                let newItems = Array(seeded.items.dropFirst(items.count))
                if !newItems.isEmpty {
                    appendUnique(newItems)
                    nextCursor = seeded.nextCursor
                    paginationErrorMessage = nil
                    #if DEBUG
                    TradeHistoryLoadProbe.markPageSize(newItems.count)
                    #endif
                    return
                }
            }

            if !hasLocalBrowseConstraints,
               let rpc,
               let applied = try? await TradesListBootstrapLoader.load(
                   viewerID: profileID,
                   rpc: rpc,
                   detailCache: detailCache,
                   query: currentQuery,
                   limit: 40,
                   cursor: cursor
               )
            {
                appendUnique(applied.trades.filter(matchesLocalBrowseConstraints))
                nextCursor = applied.nextCursor
                paginationErrorMessage = nil
                #if DEBUG
                TradeHistoryLoadProbe.markPageSize(applied.trades.count)
                #endif
                return
            }

            let page = try await trades.tradeHistory(
                ownedBy: profileID,
                query: currentQuery,
                page: PageRequest(cursor: cursor, limit: 40)
            )
            appendUnique(page.items.filter(matchesLocalBrowseConstraints))
            nextCursor = page.nextCursor
            paginationErrorMessage = nil
            #if DEBUG
            TradeHistoryLoadProbe.markPageSize(page.items.count)
            #endif
        } catch {
            paginationErrorMessage = ProfileSectionSupport.message(for: error)
        }
    }

    func openTrade(_ trade: Trade) {
        ExperienceHaptics.play(.selection)
        detailCache.seed(trade)
        if let accountID = trade.accountID, let name = accountNames[accountID] {
            detailCache.seedAccountName(name, for: accountID)
        }
        navigationCoordinator.open(.home(.tradeDetail(trade.id)))
    }

    func editTrade(_ trade: Trade) {
        ExperienceHaptics.play(.selection)
        detailCache.seed(trade)
        navigationCoordinator.editTrade(trade.id)
    }

    func shareTrade(_ trade: Trade) {
        ExperienceHaptics.play(.selection)
        let pnl = TradeDisplay.pnlText(trade.realizedPnL)
        let side = trade.side == .long ? "Long" : "Short"
        sharePayload = SharePayload(text: "\(trade.symbol.ticker) \(side) \(pnl) on TradeTraxs")
    }

    func requestDelete(_ trade: Trade) {
        ExperienceHaptics.play(.warning)
        pendingDelete = trade
    }

    func confirmDelete() async {
        guard let trade = pendingDelete else { return }
        pendingDelete = nil
        do {
            try await trades.delete(id: trade.id)
            items.removeAll { $0.id == trade.id }
            detailCache.removeTrade(id: trade.id)
            TradeJournalMutationStore.shared.noteDeleted(id: trade.id, owner: trade.ownerProfileID)
            ExperienceHaptics.play(.success)
        } catch {
            paginationErrorMessage = ProfileSectionSupport.message(for: error)
            ExperienceHaptics.play(.warning)
        }
    }

    func addTrade() {
        ExperienceHaptics.play(.selection)
        navigationCoordinator.openCompose(.trade)
    }

    func handleJournalMutation() {
        // Prefer session-store patch (already applied in TradeJournalMutationStore).
        switch TradeJournalMutationStore.shared.latest {
        case .created, .updated, .deleted:
            if let profileID,
               let snap = TradeHistorySessionStore.shared.restore(
                   profileID: profileID,
                   filters: filters,
                   searchText: searchText
               )
            {
                applySnapshot(snap)
                return
            }
        case .bulkImport, .none:
            break
        }
        guard hasLoaded else { return }
        // Bulk import / unknown mutation — revalidate once.
        Task { await reload(reason: "mutation", preserveScroll: true) }
    }

    func handleAccountMutation() {
        guard hasLoaded || profileID != nil else { return }
        SessionAccountsStore.shared.invalidate(profileID: profileID)
        Task { await loadAccountsOnly() }
    }

    // MARK: - Private

    private var currentQuery: TradeHistoryQuery {
        TradeHistoryQuery(filters: filters, searchText: searchText)
    }

    private func reload(reason: String, preserveScroll: Bool = false, generation: UInt64? = nil) async {
        loadTask?.cancel()
        let activeGeneration = generation ?? {
            loadGeneration &+= 1
            return loadGeneration
        }()
        let task = Task { await performLoad(reason: reason, preserveScroll: preserveScroll, generation: activeGeneration) }
        loadTask = task
        await task.value
    }

    private func performLoad(reason: String, preserveScroll: Bool, generation: UInt64) async {
        // Dashboard chart taps seed filters before the first history load.
        if reason == "open" {
            applyLaunchSeedIfNeeded()
        }

        #if DEBUG
        if reason == "open" {
            TradeHistoryLoadProbe.beginSession()
            TradeHistoryLoadProbe.markFilterStrategy(
                server: [
                    "account", "visibility", "created_at", "direction", "pnl",
                    "ticker/notes/account_name/strategy ilike", "sort keyset", "exclude backtest",
                ],
                local: ["dev fixtures only", "dashboard browse seed"]
            )
        } else {
            TradeHistoryLoadProbe.beginLoad()
        }
        stageCorrelation = DataLoadStageProbe.begin("trades.history")
        DataLoadStageProbe.trace(correlation: stageCorrelation!, stage: "cache.lookup.started")
        #endif

        defer {
            loadTask = nil
            if reason == "open" {
                coldLoadFinished = true
            }
            #if DEBUG
            if let stageCorrelation {
                DataLoadStageProbe.end(
                    correlation: stageCorrelation,
                    terminal: phase == .loaded ? "trades.history.loaded" : "trades.history.terminal"
                )
            }
            #endif
        }

        let userID = await session.currentUserID
        let profileID = ProfileID(userID?.rawValue ?? "dev.screenshot")
        self.profileID = profileID

        // Session store survives ViewModel recreation on push/pop (profile-scoped key).
        // Snapshot only holds trades/filters — accounts live in SessionAccountsStore (Dashboard).
        // Skip restore when local browse constraints are active (seeded from charts).
        let hasLocalBrowse = hasLocalBrowseConstraints
        if reason == "open",
           !hasLocalBrowse,
           let snap = TradeHistorySessionStore.shared.restore(
               profileID: profileID,
               filters: filters,
               searchText: searchText
           )
        {
            #if DEBUG
            DataLoadStageProbe.trace(correlation: stageCorrelation!, stage: "cache.hit", detail: "sessionStore")
            #endif
            applySnapshot(snap)
            await hydrateAccountsFromSession(for: profileID)
            return
        }

        let query = currentQuery
        let queryKey = TradeHistorySessionStore.queryKey(
            profileID: profileID,
            filters: filters,
            searchText: searchText
        )
        if Self.canUseOwnerTradeSeed(reason: reason),
           TradeHistoryOwnerSeed.canSeed(
               query: query,
               hasLocalBrowseConstraints: hasLocalBrowse
           ),
           let ownerTrades = SessionOwnerTradesStore.shared.cached(for: profileID),
           SessionOwnerTradesStore.shared.isFresh(for: profileID)
        {
            let seeded = TradeHistoryOwnerSeed.page(
                from: ownerTrades,
                query: query,
                limit: 40,
                context: matchContext
            )
            #if DEBUG
            DataLoadStageProbe.trace(
                correlation: stageCorrelation!,
                stage: "cache.hit",
                detail: "ownerTrades count=\(seeded.items.count) partial=\(seeded.isPartial)"
            )
            #endif
            async let accountsTask = hydrateAccountsFromSession(for: profileID)
            items = seeded.items.filter(matchesLocalBrowseConstraints)
            nextCursor = seeded.nextCursor
            detailCache.seed(trades: items)
            hasLoaded = true
            lastQueryKey = queryKey
            phase = .loaded
            await accountsTask
            persistSnapshot()
            SessionNetworkProbe.record(
                .cacheHit,
                resource: "trades.history",
                detail: "ownerTradesSeed partial=\(seeded.isPartial)"
            )
            #if DEBUG
            TradeHistoryLoadProbe.markPageSize(items.count)
            TradeHistoryLoadProbe.markFirstUsefulRender()
            #endif
            return
        }

        if !preserveScroll, queryKey == lastQueryKey, hasLoaded, !items.isEmpty, reason == "open" {
            #if DEBUG
            TradeHistoryLoadProbe.markCacheHit()
            TradeHistoryLoadProbe.markFirstUsefulRender()
            #endif
            await hydrateAccountsFromSession(for: profileID)
            return
        }

        if items.isEmpty {
            phase = .loading
        } else if reason == "refresh" {
            isRefreshing = true
        }

        do {
            #if DEBUG
            TradeHistoryLoadProbe.markRequest()
            #endif

            if !hasLocalBrowseConstraints,
               let rpc,
               let applied = try? await TradesListBootstrapLoader.load(
                   viewerID: profileID,
                   rpc: rpc,
                   detailCache: detailCache,
                   query: query,
                   limit: 40,
                   cursor: nil
               )
            {
                applyAccountList(applied.accounts)
                items = applied.trades.filter(matchesLocalBrowseConstraints)
                nextCursor = applied.nextCursor
                hasLoaded = true
                lastQueryKey = queryKey
                phase = .loaded
                paginationErrorMessage = nil
                persistSnapshot()
                SessionNetworkProbe.record(
                    .networkFetch,
                    resource: "trades.history.rpc",
                    detail: "reason=\(reason) count=\(applied.trades.count)"
                )
                #if DEBUG
                TradeHistoryLoadProbe.markPageSize(items.count)
                TradeHistoryLoadProbe.markFirstUsefulRender()
                #endif
                isRefreshing = false
                return
            }

            async let accountsTask = hydrateAccountsFromSession(for: profileID)

            if ProfileSectionSupport.isLocalDevelopmentProfile(profileID) {
                await loadAccounts(for: profileID)
                applyFixtures(profileID: profileID)
                hasLoaded = true
                lastQueryKey = queryKey
                phase = .loaded
                isRefreshing = false
                persistSnapshot()
                #if DEBUG
                TradeHistoryLoadProbe.markFirstUsefulRender()
                #endif
                return
            }

            #if DEBUG
            DataLoadStageProbe.trace(correlation: stageCorrelation!, stage: "request.started")
            #endif
            async let tradesTask = trades.tradeHistory(
                ownedBy: profileID,
                query: query,
                page: PageRequest(limit: 40)
            )
            let page = try await tradesTask
            guard generation == loadGeneration, !Task.isCancelled else { return }
            await accountsTask
            if accounts.isEmpty {
                await loadAccounts(for: profileID)
            }

            items = page.items.filter(matchesLocalBrowseConstraints)
            nextCursor = page.nextCursor
            detailCache.seed(trades: items)
            hasLoaded = true
            lastQueryKey = queryKey
            phase = .loaded
            paginationErrorMessage = nil
            persistSnapshot()
            SessionNetworkProbe.record(
                .networkFetch,
                resource: "trades.history",
                detail: "reason=\(reason) count=\(page.items.count)"
            )
            #if DEBUG
            TradeHistoryLoadProbe.markPageSize(page.items.count)
            TradeHistoryLoadProbe.markFirstUsefulRender()
            AppLog.networking.info(
                "TradeHistory loaded reason=\(reason, privacy: .public) count=\(page.items.count, privacy: .public) hasMore=\(page.nextCursor != nil, privacy: .public)"
            )
            #endif
        } catch is CancellationError {
            #if DEBUG
            TradeHistoryLoadProbe.markCancelled()
            #endif
        } catch {
            let friendly = ProfileSectionSupport.message(for: error)
            if items.isEmpty {
                phase = .failed(friendly)
            }
            paginationErrorMessage = friendly
        }
        isRefreshing = false
    }

    private func loadAccounts(for profileID: ProfileID) async {
        do {
            let loaded = try await SessionAccountsStore.shared.accounts(
                for: profileID,
                detailCache: detailCache,
                repository: trades,
                forceNetwork: false,
                requiresFullOwnerSnapshot: true
            )
            applyAccountList(loaded)
        } catch {
            // Prefer any session/detail seed over wiping the menu empty.
            if accounts.isEmpty {
                applyAccountsFromLocalSession(profileID: profileID)
            }
        }
    }

    private func loadAccountsOnly() async {
        guard let profileID else { return }
        do {
            let loaded = try await SessionAccountsStore.shared.accounts(
                for: profileID,
                detailCache: detailCache,
                repository: trades,
                forceNetwork: true,
                requiresFullOwnerSnapshot: true
            )
            applyAccountList(loaded)
        } catch {
            // keep existing
        }
    }

    /// Cache-only hydrate for snapshot / early-open paths — never forces network.
    /// Dashboard already primed ``SessionAccountsStore``; Trades must reuse it.
    private func hydrateAccountsFromSession(for profileID: ProfileID) async {
        if applyAccountsFromLocalSession(profileID: profileID) {
            return
        }
        // Miss in memory/detail — SessionAccountsStore may still serve disk without a new fetch.
        await loadAccounts(for: profileID)
    }

    @discardableResult
    private func applyAccountsFromLocalSession(profileID: ProfileID) -> Bool {
        let loaded = SessionAccountsStore.shared.cached(for: profileID)
            ?? detailCache.accounts(for: profileID)
            ?? []
        guard !loaded.isEmpty else { return false }
        applyAccountList(loaded)
        SessionNetworkProbe.record(
            .cacheHit,
            resource: "trades.history.accounts",
            detail: "count=\(loaded.count)"
        )
        return true
    }

    private func applyAccountList(_ loaded: [TradingAccount]) {
        // Match Dashboard account menu — show the full session list (no isActive filter).
        accounts = loaded.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        accountNames = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.name) })
    }

    private func applySnapshot(_ snap: TradeHistorySessionStore.Snapshot) {
        filters = snap.filters
        searchText = snap.searchText
        items = snap.items
        nextCursor = snap.nextCursor
        lastQueryKey = snap.queryKey
        hasLoaded = true
        phase = .loaded
        #if DEBUG
        TradeHistoryLoadProbe.markFirstUsefulRender()
        #endif
    }

    private func persistSnapshot() {
        guard let profileID else { return }
        let key = TradeHistorySessionStore.queryKey(
            profileID: profileID,
            filters: filters,
            searchText: searchText
        )
        TradeHistorySessionStore.shared.save(
            TradeHistorySessionStore.Snapshot(
                queryKey: key,
                profileID: profileID,
                items: items,
                nextCursor: nextCursor,
                filters: filters,
                searchText: searchText,
                loadedAt: Date()
            )
        )
    }

    private func applyFixtures(profileID: ProfileID) {
        let all = ProfileTradeFixtures.samples(owner: profileID)
        accounts = PropFirmFixtures.accounts(owner: profileID)
        accountNames = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.name) })
        detailCache.seed(accounts: accounts, for: profileID)
        let query = currentQuery
        var filtered = all.filter {
            TradeHistoryLocalMatch.matches($0, query: query, context: matchContext)
        }
        filtered = filtered.filter(matchesLocalBrowseConstraints)
        filtered = TradeHistorySortSupport.sorted(filtered, sort: filters.sort)
        items = filtered
        nextCursor = nil
        detailCache.seed(trades: filtered)
        persistSnapshot()
        #if DEBUG
        TradeHistoryLoadProbe.markPageSize(filtered.count)
        #endif
    }

    private func appendUnique(_ page: [Trade]) {
        var seen = Set(items.map(\.id))
        for trade in page where !seen.contains(trade.id) {
            items.append(trade)
            seen.insert(trade.id)
        }
        detailCache.seed(trades: page)
        persistSnapshot()
    }

    private static func canUseOwnerTradeSeed(reason: String) -> Bool {
        switch reason {
        case "open", "search", "filters", "chip", "account", "clear":
            return true
        default:
            return false
        }
    }
}
