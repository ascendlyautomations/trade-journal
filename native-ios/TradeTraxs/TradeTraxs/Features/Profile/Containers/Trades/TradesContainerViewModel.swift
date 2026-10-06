import Foundation
import Observation

@Observable
@MainActor
final class TradesContainerViewModel {
    private(set) var state: ProfileSectionLoadState = .idle
    private(set) var journalItems: [TradeOwnerJournalSummary] = []
    /// Grouped Profile Trades cards — rebuilt with ``updateStateForVisibleItems()`` (includes copy mode summary).
    private(set) var renderedTradeSummaries: [TradeSummary] = []

    /// Flat public trade rows backing the section (includes copy siblings before display grouping).
    var items: [TradeSummary] {
        journalItems.map(\.summary)
    }
    private(set) var nextCursor: String?
    private(set) var accountNames: [TradingAccountID: String] = [:]
    private(set) var accountNumbers: [TradingAccountID: String] = [:]
    private(set) var accountModes: [TradingAccountID: TradingAccountMode] = [:]
    private(set) var accountSizes: [TradingAccountID: Decimal] = [:]
    private(set) var isRefreshing = false
    private(set) var paginationErrorMessage: String?

    var filter: ProfileTradesFilter = .all
    var sort: ProfileTradesSort = .newest
    var sharePayload: SharePayload?
    var pendingDelete: TradeSummary?
    var deleteErrorMessage: String?
    private(set) var deletingTradeID: TradeID?

    private let profileID: ProfileID
    private let trades: any TradeRepository
    private let session: any SessionProviding
    private let rpc: (any RPCClient)?
    private let navigationCoordinator: NavigationCoordinator
    private let detailCache: DetailPresentationCache
    private let tradeDetailRepository: any TradeDetailRepository
    private let engagementStore: EngagementStore?
    private let isOwner: Bool

    private var loadTask: Task<Void, Never>?
    private var loadMoreTask: Task<Void, Never>?
    private var hasLoaded = false
    private var isLoadingMore = false
    private var paginationGeneration = 0
    private var syncGeneration: UInt64 = 0
    private var canViewContent = true
    private var isScreenOwned = false
    private var awaitingScreenBootstrap = false
    private var hasAuthoritativeV2Journal = false
    private(set) var isHydratingAuthoritativeJournal = false
    private let initialLoadFailureGrace = ProfileSectionFailureGrace()

    var hasAuthoritativePayload: Bool { hasLoaded }

    #if DEBUG
    /// Tests — loaded list with a stale pagination footer and an explicit cursor.
    func testing_setLoadedPagination(nextCursor: String?, paginationError: String?) {
        hasLoaded = true
        self.nextCursor = nextCursor
        paginationErrorMessage = paginationError
    }

    /// Tests — simulate successful `rpc_v1_profile_tab_trades_v2` hydration.
    func installAuthoritativeV2JournalForTests(_ rows: [TradeOwnerJournalSummary]) {
        hasAuthoritativeV2Journal = true
        journalItems = rows
        hasLoaded = true
        updateStateForVisibleItems()
    }
    #endif

    struct SharePayload: Identifiable, Equatable {
        let id = UUID()
        let text: String
    }

    init(
        profileID: ProfileID,
        trades: any TradeRepository,
        session: any SessionProviding,
        rpc: (any RPCClient)? = nil,
        navigationCoordinator: NavigationCoordinator,
        detailCache: DetailPresentationCache,
        tradeDetailRepository: any TradeDetailRepository,
        engagementStore: EngagementStore? = nil,
        isOwner: Bool = true
    ) {
        self.profileID = profileID
        self.trades = trades
        self.session = session
        self.rpc = rpc
        self.navigationCoordinator = navigationCoordinator
        self.detailCache = detailCache
        self.tradeDetailRepository = tradeDetailRepository
        self.engagementStore = engagementStore
        self.isOwner = isOwner
    }

    /// Screen-owned engagement prefetch — views must not call the repository path.
    func prefetchEngagement(for tradeIDs: [TradeID]) {
        let targets = tradeIDs.map { InteractionTarget.trade($0) }
        guard !targets.isEmpty else { return }
        engagementStore?.prefetch(targets)
    }

    var visibleItems: [TradeSummary] {
        renderedTradeSummaries
    }

    var showsOwnerActions: Bool { isOwner }

    var profileOwnerID: ProfileID { profileID }

    var emptyTitle: String {
        switch filter {
        case .all: return ProfileSection.trades.emptyTitle
        case .wins: return "No winning trades"
        case .losses: return "No losing trades"
        }
    }

    var emptyMessage: String {
        switch filter {
        case .all:
            return isOwner
                ? "Log a trade to start building your journal."
                : "Trades will show up here when they’re shared."
        case .wins: return "Winning trades will show up here."
        case .losses: return "Losing trades will show up here."
        }
    }

    /// Shown when trades exist but the active filter/sort yields no rows — keeps filters visible (Stats parity).
    var filterEmptyMessage: String? {
        guard hasLoaded, !journalItems.isEmpty, visibleItems.isEmpty else { return nil }
        return emptyMessage
    }

