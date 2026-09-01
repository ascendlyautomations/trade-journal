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

    private(set) var phase: Phase = .idle
    private(set) var isLoadingMore = false
    private(set) var loadMoreFailedMessage: String?

    private let explore: any ExploreRepository
    private let profiles: any ProfileRepository
    private let session: any SessionProviding
    private let detailCache: DetailPresentationCache
    private let navigationCoordinator: NavigationCoordinator
    private let store: ExploreSessionStore

    private var viewerID: ProfileID?
    private var loadTask: Task<Void, Never>?
    private var loadMoreTask: Task<Void, Never>?
    private var loadGeneration = 0
    private var inFlightFollow: Set<ProfileID> = []

    var pendingUnfollow: ExploreTraderSuggestion?

    init(
        explore: any ExploreRepository,
        profiles: any ProfileRepository,
        session: any SessionProviding,
        detailCache: DetailPresentationCache,
        navigationCoordinator: NavigationCoordinator,
        store: ExploreSessionStore? = nil
    ) {
        self.explore = explore
        self.profiles = profiles
        self.session = session
        self.detailCache = detailCache
        self.navigationCoordinator = navigationCoordinator
        self.store = store ?? .shared
    }

    var traders: [ExploreTraderSuggestion] {
        guard let viewerID else { return store.suggestedTraders }
        return store.suggestedTraders.filter { $0.id != viewerID }
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

        let hadTraders = !traders.isEmpty
        if !hadTraders {
            phase = .loading
        }

        await loadFirstPage(source: .refresh, replacing: true, generation: generation)
    }

    func loadMoreIfNeeded() {
        guard canLoadMore, !isLoadingMore, loadMoreTask == nil else { return }
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
        store.viewerFollowingIDs.contains(trader.id)
    }

    func toggleFollow(_ trader: ExploreTraderSuggestion) {
        guard let viewerID, viewerID != trader.id else { return }
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
