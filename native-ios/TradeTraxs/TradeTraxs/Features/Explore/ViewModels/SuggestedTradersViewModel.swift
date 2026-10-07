import Foundation
import Observation

@Observable
@MainActor
final class SuggestedTradersViewModel {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    enum SearchPhase: Equatable {
        case idle
        case searching
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var searchPhase: SearchPhase = .idle
    private(set) var searchResults: [ExploreTraderSuggestion] = []
    var searchText = ""
    private(set) var isLoadingMore = false
    private(set) var loadMoreFailedMessage: String?

    private let explore: any ExploreRepository
    private let search: any SearchRepository
    private let profiles: any ProfileRepository
    private let session: any SessionProviding
    private let detailCache: DetailPresentationCache
    private let navigationCoordinator: NavigationCoordinator
    private let store: ExploreSessionStore
    private let messages: (any MessageRepository)?

    private var viewerID: ProfileID?
    @ObservationIgnored private nonisolated(unsafe) var blockListObserver: NSObjectProtocol?
    private var loadTask: Task<Void, Never>?
    private var loadMoreTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var searchGeneration: UInt64 = 0
    private var loadGeneration = 0
    private var inFlightFollow: Set<ProfileID> = []

    var pendingUnfollow: ExploreTraderSuggestion?

    init(
        explore: any ExploreRepository,
        search: any SearchRepository,
        profiles: any ProfileRepository,
        session: any SessionProviding,
        detailCache: DetailPresentationCache,
        navigationCoordinator: NavigationCoordinator,
        store: ExploreSessionStore? = nil,
        messages: (any MessageRepository)? = nil
    ) {
        self.explore = explore
        self.search = search
        self.profiles = profiles
        self.session = session
        self.detailCache = detailCache
        self.navigationCoordinator = navigationCoordinator
        self.store = store ?? .shared
        self.messages = messages
        blockListObserver = DiscoveryBlockedPeersObserver.install(messages: messages) { [weak self] in
            self?.applyBlockedPeersToVisibleResults()
        }
    }

    deinit {
        if let blockListObserver {
            NotificationCenter.default.removeObserver(blockListObserver)
        }
    }

    var isSearching: Bool {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
    }

    var traders: [ExploreTraderSuggestion] {
        let base: [ExploreTraderSuggestion]
        if let viewerID {
            base = store.suggestedTraders.filter { $0.id != viewerID }
        } else {
            base = store.suggestedTraders
        }
        let unblocked = FeedBlockedAuthorsFilter.shared.filterTraderSuggestions(base)
        return ExploreTraderRanking.preservingOrderPreferringProfilePictures(unblocked) { resolvedProfile(for: $0) }
    }

    var displayedTraders: [ExploreTraderSuggestion] {
        isSearching ? searchResults : traders
    }

    var showsSearchEmpty: Bool {
        isSearching && searchPhase == .idle && searchResults.isEmpty
    }

    var canLoadMore: Bool { store.tradersNextCursor != nil }

    var showsEmpty: Bool {
        phase == .loaded && traders.isEmpty
    }

    var followRevision: Int { FollowMutationCoordinator.shared.revision }

    func loadIfNeeded() {
        guard loadTask == nil else { return }
        loadTask = Task {
            await resolveViewerID()
            await DiscoveryBlockedPeersObserver.sync(messages: messages, force: false)
            applyBlockedPeersToVisibleResults()
            if store.hasBootstrapped, !store.suggestedTraders.isEmpty {
                phase = .loaded
                await hydrateVisibleTraders(
                    source: .initial,
                    authoritativeProfiles: [:],
                    forceNetwork: false,
                    generation: loadGeneration
                )
            } else {
                phase = .loading
                await loadFirstPage(source: .initial, replacing: false, generation: loadGeneration)
            }
            loadTask = nil
        }
    }

    func refresh() async {
        loadTask?.cancel()
        loadMoreTask?.cancel()
        loadMoreFailedMessage = nil
        loadGeneration += 1
        let generation = loadGeneration
        await resolveViewerID()
        await DiscoveryBlockedPeersObserver.sync(messages: messages, force: true)

        let hadTraders = !traders.isEmpty
        if !hadTraders {
            phase = .loading
        }

        await loadFirstPage(source: .refresh, replacing: true, generation: generation)
    }