    /// Applies screen bootstrap — uses section data when Stage 2 already filled it.
    func applyBootstrap(_ snapshot: ProfileState) {
        if snapshot.didBootstrap || snapshot.phase == .loaded {
            isScreenOwned = true
        }
        if snapshot.isContentLocked {
            canViewContent = false
            hasLoaded = true
            journalItems = []
            state = .empty
            return
        }
        canViewContent = true
        awaitingScreenBootstrap = ProfileSectionInitialLoad.awaitingScreenBootstrap(
            isScreenOwned: isScreenOwned,
            snapshot: snapshot,
            didLoadSection: snapshot.didLoadTrades,
            sectionItemsEmpty: snapshot.trades.isEmpty,
            localItemsEmpty: journalItems.isEmpty
        )
        guard snapshot.didLoadTrades || !snapshot.trades.isEmpty else {
            if hasLoaded {
                updateStateForVisibleItems()
                return
            }
            let plan = ProfileSectionInitialLoad.planWhenBootstrapOmitsSectionPayload(
                snapshot: snapshot,
                hasLoaded: hasLoaded,
                itemsEmpty: journalItems.isEmpty,
                itemCount: journalItems.count,
                currentState: state,
                awaitingScreenBootstrap: awaitingScreenBootstrap
            )
            ProfileSectionInitialLoad.applyBootstrapMissingSectionPlan(
                plan,
                setState: { [self] next in state = next },
                kickDeferredLoad: { [self] in loadIfNeeded() }
            )
            return
        }

        awaitingScreenBootstrap = false
        initialLoadFailureGrace.cancel()

        if hasAuthoritativeV2Journal {
            mergeBootstrapMetadata(from: snapshot)
            seedCachesFromItems()
            updateStateForVisibleItems()
            prefetchEngagement(for: visibleItems.map(\.id))
            hydrateAuthoritativeJournalIfNeeded()
            return
        }

        if hasLoaded {
            if isHydratingAuthoritativeJournal, !hasAuthoritativeV2Journal {
                mergeBootstrapMetadata(from: snapshot)
                seedCachesFromItems()
                updateStateForVisibleItems()
                prefetchEngagement(for: visibleItems.map(\.id))
                return
            }
            if snapshot.trades.isEmpty {
                if snapshot.didLoadTrades {
                    journalItems = []
                    nextCursor = snapshot.tradesNextCursor
                    seedCachesFromItems()
                    updateStateForVisibleItems()
                    prefetchEngagement(for: [])
                    acceptBootstrapPreviewOrHydrate(snapshot)
                }
                return
            }
            journalItems = mergedBootstrapJournal(snapshot: snapshot, summaries: snapshot.trades)
            #if DEBUG
            ProfileTradesHydrationDiagnostics.logHydration(
                source: .bootstrap,
                count: snapshot.trades.count,
                journalCount: journalItems.count
            )
            #endif
            nextCursor = snapshot.tradesNextCursor ?? nextCursor
            mergeBootstrapMetadata(from: snapshot)
            seedCachesFromItems()
            updateStateForVisibleItems()
            prefetchEngagement(for: visibleItems.map(\.id))
            acceptBootstrapPreviewOrHydrate(snapshot)
            return
        }

        let reconciled = ProfileSectionSupport.reconcileSectionItems(
            snapshotItems: snapshot.trades,
            loadedItems: items,
            hasLoaded: hasLoaded,
            didLoadAuthoritative: snapshot.didLoadTrades
        )
        journalItems = mergedBootstrapJournal(snapshot: snapshot, summaries: reconciled.items)
        #if DEBUG
        ProfileTradesHydrationDiagnostics.logHydration(
            source: .bootstrap,
            count: reconciled.items.count,
            journalCount: journalItems.count
        )
        #endif
        hasLoaded = reconciled.hasLoaded
        nextCursor = snapshot.tradesNextCursor
        mergeBootstrapMetadata(from: snapshot)
        accountNumbers = [:]
        seedCachesFromItems()
        paginationErrorMessage = nil
        updateStateForVisibleItems()
        prefetchEngagement(for: visibleItems.map(\.id))
        acceptBootstrapPreviewOrHydrate(snapshot)
    }

    /// Profile → Trades tab — ensure V2 journal hydration even after bootstrap `didLoadTrades`.
    func hydrateAuthoritativeJournalIfNeeded() {
        let decision = Self.v2HydrationDecision(profileID: profileID, rpc: rpc, hasV2Journal: hasAuthoritativeV2Journal)
        #if DEBUG
        ProfileTradesHydrationDiagnostics.logV2Request(
            requested: decision.shouldFetch,
            reason: decision.reason
        )
        #endif
        guard decision.shouldFetch else { return }
        if loadTask != nil { return }
        syncGeneration &+= 1
        let generation = syncGeneration
        isHydratingAuthoritativeJournal = true
        loadTask = Task { await performLoad(reset: true, generation: generation) }
    }

    private func mergeBootstrapMetadata(from snapshot: ProfileState) {
        if !snapshot.accountNames.isEmpty { accountNames = snapshot.accountNames }
        if !snapshot.accountModes.isEmpty {
            accountModes = CopyTradePresentation.mergedAccountModes(
                journalItems: journalItems,
                accountModesByID: snapshot.accountModes
            )
        }
        if !snapshot.accountSizes.isEmpty { accountSizes = snapshot.accountSizes }
    }

    /// Owner journal create/update — upsert immediately; optional page-1 reload uses generation guards.
    func noteJournalMutationSucceeded(_ trade: Trade, preservingExisting existingItems: [TradeSummary] = []) {
        guard trade.ownerProfileID == profileID else { return }
        guard trade.visibility == .public else {
            journalItems.removeAll { $0.id == trade.id }
            detailCache.removeTrade(id: trade.id)
            updateStateForVisibleItems()
            return
        }
        let journal = TradeSummaryMapper.ownerJournal(fromListTrade: trade)
        var next = journalItems.isEmpty
            ? ProfileTradesJournalMapping.journalItems(from: existingItems)
            : journalItems
        if let index = next.firstIndex(where: { $0.id == journal.id }) {
            next[index] = journal
        } else {
            next.insert(journal, at: 0)
        }
        journalItems = next
        hasLoaded = true
        detailCache.seedPresentationSeed(TradeSummaryMapper.presentationSeed(fromListTrade: trade))
        updateStateForVisibleItems()
        prefetchEngagement(for: visibleItems.map(\.id))
    }

    func loadIfNeeded() {
        if !hasAuthoritativeV2Journal {
            hydrateAuthoritativeJournalIfNeeded()
            if loadTask != nil { return }
        }
        guard !hasLoaded, loadTask == nil else { return }
        guard canViewContent else {
            hasLoaded = true
            state = .empty
            return
        }
        if awaitingScreenBootstrap {
            if journalItems.isEmpty {
                state = .loading
            }
            return
        }
        syncGeneration &+= 1
        let generation = syncGeneration
        loadTask = Task { await performLoad(reset: true, generation: generation) }
    }

    func refresh() async {
        await refresh(background: false)
    }

    func setFilter(_ value: ProfileTradesFilter) {
        guard filter != value else { return }
        ExperienceHaptics.play(.selection)
        filter = value
        updateStateForVisibleItems()
    }

    func setSort(_ value: ProfileTradesSort) {
        guard sort != value else { return }
        ExperienceHaptics.play(.selection)
        sort = value
        updateStateForVisibleItems()
    }

