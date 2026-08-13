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

    private var profileID: ProfileID?
    private var loadTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var hasLoaded = false
    private var lastQueryKey: String?

    init(
        trades: any TradeRepository,
        session: any SessionProviding,
        detailCache: DetailPresentationCache,
        navigationCoordinator: NavigationCoordinator
    ) {
        self.trades = trades
        self.session = session
        self.detailCache = detailCache
        self.navigationCoordinator = navigationCoordinator
    }

    var summary: TradeHistorySummary {
        TradeHistorySummary.from(trades: items)
    }

    var activeChips: [TradeHistoryFilterChip] {
        filters.activeChips { accountNames[$0] }
    }

    var accountMenuTitle: String {
        switch filters.account {
        case .all:
            return "All Accounts"
        case .account(let id):
            return accountNames[id] ?? "Account"
        }
    }

    var isEmptyJournal: Bool {
        phase == .loaded && items.isEmpty && !hasActiveQuery
    }

    var isEmptyFiltered: Bool {
        phase == .loaded && items.isEmpty && hasActiveQuery
    }

    var hasActiveQuery: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || filters.hasActiveConstraints
    }

    var canLoadMore: Bool { nextCursor != nil && !isLoadingMore }

    func loadIfNeeded() {
        if hasLoaded, loadTask == nil {
            #if DEBUG
            TradeHistoryLoadProbe.markCacheHit()
            #endif
            SessionNetworkProbe.record(.cacheHit, resource: "trades.history.vm")
            return
        }
        guard loadTask == nil else { return }
        loadTask = Task { await reload(reason: "open") }
    }

    func refresh() async {
        await reload(reason: "refresh")
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
        navigationCoordinator.openSettings([.tradingAccounts])
    }

    func openFilters() {
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
        Task { await reload(reason: "clear") }
    }

    func removeChip(_ chip: TradeHistoryFilterChip) {
        ExperienceHaptics.play(.selection)
        filters.clearChip(id: chip.id)
        Task { await reload(reason: "chip") }
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
            let page = try await trades.tradeHistory(
                ownedBy: profileID,
                query: currentQuery,
                page: PageRequest(cursor: cursor, limit: 40)
            )
            appendUnique(page.items)
            nextCursor = page.nextCursor
            paginationErrorMessage = nil
            #if DEBUG
            TradeHistoryLoadProbe.markPageSize(page.items.count)
            #endif
        } catch {
            paginationErrorMessage = error.localizedDescription
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

    func addTrade() {
        ExperienceHaptics.play(.selection)
        navigationCoordinator.openCompose(.trade)
    }

    func handleJournalMutation() {
        // Prefer session-store patch (already applied in TradeJournalMutationStore).
        if TradeJournalMutationStore.shared.latestCreatedTrade != nil,
           let profileID,
           let snap = TradeHistorySessionStore.shared.restore(
               profileID: profileID,
               filters: filters,
               searchText: searchText
           )
        {
            applySnapshot(snap)
            return
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

    private func reload(reason: String, preserveScroll: Bool = false) async {
        loadTask?.cancel()
        let task = Task { await performLoad(reason: reason, preserveScroll: preserveScroll) }
        loadTask = task
        await task.value
    }

    private func performLoad(reason: String, preserveScroll: Bool) async {
        #if DEBUG
        if reason == "open" {
            TradeHistoryLoadProbe.beginSession()
            TradeHistoryLoadProbe.markFilterStrategy(
                server: [
                    "account", "visibility", "created_at", "direction", "pnl",
                    "ticker/notes/account_name/strategy ilike", "sort keyset", "exclude backtest",
                ],
                local: ["dev fixtures only"]
            )
        }
        #endif

        let userID = await session.currentUserID
        let profileID = ProfileID(userID?.rawValue ?? "dev.screenshot")
        self.profileID = profileID

        // Session store survives ViewModel recreation on push/pop (profile-scoped key).
        if reason == "open",
           let snap = TradeHistorySessionStore.shared.restore(
               profileID: profileID,
               filters: filters,
               searchText: searchText
           )
        {
            applySnapshot(snap)
            return
        }

        let queryKey = TradeHistorySessionStore.queryKey(
            profileID: profileID,
            filters: filters,
            searchText: searchText
        )
        if !preserveScroll, queryKey == lastQueryKey, hasLoaded, !items.isEmpty, reason == "open" {
            #if DEBUG
            TradeHistoryLoadProbe.markCacheHit()
            TradeHistoryLoadProbe.markFirstUsefulRender()
            #endif
            return
        }

        if items.isEmpty {
            phase = .loading
        } else if reason == "refresh" {
            isRefreshing = true
        }

        do {
            await loadAccounts(for: profileID)

            if ProfileSectionSupport.isLocalDevelopmentProfile(profileID) {
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
            TradeHistoryLoadProbe.markRequest()
            #endif
            let page = try await trades.tradeHistory(
                ownedBy: profileID,
                query: currentQuery,
                page: PageRequest(limit: 40)
            )

            items = page.items
            nextCursor = page.nextCursor
            detailCache.seed(trades: page.items)
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
            if items.isEmpty {
                phase = .failed(error.localizedDescription)
            }
            paginationErrorMessage = error.localizedDescription
        }
        isRefreshing = false
    }

    private func loadAccounts(for profileID: ProfileID) async {
        do {
            let loaded = try await SessionAccountsStore.shared.accounts(
                for: profileID,
                detailCache: detailCache,
                repository: trades,
                forceNetwork: false
            )
            accounts = loaded.filter(\.isActive).sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            accountNames = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.name) })
        } catch {
            accounts = []
        }
    }

    private func loadAccountsOnly() async {
        guard let profileID else { return }
        do {
            let loaded = try await SessionAccountsStore.shared.accounts(
                for: profileID,
                detailCache: detailCache,
                repository: trades,
                forceNetwork: true
            )
            accounts = loaded.filter(\.isActive).sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            accountNames = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.name) })
        } catch {
            // keep existing
        }
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
        var filtered = all.filter { TradeHistoryLocalMatch.matches($0, query: query) }
        // Account-name search for fixtures (server uses account_name ilike).
        let search = query.trimmedSearch
        if !search.isEmpty {
            filtered = filtered.filter { trade in
                let ticker = trade.symbol.ticker.localizedCaseInsensitiveContains(search)
                let notes = trade.notePreview?.localizedCaseInsensitiveContains(search) == true
                let account = trade.accountID.flatMap { accountNames[$0] }
                    .map { $0.localizedCaseInsensitiveContains(search) } ?? false
                return ticker || notes || account
            }
        }
        switch filters.sort {
        case .newest:
            filtered.sort { $0.createdAt > $1.createdAt }
        case .oldest:
            filtered.sort { $0.createdAt < $1.createdAt }
        case .highestPnL:
            filtered.sort { ($0.realizedPnL?.amount ?? 0) > ($1.realizedPnL?.amount ?? 0) }
        case .lowestPnL:
            filtered.sort { ($0.realizedPnL?.amount ?? 0) < ($1.realizedPnL?.amount ?? 0) }
        }
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
}