    func loadMoreIfNeeded() {
        guard !isSearching, canLoadMore, !isLoadingMore, loadMoreTask == nil else { return }
        isLoadingMore = true
        loadMoreFailedMessage = nil
        let generation = loadGeneration
        loadMoreTask = Task {
            defer {
                isLoadingMore = false
                loadMoreTask = nil
            }
            await loadMoreTraders(generation: generation)
        }
    }

    func retryLoadMore() {
        loadMoreFailedMessage = nil
        loadMoreIfNeeded()
    }

    /// Prefer cache-filled avatars — embedded row snapshots may lack `avatar_url`.
    func resolvedProfile(for trader: ExploreTraderSuggestion) -> Profile {
        var merged = trader.profile
        if let cached = detailCache.profile(id: trader.id) {
            merged = merged.mergingCachedPresentation(with: cached)
        }
        return merged
    }

    func isFollowing(_ trader: ExploreTraderSuggestion) -> Bool {
        guard let viewerID else { return store.viewerFollowingIDs.contains(trader.id) }
        return FollowMutationCoordinator.shared.isFollowing(viewer: viewerID, target: trader.id)
    }

    func showsFollowControl(for trader: ExploreTraderSuggestion) -> Bool {
        guard let viewerID else { return true }
        return viewerID != trader.id
    }

    func searchChanged() {
        searchTask?.cancel()
        searchGeneration &+= 1
        let generation = searchGeneration
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            searchResults = []
            searchPhase = .idle
            return
        }

        if viewerID == DemoExperienceSupport.profileID {
            let lowered = query.lowercased()
            let exclude = viewerID ?? DemoExperienceSupport.profileID
            let filtered = DemoGraph.traders(excluding: exclude).filter {
                $0.profile.displayName.lowercased().contains(lowered)
                    || $0.profile.username.lowercased().contains(lowered)
            }
            searchResults = FeedBlockedAuthorsFilter.shared.filterTraderSuggestions(
                ExploreTraderRanking.orderingSearchResults(filtered, query: query) {
                    resolvedProfile(for: $0)
                }
            )
            searchPhase = .idle
            return
        }

        if let viewerID, isLocalDevelopment(viewerID) {
            let lowered = query.lowercased()
            let filtered = ExploreFixtures.traders(excluding: viewerID).filter {
                $0.profile.displayName.lowercased().contains(lowered)
                    || $0.profile.username.lowercased().contains(lowered)
            }
            searchResults = FeedBlockedAuthorsFilter.shared.filterTraderSuggestions(
                ExploreTraderRanking.orderingSearchResults(filtered, query: query) {
                    resolvedProfile(for: $0)
                }
            )
            searchPhase = .idle
            return
        }