    func loadMoreIfNeeded(currentTradeID: TradeID?) async {
        guard hasLoaded else {
            #if DEBUG
            ProfileTradesPaginationDiagnostics.skipped(reason: "notLoaded")
            #endif
            return
        }
        guard nextCursor != nil else {
            // End of the list is not a failed page. Drop any error left by an
            // earlier request so the footer cannot keep offering a retry.
            paginationErrorMessage = nil
            #if DEBUG
            ProfileTradesPaginationDiagnostics.skipped(reason: "noMore")
            #endif
            return
        }
        guard loadMoreTask == nil, !isLoadingMore else {
            #if DEBUG
            ProfileTradesPaginationDiagnostics.skipped(reason: "inFlight")
            #endif
            return
        }
        guard let currentTradeID, visibleItems.last?.id == currentTradeID else { return }

        let cursor = nextCursor
        let generation = paginationGeneration
        isLoadingMore = true
        #if DEBUG
        ProfileTradesPaginationDiagnostics.started(profileID: profileID, cursor: cursor)
        #endif

        loadMoreTask = Task { @MainActor in
            defer {
                isLoadingMore = false
                loadMoreTask = nil
            }
            await performLoadMore(cursor: cursor, generation: generation)
        }
    }

    func retryLoadMore() {
        paginationErrorMessage = nil
        guard let lastID = visibleItems.last?.id else { return }
        Task { await loadMoreIfNeeded(currentTradeID: lastID) }
    }

    func openTrade(_ summary: TradeSummary) {
        detailCache.seedPresentationSeed(DetailPresentationSeed(summary: summary))
        let preview = TradeSummaryMapper.previewTrade(from: summary)
        #if DEBUG
        SharedTradeOpenDiagnostics.tapped(tradeID: summary.id)
        #endif
        navigationCoordinator.pushSocialTrade(summary.id, cache: detailCache, preview: preview)
    }

    func addTrade() {
        ExperienceHaptics.play(.selection)
        navigationCoordinator.openCompose(.trade)
    }

    func editTrade(_ summary: TradeSummary) {
        guard isOwner else { return }
        ExperienceHaptics.play(.selection)
        Task {
            do {
                _ = try await tradeDetailRepository.load(tradeID: summary.id, policy: .default)
                navigationCoordinator.editTrade(summary.id)
            } catch {
                paginationErrorMessage = ProfileSectionSupport.message(for: error)
                ExperienceHaptics.play(.warning)
            }
        }
    }

    func shareTrade(_ summary: TradeSummary) {
        ExperienceHaptics.play(.selection)
        let pnl = TradeDisplay.pnlText(summary.realizedPnL)
        let side = summary.side == .long ? "Long" : "Short"
        sharePayload = SharePayload(
            text: "\(summary.symbol.ticker) \(side) \(pnl) on TradeTraxs"
        )
    }

    func requestDelete(_ summary: TradeSummary) {
        guard isOwner, deletingTradeID == nil else { return }
        ExperienceHaptics.play(.warning)
        TradeDeleteConfirmationPresenter.scheduleConfirmation { [weak self] in
            self?.pendingDelete = summary
        }
    }

    func isDeletingTrade(_ id: TradeID) -> Bool {
        deletingTradeID == id
    }

    func confirmDelete() async {
        guard isOwner, deletingTradeID == nil, let summary = pendingDelete else { return }
        pendingDelete = nil
        deletingTradeID = summary.id
        deleteErrorMessage = nil
        defer { deletingTradeID = nil }
        let previous = TradeSummaryMapper.previewTrade(from: summary)
        let owner = summary.ownerProfileID
        do {
            try await OwnerTradeDeletionService.deleteOwnedTrade(
                tradeID: summary.id,
                owner: owner,
                previous: previous,
                trades: trades,
                session: session,
                detailCache: detailCache,
                tradeDetailRepository: tradeDetailRepository
            )
            ExperienceHaptics.play(.success)
        } catch {
            deleteErrorMessage = ProfileSectionSupport.message(for: error)
            ExperienceHaptics.play(.warning)
        }
    }

    func handleJournalMutation() {
        switch TradeJournalMutationStore.shared.latest {
        case .created(let trade) where trade.visibility == .public && trade.ownerProfileID == profileID:
            let journal = TradeSummaryMapper.ownerJournal(fromListTrade: trade)
            journalItems.removeAll { $0.id == journal.id }
            journalItems.insert(journal, at: 0)
            detailCache.seedPresentationSeed(TradeSummaryMapper.presentationSeed(fromListTrade: trade))
            updateStateForVisibleItems()
        case .updated(let trade) where trade.ownerProfileID == profileID:
            let journal = TradeSummaryMapper.ownerJournal(fromListTrade: trade)
            if trade.visibility == .public {
                if let index = journalItems.firstIndex(where: { $0.id == journal.id }) {
                    journalItems[index] = journal
                } else {
                    journalItems.insert(journal, at: 0)
                }
                detailCache.seedPresentationSeed(TradeSummaryMapper.presentationSeed(fromListTrade: trade))
            } else {
                journalItems.removeAll { $0.id == journal.id }
                detailCache.removeTrade(id: journal.id)
            }
            updateStateForVisibleItems()
        case .deleted(let id, let owner) where owner == profileID:
            journalItems.removeAll { $0.id == id }
            detailCache.removeTrade(id: id)
            updateStateForVisibleItems()
        case .bulkImport:
            Task { await refresh() }
        default:
            break
        }
    }

    // MARK: - Private

    private func refresh(background: Bool) async {
        loadTask?.cancel()
        cancelLoadMore(reason: "refresh")
        syncGeneration &+= 1
        let generation = syncGeneration
        if !background {
            isRefreshing = true
        }
        await performLoad(reset: true, generation: generation)
        isRefreshing = false
    }

    private func cancelLoadMore(reason: String) {
        paginationGeneration &+= 1
        loadMoreTask?.cancel()
        loadMoreTask = nil
        isLoadingMore = false
        #if DEBUG
        ProfileTradesPaginationDiagnostics.cancelledOrStale(reason: reason)
        #endif
    }

    private func performLoadMore(cursor: String?, generation: Int) async {
        guard generation == paginationGeneration else {
            #if DEBUG
            ProfileTradesPaginationDiagnostics.cancelledOrStale(reason: "generationMismatch")
            #endif
            return
        }

        do {
            let pageJournal: [TradeOwnerJournalSummary]
            let newCursor: String?
            if BackendV2FeatureFlags.isEnabled(.profile), let rpc {
                let applied = try await ProfileTabBootstrapLoader.load(
                    tab: .trades,
                    profileID: profileID,
                    rpc: rpc,
                    detailCache: detailCache,
                    cursor: cursor
                )
                pageJournal = Self.journalItems(from: applied)
                newCursor = applied.nextCursor
                seedTradeEngagement(applied.tradeEngagement)
            } else {
                let page = try await trades.trades(
                    ownedBy: profileID,
                    accountID: nil,
                    page: PageRequest(cursor: cursor, limit: 30),
                    publicOnly: true
                )
                pageJournal = page.items.map { TradeSummaryMapper.ownerJournal(fromListTrade: $0) }
                newCursor = page.nextCursor
            }

            guard generation == paginationGeneration, !Task.isCancelled else {
                #if DEBUG
                ProfileTradesPaginationDiagnostics.cancelledOrStale(reason: "cancelledAfterFetch")
                #endif
                return
            }

            #if DEBUG
            ProfileTradesPaginationDiagnostics.response(
                count: pageJournal.count,
                hasMore: newCursor != nil
            )
            #endif

            let beforeCount = journalItems.count
            if pageJournal.isEmpty {
                nextCursor = nil
            } else {
                appendUniqueJournal(pageJournal)
                nextCursor = newCursor
                if journalItems.count == beforeCount {
                    nextCursor = nil
                }
            }
            paginationErrorMessage = nil
            updateStateForVisibleItems()
            prefetchEngagement(for: visibleItems.map(\.id))

            #if DEBUG
            ProfileTradesPaginationDiagnostics.completed(
                appended: journalItems.count - beforeCount,
                hasMore: nextCursor != nil
            )
            #endif
        } catch is CancellationError {
            #if DEBUG
            ProfileTradesPaginationDiagnostics.cancelledOrStale(reason: "cancellation")
            #endif
        } catch {
            if Self.isBenignPaginationCancellation(error) {
                #if DEBUG
                ProfileTradesPaginationDiagnostics.cancelledOrStale(reason: "cancelled")
                #endif
                return
            }
            guard generation == paginationGeneration, !Task.isCancelled else {
                #if DEBUG
                ProfileTradesPaginationDiagnostics.cancelledOrStale(reason: "cancelledAfterError")
                #endif
                return
            }
            paginationErrorMessage = Self.loadMoreFailureMessage
            #if DEBUG
            ProfileTradesPaginationDiagnostics.failed(message: ProfileSectionSupport.message(for: error))
            #endif
        }
    }

    private func performLoad(reset: Bool, generation: UInt64) async {
        if reset {
            cancelLoadMore(reason: "reset")
        }
        if ProfileSectionSupport.isLocalDevelopmentProfile(profileID) {
            guard generation == syncGeneration else {
                loadTask = nil
                return
            }
            hasLoaded = true
            if profileID == DemoExperienceSupport.profileID {
                journalItems = DemoCanonicalDataset.trades().map {
                    TradeSummaryMapper.ownerJournal(fromListTrade: $0)
                }
                accountNames = Dictionary(
                    uniqueKeysWithValues: DemoCanonicalDataset.accounts().map { ($0.id, $0.name) }
                )
                accountModes = DemoCanonicalDataset.accountModes()
                accountSizes = Dictionary(
                    uniqueKeysWithValues: DemoCanonicalDataset.accounts().compactMap { account in
                        account.size.map { (account.id, $0.amount) }
                    }
                )
            } else {
                journalItems = ProfileTradeFixtures.samples(owner: profileID).map {
                    TradeSummaryMapper.ownerJournal(fromListTrade: $0)
                }
                accountNames = ProfileTradeFixtures.accountNames()
                accountModes = ProfileTradeFixtures.accountModes()
                accountSizes = ProfileTradeFixtures.accountSizes()
            }
            accountNumbers = [:]
            seedCachesFromItems()
            nextCursor = nil
            updateStateForVisibleItems()
            prefetchEngagement(for: visibleItems.map(\.id))
            loadTask = nil
            return
        }

        if reset, journalItems.isEmpty {
            state = .loading
        }
        initialLoadFailureGrace.cancel()

        #if DEBUG
        ProfileTradesHydrationDiagnostics.logPerformLoadStart(
            reset: reset,
            journalCount: journalItems.count
        )
        #endif

        var usedV2Journal = false
        var pageJournalCount = 0
        do {
            let pageJournal: [TradeOwnerJournalSummary]
            let newCursor: String?
            let hydrationSource: ProfileTradesHydrationDiagnostics.Source
            if BackendV2FeatureFlags.isEnabled(.profile), let rpc {
                let applied = try await ProfileTabBootstrapLoader.load(
                    tab: .trades,
                    profileID: profileID,
                    rpc: rpc,
                    detailCache: detailCache,
                    cursor: nil
                )
                pageJournal = Self.journalItems(from: applied)
                newCursor = applied.nextCursor
                if let names = applied.accountNames { accountNames = names }
                if let modes = applied.accountModes {
                    accountModes = CopyTradePresentation.mergedAccountModes(
                        journalItems: pageJournal,
                        accountModesByID: modes
                    )
                }
                if let sizes = applied.accountSizes { accountSizes = sizes }
                seedTradeEngagement(applied.tradeEngagement)
                usedV2Journal = Self.appliedUsesAuthoritativeV2Journal(applied)
                hydrationSource = usedV2Journal ? .v2 : .v1
                pageJournalCount = pageJournal.count
            } else {
                let page = try await trades.trades(
                    ownedBy: profileID,
                    accountID: nil,
                    page: PageRequest(limit: 30),
                    publicOnly: true
                )
                pageJournal = page.items.map { TradeSummaryMapper.ownerJournal(fromListTrade: $0) }
                newCursor = page.nextCursor
                usedV2Journal = false
                hydrationSource = .repository
                pageJournalCount = pageJournal.count
            }

            guard generation == syncGeneration, !Task.isCancelled else {
                #if DEBUG
                ProfileTradesHydrationDiagnostics.logPerformLoadFinished(
                    usedV2: usedV2Journal,
                    pageCount: pageJournalCount,
                    journalCount: journalItems.count,
                    error: "cancelledOrStaleGeneration"
                )
                #endif
                loadTask = nil
                isHydratingAuthoritativeJournal = false
                return
            }

            if usedV2Journal {
                hasAuthoritativeV2Journal = true
                applyAuthoritativeJournalPage(pageJournal, reset: reset)
            } else {
                let preserveIDs = ownerPublicTradePreserveIDs()
                let pageSummaries = pageJournal.map(\.summary)
                if reset, !journalItems.isEmpty {
                    let reconciled = ProfilePersistentReconcile.reconcileTradeSummaries(
                        existing: items,
                        incoming: pageSummaries,
                        preserveIDs: preserveIDs
                    ).items
                    var next = reconcileJournal(snapshot: reconciled, loaded: journalItems)
                    let pageByID = Dictionary(uniqueKeysWithValues: pageJournal.map { ($0.id, $0) })
                    next = next.map { pageByID[$0.id] ?? $0 }
                    journalItems = next
                } else {
                    journalItems = pageJournal
                }
            }
            #if DEBUG
            ProfileTradesHydrationDiagnostics.logHydration(
                source: hydrationSource,
                count: pageJournal.count,
                journalCount: journalItems.count
            )
            #endif
            nextCursor = newCursor
            seedCachesFromItems()
            hasLoaded = true
            paginationErrorMessage = nil
            initialLoadFailureGrace.cancel()
            updateStateForVisibleItems()
            prefetchEngagement(for: visibleItems.map(\.id))
            if isOwner {
                OwnerProfileOptimisticStore.shared.syncOwnerTradesState(items)
            }
            #if DEBUG
            ProfileTradesHydrationDiagnostics.logPerformLoadFinished(
                usedV2: usedV2Journal,
                pageCount: pageJournalCount,
                journalCount: journalItems.count,
                error: nil
            )
            #endif
        } catch {
            #if DEBUG
            ProfileTradesHydrationDiagnostics.logPerformLoadFinished(
                usedV2: false,
                pageCount: pageJournalCount,
                journalCount: journalItems.count,
                error: String(describing: error)
            )
            #endif
            guard !Task.isCancelled else { return }
            guard generation == syncGeneration else {
                loadTask = nil
                isHydratingAuthoritativeJournal = false
                return
            }
            if journalItems.isEmpty {
                if awaitingScreenBootstrap {
                    state = .loading
                } else {
                    let message = ProfileSectionSupport.message(for: error)
                    let failedGeneration = generation
                    initialLoadFailureGrace.scheduleIfNeeded(message: message) { [weak self] in
                        guard let self else { return false }
                        return !hasLoaded
                            && journalItems.isEmpty
                            && syncGeneration == failedGeneration
                            && !awaitingScreenBootstrap
                    } present: { [weak self] message in
                        self?.state = .failed(message: message)
                    }
                }
            } else if nextCursor != nil {
                paginationErrorMessage = ProfileSectionSupport.message(for: error)
            } else {
                paginationErrorMessage = nil
            }
        }
        loadTask = nil
        isHydratingAuthoritativeJournal = false
    }