        searchPhase = .searching
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled, generation == searchGeneration else { return }
            await performSearch(query: query, generation: generation)
        }
    }

    func toggleFollow(_ trader: ExploreTraderSuggestion) {
        guard let viewerID, viewerID != trader.id else { return }
        if AppLaunchController.shared.isDemoExperienceActive {
            DemoModeAuthGatePresenter.shared.requireAuthentication()
            return
        }
        guard !inFlightFollow.contains(trader.id) else { return }
        if isFollowing(trader) {
            ExperienceHaptics.play(.warning)
            pendingUnfollow = trader
            return
        }
        performFollowChange(trader, currentlyFollowing: false)
    }

    func confirmUnfollow() {
        guard let trader = pendingUnfollow else { return }
        pendingUnfollow = nil
        performFollowChange(trader, currentlyFollowing: true)
    }

    func openTrader(_ trader: ExploreTraderSuggestion) {
        ExperienceHaptics.play(.selection)
        detailCache.seed(resolvedProfile(for: trader))
        if trader.id == viewerID {
            navigationCoordinator.open(.tab(.profile))
            navigationCoordinator.open(.popToRoot(.profile))
            return
        }
        navigationCoordinator.open(.feed(.profile(trader.id)))
    }

    // MARK: - Private

    private func resolveViewerID() async {
        if viewerID != nil { return }
        if let raw = await session.currentUserID?.rawValue {
            viewerID = ProfileID(raw)
        }
    }

    private func loadFirstPage(
        source: SuggestedTradersHydrationDiagnostics.Source,
        replacing: Bool,
        generation: Int
    ) async {
        guard generation == loadGeneration else { return }

        if let viewerID, isLocalDevelopment(viewerID) {
            let traders = ExploreFixtures.traders(excluding: viewerID)
            ExploreFixtures.seedDetailCache(detailCache, viewer: viewerID)
            store.applyBootstrap(
                traders: traders,
                rooms: store.popularRooms,
                following: store.viewerFollowingIDs,
                tradersNextCursor: nil
            )
            phase = .loaded
            logHydration(source: source, rows: traders.count, requests: 0, confirmedAbsent: store.avatarConfirmedAbsentIDs)
            return
        }

        var requestCount = 0
        guard let page = await fetchProfilesPage(cursor: nil, generation: generation) else {
            guard generation == loadGeneration else { return }
            if traders.isEmpty {
                phase = .failed(store.tradersFailedMessage ?? "Couldn't load suggested traders")
            } else {
                phase = .loaded
            }
            return
        }
        requestCount += 1
        guard generation == loadGeneration else { return }

        let ranked = rankProfiles(page.items, limit: replacing ? 48 : 24, minScore: replacing ? 1 : 3)
        let apiProfiles = Dictionary(uniqueKeysWithValues: page.items.map { ($0.id, $0) })
        var confirmedAbsent = store.avatarConfirmedAbsentIDs
        let (hydrated, metrics) = await ExploreProfileHydration.hydrateTraders(
            ranked,
            authoritativeProfiles: apiProfiles,
            detailCache: detailCache,
            repository: profiles,
            confirmedAbsent: &confirmedAbsent,
            forceNetwork: source == .refresh
        )
        requestCount += metrics.batchRequestCount
        guard generation == loadGeneration else { return }

        store.updateAvatarConfirmedAbsent(confirmedAbsent)
        let presentation = preservingPresentation(hydrated)
        for trader in presentation { detailCache.seed(trader.profile) }

        let following = store.viewerFollowingIDs
        store.applyBootstrap(
            traders: presentation,
            rooms: store.popularRooms,
            following: following,
            tradersNextCursor: page.nextCursor,
            clearFailures: true
        )
        phase = .loaded
        logHydration(
            source: source,
            rows: presentation.count,
            requests: requestCount,
            confirmedAbsent: confirmedAbsent
        )
    }

    private func loadMoreTraders(generation: Int) async {
        guard generation == loadGeneration else { return }
        guard let cursor = store.tradersNextCursor else { return }

        var requestCount = 0
        guard let page = await fetchProfilesPage(cursor: cursor, generation: generation) else {
            guard generation == loadGeneration else { return }
            loadMoreFailedMessage = "Couldn't load more traders"
            return
        }
        requestCount += 1
        guard generation == loadGeneration else { return }

        var exclude = store.viewerFollowingIDs
        if let viewerID { exclude.insert(viewerID) }
        exclude.formUnion(store.suggestedTraders.map(\.id))
        FeedBlockedAuthorsFilter.shared.unionBlockedPeers(into: &exclude)

        let ranked = ExploreTraderRanking.rank(
            profiles: page.items,
            excluding: exclude,
            limit: page.items.count,
            minScore: 2
        )
        var confirmedAbsent = store.avatarConfirmedAbsentIDs
        let apiProfiles = Dictionary(uniqueKeysWithValues: page.items.map { ($0.id, $0) })
        let (hydrated, metrics) = await ExploreProfileHydration.hydrateTraders(
            ranked,
            authoritativeProfiles: apiProfiles,
            detailCache: detailCache,
            repository: profiles,
            confirmedAbsent: &confirmedAbsent
        )
        requestCount += metrics.batchRequestCount
        guard generation == loadGeneration else { return }

        store.updateAvatarConfirmedAbsent(confirmedAbsent)
        for trader in hydrated { detailCache.seed(trader.profile) }
        store.appendTraders(hydrated, nextCursor: page.nextCursor)
        logHydration(
            source: .pagination,
            rows: hydrated.count,
            requests: requestCount,
            confirmedAbsent: confirmedAbsent
        )
    }

    /// Batch-hydrate avatars for rows already seeded from Explore preview — no discoverable refetch.
    private func hydrateVisibleTraders(
        source: SuggestedTradersHydrationDiagnostics.Source,
        authoritativeProfiles: [ProfileID: Profile],
        forceNetwork: Bool,
        generation: Int
    ) async {
        guard generation == loadGeneration else { return }
        guard !store.suggestedTraders.isEmpty else { return }

        var confirmedAbsent = store.avatarConfirmedAbsentIDs
        let (hydrated, metrics) = await ExploreProfileHydration.hydrateTraders(
            store.suggestedTraders,
            authoritativeProfiles: authoritativeProfiles,
            detailCache: detailCache,
            repository: profiles,
            confirmedAbsent: &confirmedAbsent,
            forceNetwork: forceNetwork
        )
        guard generation == loadGeneration else { return }

        store.updateAvatarConfirmedAbsent(confirmedAbsent)
        let presentation = preservingPresentation(hydrated)
        for trader in presentation { detailCache.seed(trader.profile) }
        store.replaceTraders(presentation)
        logHydration(
            source: source,
            rows: presentation.count,
            requests: metrics.batchRequestCount,
            confirmedAbsent: confirmedAbsent
        )
    }

    private func rankProfiles(_ profiles: [Profile], limit: Int, minScore: Int) -> [ExploreTraderSuggestion] {
        var exclude = Set<ProfileID>()
        if let viewerID { exclude.insert(viewerID) }
        if let cachedFollowing = detailCache.viewerFollowingIDs() {
            exclude.formUnion(cachedFollowing)
        } else {
            exclude.formUnion(store.viewerFollowingIDs)
        }
        FeedBlockedAuthorsFilter.shared.unionBlockedPeers(into: &exclude)
        return ExploreTraderRanking.rank(
            profiles: profiles,
            excluding: exclude,
            limit: limit,
            minScore: minScore
        )
    }

    private func preservingPresentation(_ fresh: [ExploreTraderSuggestion]) -> [ExploreTraderSuggestion] {
        let prior = Dictionary(uniqueKeysWithValues: store.suggestedTraders.map { ($0.id, $0) })
        return fresh.map { trader in
            guard let old = prior[trader.id] else { return trader }
            var copy = trader
            copy.followerCount = old.followerCount
            copy.score = old.score
            copy.identityLine = copy.identityLine ?? old.identityLine
            copy.profile = old.profile.mergingCachedPresentation(with: copy.profile)
            return copy
        }
    }

    private func performSearch(query: String, generation: UInt64) async {
        do {
            let page = try await search.search(
                query: query,
                kinds: [.profile],
                page: PageRequest(limit: 24),
                excludingProfileID: viewerID
            )
            guard !Task.isCancelled, generation == searchGeneration else { return }

            let profileIDs = page.items.compactMap { item -> ProfileID? in
                guard item.kind == .profile, let id = item.profileID, id != viewerID else { return nil }
                return id
            }
            var confirmedAbsent = store.avatarConfirmedAbsentIDs
            let fetchedProfiles = (try? await SessionProfileStore.shared.profiles(
                ids: profileIDs,
                detailCache: detailCache,
                repository: profiles,
                acceptCached: { ExploreProfileHydration.isAvatarResolved($0, confirmedAbsent: confirmedAbsent) }
            )) ?? []
            let authoritative = Dictionary(uniqueKeysWithValues: fetchedProfiles.map { ($0.id, $0) })
            for profile in fetchedProfiles {
                if profile.avatar == nil {
                    confirmedAbsent.insert(profile.id)
                } else {
                    confirmedAbsent.remove(profile.id)
                }
            }
            store.updateAvatarConfirmedAbsent(confirmedAbsent)

            var people: [ExploreTraderSuggestion] = []
            for result in page.items where result.kind == .profile {
                guard let id = result.profileID, id != viewerID else { continue }
                let profile = authoritative[id]
                    ?? detailCache.profile(id: id)?.mergingCachedPresentation(with: Profile(
                        id: id,
                        userID: UserID(id.rawValue),
                        username: result.title,
                        displayName: result.subtitle ?? result.title,
                        bio: nil,
                        avatar: nil,
                        traderType: nil,
                        tradingStyle: nil,
                        primaryMarket: nil,
                        startedTradingAt: nil,
                        isPrivate: false,
                        isCreator: false,
                        createdAt: .now
                    ))
                    ?? Profile(
                        id: id,
                        userID: UserID(id.rawValue),
                        username: result.title,
                        displayName: result.subtitle ?? result.title,
                        bio: nil,
                        avatar: nil,
                        traderType: nil,
                        tradingStyle: nil,
                        primaryMarket: nil,
                        startedTradingAt: nil,
                        isPrivate: false,
                        isCreator: false,
                        createdAt: .now
                    )
                people.append(
                    ExploreTraderSuggestion(
                        profile: profile,
                        followerCount: 0,
                        score: 0,
                        identityLine: ExploreTraderRanking.identityLine(for: profile)
                    )
                )
            }
            var searchConfirmedAbsent = store.avatarConfirmedAbsentIDs
            let (hydratedPeople, _) = await ExploreProfileHydration.hydrateTraders(
                people,
                authoritativeProfiles: authoritative,
                detailCache: detailCache,
                repository: profiles,
                confirmedAbsent: &searchConfirmedAbsent
            )
            store.updateAvatarConfirmedAbsent(searchConfirmedAbsent)
            guard !Task.isCancelled, generation == searchGeneration else { return }
            searchResults = FeedBlockedAuthorsFilter.shared.filterTraderSuggestions(
                ExploreTraderRanking.orderingSearchResults(hydratedPeople, query: query) {
                    resolvedProfile(for: $0)
                }
            )
            searchPhase = .idle
        } catch {
            guard !Task.isCancelled, generation == searchGeneration else { return }
            searchPhase = .failed(UserFacingError.message(for: error))
        }
    }

    private func applyBlockedPeersToVisibleResults() {
        let filteredTraders = FeedBlockedAuthorsFilter.shared.filterTraderSuggestions(store.suggestedTraders)
        if filteredTraders.count != store.suggestedTraders.count {
            store.replaceTraders(filteredTraders)
        }
        let filteredSearch = FeedBlockedAuthorsFilter.shared.filterTraderSuggestions(searchResults)
        if filteredSearch.count != searchResults.count {
            searchResults = filteredSearch
        }
    }

    private func performFollowChange(_ trader: ExploreTraderSuggestion, currentlyFollowing: Bool) {
        guard let viewerID else { return }
        ExperienceHaptics.play(.selection)
        inFlightFollow.insert(trader.id)
        let next = !currentlyFollowing
        FollowMutationCoordinator.shared.applyEdgeChange(
            viewer: viewerID,
            target: trader.id,
            isFollowing: next
        )

        Task {
            defer { inFlightFollow.remove(trader.id) }
            do {
                if currentlyFollowing {
                    try await profiles.unfollow(from: viewerID, to: trader.id)
                } else {
                    try await profiles.follow(from: viewerID, to: trader.id)
                }
            } catch {
                FollowMutationCoordinator.shared.applyEdgeChange(
                    viewer: viewerID,
                    target: trader.id,
                    isFollowing: currentlyFollowing
                )
            }
        }
    }

    private func fetchProfilesPage(cursor: String?, generation: Int) async -> CursorPage<Profile>? {
        guard generation == loadGeneration else { return nil }
        do {
            return try await explore.discoverableProfiles(
                page: PageRequest(cursor: cursor, limit: 24)
            )
        } catch {
            return nil
        }
    }

    private func logHydration(
        source: SuggestedTradersHydrationDiagnostics.Source,
        rows: Int,
        requests: Int,
        confirmedAbsent: Set<ProfileID>
    ) {
        let visible = traders
        let resolved = visible.filter {
            ExploreProfileHydration.isAvatarResolved(
                resolvedProfile(for: $0),
                confirmedAbsent: confirmedAbsent
            )
        }.count
        let avatars = visible.filter { resolvedProfile(for: $0).avatar != nil }.count
        let unknown = visible.count - resolved
        SuggestedTradersHydrationDiagnostics.log(
            source: source,
            rows: rows,
            profilesResolved: resolved,
            avatarsAvailable: avatars,
            avatarsUnknown: unknown,
            requests: requests
        )
    }

    private func isLocalDevelopment(_ id: ProfileID) -> Bool {
        id.rawValue.hasPrefix("dev.")
    }
}