    private func seedCachesFromItems() {
        detailCache.seed(publicTradeSummaries: items, for: profileID)
        detailCache.seedPublicAccountMetadata(
            names: sanitizedPublicAccountNames(from: accountNames),
            modes: accountModes,
            sizes: accountSizes,
            for: profileID
        )
    }

    private func ownerPublicTradePreserveIDs() -> Set<TradeID> {
        Set(
            (SessionOwnerTradesStore.shared.cached(for: profileID) ?? [])
                .filter { $0.visibility == .public }
                .map(\.id)
        )
    }

    private func sanitizedPublicAccountNames(
        from names: [TradingAccountID: String]
    ) -> [TradingAccountID: String] {
        Dictionary(uniqueKeysWithValues: names.map { id, name in
            (
                id,
                PublicAccountPrivacy.publicSafeAccountName(
                    rawName: name,
                    accountNumber: nil,
                    category: nil,
                    mode: accountModes[id]
                )
            )
        })
    }

    private func seedTradeEngagement(_ engagement: [String: ProfileBootstrapV1.TradeEngagementWire]?) {
        guard let engagement else { return }
        for (tradeID, wire) in engagement {
            engagementStore?.seed(
                EngagementSnapshot(
                    likeCount: wire.like_count,
                    commentCount: wire.comment_count,
                    viewerHasLiked: wire.liked_by_me
                ),
                for: .trade(TradeID(tradeID))
            )
        }
    }

    private func appendUniqueJournal(_ pageItems: [TradeOwnerJournalSummary]) {
        let existing = Set(journalItems.map(\.id))
        let fresh = pageItems.filter { !existing.contains($0.id) }
        journalItems.append(contentsOf: fresh)
        if !fresh.isEmpty {
            detailCache.seed(publicTradeSummaries: items, for: profileID)
        }
    }

    private func reconcileJournal(
        snapshot: [TradeSummary],
        loaded: [TradeOwnerJournalSummary]
    ) -> [TradeOwnerJournalSummary] {
        guard !loaded.isEmpty else {
            return ProfileTradesJournalMapping.journalItems(from: snapshot)
        }
        let reconciled = ProfileSectionSupport.reconcileLoadedSnapshot(
            snapshot: snapshot,
            loaded: loaded.map(\.summary)
        )
        return ProfileTradesJournalMapping.replaceSummaries(
            reconciled,
            in: loaded,
            preserveRicherExisting: hasAuthoritativeV2Journal
        )
    }

    private func applyAuthoritativeJournalPage(
        _ pageJournal: [TradeOwnerJournalSummary],
        reset: Bool
    ) {
        guard !pageJournal.isEmpty else { return }
        if reset || journalItems.isEmpty {
            journalItems = pageJournal
            return
        }
        let pageByID = Dictionary(uniqueKeysWithValues: pageJournal.map { ($0.id, $0) })
        journalItems = journalItems.map { pageByID[$0.id] ?? $0 }
        let known = Set(journalItems.map(\.id))
        journalItems.append(contentsOf: pageJournal.filter { !known.contains($0.id) })
    }

    /// Bootstrap already returned this page. Keep it when the journal rows still
    /// carry copy linkage and the cursor. Fetch V2 only when that preview is incomplete.
    private func acceptBootstrapPreviewOrHydrate(_ snapshot: ProfileState) {
        guard Self.bootstrapPreviewSatisfiesAuthoritativeJournal(
            seeded: journalItems,
            summaries: snapshot.trades,
            didLoadTrades: snapshot.didLoadTrades
        ) else {
            hydrateAuthoritativeJournalIfNeeded()
            return
        }
        hasAuthoritativeV2Journal = true
    }

    private func mergedBootstrapJournal(
        snapshot: ProfileState,
        summaries: [TradeSummary]
    ) -> [TradeOwnerJournalSummary] {
        if hasAuthoritativeV2Journal, !journalItems.isEmpty {
            return reconcileJournal(snapshot: summaries, loaded: journalItems)
        }
        guard let preview = Self.journalPreview(snapshot.tradeJournalPreview, orderedLike: summaries) else {
            return reconcileJournal(snapshot: summaries, loaded: journalItems)
        }
        if journalItems.isEmpty { return preview }
        let existingByID = Dictionary(uniqueKeysWithValues: journalItems.map { ($0.id, $0) })
        var merged = preview.map { row in
            if let existing = existingByID[row.id],
               ProfileTradesJournalMapping.journalRichness(existing) > ProfileTradesJournalMapping.journalRichness(row)
            {
                return existing
            }
            return row
        }
        let previewIDs = Set(preview.map(\.id))
        merged.append(contentsOf: journalItems.filter { !previewIDs.contains($0.id) })
        return merged
    }

    private static func journalPreview(
        _ preview: [TradeOwnerJournalSummary],
        orderedLike summaries: [TradeSummary]
    ) -> [TradeOwnerJournalSummary]? {
        guard !preview.isEmpty, preview.count == summaries.count else { return nil }
        let byID = Dictionary(uniqueKeysWithValues: preview.map { ($0.id, $0) })
        let ordered = summaries.compactMap { byID[$0.id] }
        guard ordered.count == summaries.count else { return nil }
        return ordered
    }

    /// True when the bootstrap page can be the first journal page, including its cursor.
    private static func bootstrapPreviewSatisfiesAuthoritativeJournal(
        seeded: [TradeOwnerJournalSummary],
        summaries: [TradeSummary],
        didLoadTrades: Bool
    ) -> Bool {
        guard didLoadTrades else { return false }
        if summaries.isEmpty { return true }
        let byID = Dictionary(uniqueKeysWithValues: seeded.map { ($0.id, $0) })
        for summary in summaries {
            guard let row = byID[summary.id] else { return false }
            guard summary.mode == .copyTraded else { continue }
            guard let copy = row.copyTrade else { return false }
            let hasParticipants = copy.sourceAccountID != nil
                || !copy.copiedAccountIDs.isEmpty
                || !copy.participatingAccountModesByID.isEmpty
                || row.accountID != nil
            if !hasParticipants { return false }
        }
        return true
    }

    private struct V2HydrationDecision {
        var shouldFetch: Bool
        var reason: String
    }

    private static func v2HydrationDecision(
        profileID: ProfileID,
        rpc: (any RPCClient)?,
        hasV2Journal: Bool
    ) -> V2HydrationDecision {
        if ProfileSectionSupport.isLocalDevelopmentProfile(profileID) {
            return V2HydrationDecision(shouldFetch: false, reason: "localDevelopmentProfile")
        }
        if hasV2Journal {
            return V2HydrationDecision(shouldFetch: false, reason: "alreadyHydratedV2")
        }
        guard BackendV2FeatureFlags.isEnabled(.profile) else {
            return V2HydrationDecision(shouldFetch: false, reason: "profileFlagOff")
        }
        guard BackendV2FeatureFlags.isEnabled(.profileTradesSummaryV2) else {
            return V2HydrationDecision(shouldFetch: false, reason: "profileTradesSummaryV2Off")
        }
        guard rpc != nil else {
            return V2HydrationDecision(shouldFetch: false, reason: "rpcUnavailable")
        }
        return V2HydrationDecision(shouldFetch: true, reason: "needsAuthoritativeV2Journal")
    }

    private static func appliedUsesAuthoritativeV2Journal(
        _ applied: ProfileTabBootstrapApplier.Applied
    ) -> Bool {
        guard BackendV2FeatureFlags.isEnabled(.profileTradesSummaryV2) else { return false }
        guard let journal = applied.profileTradeJournalItems, !journal.isEmpty else { return false }
        return journal.contains { $0.accountID != nil || $0.copyTrade != nil }
    }

    private static func journalItems(from applied: ProfileTabBootstrapApplier.Applied) -> [TradeOwnerJournalSummary] {
        if let journal = applied.profileTradeJournalItems, !journal.isEmpty {
            return journal
        }
        return ProfileTradesJournalMapping.journalItems(from: applied.tradeSummaries ?? [])
    }

    private func updateStateForVisibleItems() {
        renderedTradeSummaries = ProfileTradesDisplayGrouping.visibleSummaries(
            journalItems: journalItems,
            filter: filter,
            sort: sort,
            accountModesByID: accountModes,
            deferCopyModeSummaryUntilAuthoritativeJournal:
                isHydratingAuthoritativeJournal && !hasAuthoritativeV2Journal
        )
        if !hasLoaded {
            state = .loading
            return
        }
        if journalItems.isEmpty {
            renderedTradeSummaries = []
            state = .empty
            return
        }
        if renderedTradeSummaries.isEmpty {
            state = .loaded(itemCount: 0)
            return
        }
        state = .loaded(itemCount: renderedTradeSummaries.count)
    }

    private static let loadMoreFailureMessage = "Please try again."

    private static func isBenignPaginationCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if case AppError.cancelled = error { return true }
        if case AppError.transport(.cancelled) = error { return true }
        if NetworkTaskCancellation.mapIfCancelled(error) == .cancelled { return true }
        return false
    }
}

nonisolated enum TradeDisplay {
    /// Trading-platform price — `$20,153.25` (USD grouping, preserved decimals).
    private static let priceFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.locale = Locale(identifier: "en_US")
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 8
        formatter.usesGroupingSeparator = true
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    /// Compact trade timestamp — `9:37AM 7/31/26`.
    private static let compactDateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "h:mma M/d/yy"
        formatter.amSymbol = "AM"
        formatter.pmSymbol = "PM"
        return formatter
    }()

    static func pnlText(_ money: Money?) -> String {
        NumberDisplay.pnlWholeDollars(money)
    }

    /// Web parity — null/empty tickers render as em dash (`ProfileTradeCard`).
    static func tickerText(_ ticker: String) -> String {
        let trimmed = ticker.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "—" : trimmed
    }

    static func tickerText(_ symbol: Symbol) -> String {
        tickerText(symbol.ticker)
    }

    static func priceText(_ value: Decimal?) -> String {
        guard let value else { return "—" }
        return priceFormatter.string(from: NSDecimalNumber(decimal: value))
            ?? "$\(value)"
    }

    /// Collapsed Profile card — nearest whole dollar, display only (`$29,406` from `29405.50`).
    static func profileCardExecutionPriceText(_ value: Decimal?) -> String {
        guard let value else { return "—" }
        var input = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &input, 0, .plain)
        return NumberDisplay.currency(
            rounded,
            minimumFractionDigits: 0,
            maximumFractionDigits: 0
        )
    }

    static func executionPriceText(
        _ value: Decimal?,
        display: TradeExecutionMetricsPriceDisplay
    ) -> String {
        switch display {
        case .fullPrecision:
            return priceText(value)
        case .profileCardRounded:
            return profileCardExecutionPriceText(value)
        }
    }

    static func rrText(_ value: Decimal?) -> String {
        guard let value else { return "—" }
        return "RR \(NumberDisplay.decimal(value, minimumFractionDigits: 1, maximumFractionDigits: 1))"
    }

    /// Compact R multiple — `+7.1R`.
    static func compactRRText(_ value: Decimal?) -> String? {
        guard let value else { return nil }
        let formatted = "\(NumberDisplay.decimal(abs(value), minimumFractionDigits: 1, maximumFractionDigits: 1))R"
        if value > 0 { return "+\(formatted)" }
        if value < 0 { return "-\(formatted)" }
        return formatted
    }

    /// Compact hold label — `8m 42s`.
    static func compactHoldDuration(seconds: Int) -> String? {
        durationTextFromSeconds(seconds)
    }

    /// Journal-style R:R — `1:2.9` when value is the reward multiple.
    static func journalRRText(_ value: Decimal?) -> String? {
        guard let value else { return nil }
        return NumberDisplay.journalRewardMultiple(value)
    }

    static func pointsText(_ value: Decimal?) -> String? {
        guard let value else { return nil }
        let formatted = NumberDisplay.decimal(abs(value), minimumFractionDigits: 0, maximumFractionDigits: 2)
        if value > 0 { return "+\(formatted)" }
        if value < 0 { return "-\(formatted)" }
        return formatted
    }

    static func contractsText(_ value: Decimal) -> String {
        let number = NSDecimalNumber(decimal: value)
        if number == number.rounding(accordingToBehavior: nil) {
            return NumberDisplay.integer(number.intValue)
        }
        return NumberDisplay.decimal(value, minimumFractionDigits: 0, maximumFractionDigits: 8)
    }

    /// Quick stats — em dash when contracts were absent on the wire (mapped as zero).
    static func contractsText(for quantity: Decimal) -> String {
        guard quantity != 0 else { return "—" }
        return contractsText(quantity)
    }

    static func durationText(entryAt: Date, exitAt: Date?) -> String? {
        guard let exitAt, exitAt > entryAt else { return nil }
        let seconds = Int(exitAt.timeIntervalSince(entryAt).rounded(.down))
        guard seconds > 0 else { return nil }
        let allowSubMinute = TradeHoldDuration.timestampsSupportSecondPrecision(
            entryAt: entryAt,
            exitAt: exitAt
        )
        return TradeHoldDuration.formatSeconds(seconds, allowSubMinuteSeconds: allowSubMinute)
    }

    /// Public trade-card duration — derived only from entry/exit timestamps.
    static func cardDurationText(for trade: Trade) -> String? {
        cardDurationText(entryAt: trade.entryAt, exitAt: trade.exitAt)
    }

    static func cardDurationText(for summary: TradeSummary) -> String? {
        if let text = summary.durationText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty
        {
            return text
        }
        if let seconds = summary.durationSeconds, seconds >= 0 {
            return cardDurationTextFromSeconds(seconds, allowSubMinuteSeconds: true)
        }
        return cardDurationText(entryAt: summary.entryAt, exitAt: summary.exitAt)
    }

    static func cardDurationText(entryAt: Date, exitAt: Date?) -> String? {
        guard let exitAt, exitAt > entryAt else { return nil }
        let seconds = Int(exitAt.timeIntervalSince(entryAt).rounded(.down))
        guard seconds > 0 else { return nil }
        let allowSubMinute = TradeHoldDuration.timestampsSupportSecondPrecision(
            entryAt: entryAt,
            exitAt: exitAt
        )
        return cardDurationTextFromSeconds(seconds, allowSubMinuteSeconds: allowSubMinute)
    }

    /// Prefer authoritative DB duration fields, then entry/exit timestamps.
    static func holdDuration(for trade: Trade) -> String? {
        if let text = trade.durationText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty
        {
            return text
        }
        if let seconds = trade.durationSeconds, seconds >= 0 {
            return durationTextFromSeconds(seconds, allowSubMinuteSeconds: true)
        }
        return durationText(entryAt: trade.entryAt, exitAt: trade.exitAt)
    }

    static func holdDuration(for item: TradeOwnerJournalSummary) -> String? {
        holdDuration(for: TradeSummaryMapper.listMatchTrade(from: item))
    }

    /// Personal Trades list — prefer entry→exit duration (full components) over stored abbreviations.
    static func journalCardDuration(for item: TradeOwnerJournalSummary) -> String? {
        let trade = TradeSummaryMapper.listMatchTrade(from: item)
        if let fromTimes = durationText(entryAt: trade.entryAt, exitAt: trade.exitAt) {
            return fromTimes
        }
        if let seconds = trade.durationSeconds, seconds >= 0 {
            return durationTextFromSeconds(seconds, allowSubMinuteSeconds: true)
        }
        if let text = trade.durationText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty
        {
            return text
        }
        return nil
    }

    private static func durationTextFromSeconds(
        _ seconds: Int,
        allowSubMinuteSeconds: Bool = true
    ) -> String? {
        TradeHoldDuration.formatSeconds(seconds, allowSubMinuteSeconds: allowSubMinuteSeconds)
    }

    private static func cardDurationTextFromSeconds(
        _ seconds: Int,
        allowSubMinuteSeconds: Bool = true
    ) -> String? {
        TradeHoldDuration.formatSeconds(seconds, allowSubMinuteSeconds: allowSubMinuteSeconds)
    }

    /// Account · date · time line for journal cards.
    static func journalContextLine(accountName: String?, at date: Date) -> String {
        let stamp = journalDateTimeFormatter.string(from: date)
        if let accountName, !accountName.isEmpty {
            return "\(accountName) · \(stamp)"
        }
        return stamp
    }

    private static let journalDateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d · h:mm a"
        return formatter
    }()

    static func quantityBadgeText(_ value: Decimal) -> String {
        "Qty \(contractsText(value))"
    }

    static func dateText(_ date: Date) -> String {
        dayFormatter.string(from: date)
    }

    static func sideTitle(_ side: TradeSide) -> String {
        side == .long ? "Long" : "Short"
    }

    static func dateTimeText(_ date: Date) -> String {
        compactDateTimeFormatter.string(from: date)
    }

    /// Entry/exit time in quick stats — time-only when paired timestamps share a day.
    static func entryExecutionTimeText(for trade: Trade) -> String {
        entryExecutionTimeText(entryAt: trade.entryAt, exitAt: trade.exitAt)
    }

    static func exitExecutionTimeText(for trade: Trade) -> String {
        exitExecutionTimeText(entryAt: trade.entryAt, exitAt: trade.exitAt)
    }

    static func entryExecutionTimeText(for summary: TradeSummary) -> String {
        entryExecutionTimeText(entryAt: summary.entryAt, exitAt: summary.exitAt)
    }

    static func exitExecutionTimeText(for summary: TradeSummary) -> String {
        exitExecutionTimeText(entryAt: summary.entryAt, exitAt: summary.exitAt)
    }

    static func entryExecutionTimeText(entryAt: Date, exitAt: Date?) -> String {
        executionTimestampText(entryAt, compareTo: exitAt)
    }

    static func exitExecutionTimeText(entryAt: Date, exitAt: Date?) -> String {
        guard let exitAt else { return "—" }
        return executionTimestampText(exitAt, compareTo: entryAt)
    }

    /// Shared social trade detail — entry/exit clock times on one line.
    static func socialSharedExecutionTimeRangeText(for trade: Trade) -> String {
        socialSharedExecutionTimeRangeText(entryAt: trade.entryAt, exitAt: trade.exitAt)
    }

    /// Entry/exit clock times from the trade's execution timestamps.
    static func socialSharedExecutionTimeRangeText(entryAt: Date, exitAt: Date?) -> String {
        let entry = executionTimeOnlyFormatter.string(from: entryAt)
        guard let exitAt else { return entry }
        let exit = executionTimeOnlyFormatter.string(from: exitAt)
        return "\(entry) – \(exit)"
    }

    /// Feed copy-trade metadata — execution clocks, then the canonical trade date.
    static func feedCopyExecutionMetadata(entryAt: Date, exitAt: Date?) -> String {
        let times = socialSharedExecutionTimeRangeText(entryAt: entryAt, exitAt: exitAt)
        return "\(times) • \(dateText(entryAt))"
    }

    /// Shared social trade detail — calendar day for the execution (entry day).
    static func socialSharedTradeDateText(for trade: Trade) -> String {
        dateText(trade.entryAt)
    }

    private static let executionTimeOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    private static func executionTimestampText(_ date: Date, compareTo other: Date?) -> String {
        if let other, Calendar.current.isDate(date, inSameDayAs: other) {
            return executionTimeOnlyFormatter.string(from: date)
        }
        return journalDateTimeFormatter.string(from: date)
    }

    /// Web `resolveTradeModeBadgeLabel` account-status titles.
    static func accountStatusTitle(_ mode: TradingAccountMode) -> String {
        switch mode {
        case .funded: return "Funded"
        case .evaluation: return "Evaluation"
        case .live: return "Live"
        case .sim: return "SIM"
        case .backtest: return "Backtest"
        }
    }

    static func tradeModeFallbackTitle(_ mode: TradeMode?) -> String? {
        guard let mode else { return nil }
        switch mode {
        case .live: return "Live"
        case .sim: return "SIM"
        case .replay: return "Replay"
        case .backtest: return "Backtest"
        case .copyTraded: return "Copy Traded"
        }
    }

    /// Web `formatTradingAccountModeLabel` — short header status (`Eval`, not `Evaluation`).
    static func accountModeCompactTitle(_ mode: TradingAccountMode) -> String {
        switch mode {
        case .evaluation: return "Eval"
        case .funded: return "Funded"
        case .live: return "Live"
        case .sim: return "Sim"
        case .backtest: return "Backtest"
        }
    }

    /// Web `formatAccountBalanceForDisplay` — `50000` → `50K`.
    static func accountSizeText(_ size: Decimal?) -> String {
        guard let size else { return "" }
        let number = NSDecimalNumber(decimal: size).doubleValue
        guard number.isFinite else { return "" }
        if abs(number) >= 1_000 {
            let thousands = number / 1_000
            if thousands.rounded() == thousands {
                return "\(Int(thousands))K"
            }
            let rounded = (thousands * 10).rounded() / 10
            if rounded.rounded() == rounded {
                return "\(Int(rounded))K"
            }
            return String(format: "%.1fK", rounded)
        }
        let intValue = NSDecimalNumber(decimal: size)
        if intValue == intValue.rounding(accordingToBehavior: nil) {
            return "\(intValue.intValue)"
        }
        return intValue.stringValue
    }

    /// Account identity line — journal+owner: `Name • Number`; public/social: sanitized name only.
    static func accountIdentityLine(
        name: String?,
        size: Decimal? = nil,
        mode: TradingAccountMode? = nil,
        accountNumber: String? = nil,
        audience: TradingAccountDisplay.Audience = .public,
        category: TradingAccountCategory? = nil
    ) -> String? {
        _ = size
        return TradingAccountDisplay.optionalTitle(
            name: name,
            accountNumber: accountNumber,
            audience: audience,
            category: category,
            mode: mode
        )
    }
}
