import Foundation
import Observation

@Observable
@MainActor
final class ExploreViewModel {
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
    private(set) var searchPeople: [ExploreTraderSuggestion] = []
    private(set) var searchRooms: [ExploreRoomSuggestion] = []
    private(set) var isLoadingMoreTraders = false
    var searchText = ""

    private let explore: any ExploreRepository
    private let search: any SearchRepository
    private let profiles: any ProfileRepository
    private let session: any SessionProviding
    private let detailCache: DetailPresentationCache
    private let navigationCoordinator: NavigationCoordinator
    private let store: ExploreSessionStore
    private let rpc: (any RPCClient)?

    private var viewerID: ProfileID?
    private var bootstrapTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var enrichTask: Task<Void, Never>?
    private var hydrateTask: Task<Void, Never>?
    private var inFlightFollow: Set<ProfileID> = []

    #if DEBUG
    private(set) var lastProbe: ExploreLoadProbe.Snapshot?
    #endif

    init(
        explore: any ExploreRepository,
        search: any SearchRepository,
        profiles: any ProfileRepository,
        session: any SessionProviding,
        detailCache: DetailPresentationCache,
        navigationCoordinator: NavigationCoordinator,
        store: ExploreSessionStore? = nil,
        rpc: (any RPCClient)? = nil
    ) {
        self.explore = explore
        self.search = search
        self.profiles = profiles
        self.session = session
        self.detailCache = detailCache
        self.navigationCoordinator = navigationCoordinator
        self.store = store ?? .shared
        self.rpc = rpc
    }

    var suggestedTraders: [ExploreTraderSuggestion] { store.suggestedTraders }
    var popularRooms: [ExploreRoomSuggestion] { store.popularRooms }
    var viewerFollowingIDs: Set<ProfileID> { store.viewerFollowingIDs }
    var tradersFailedMessage: String? { store.tradersFailedMessage }
    var roomsFailedMessage: String? { store.roomsFailedMessage }
    var canLoadMoreTraders: Bool { store.tradersNextCursor != nil }

    var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var showsSearchEmpty: Bool {
        isSearching
            && searchPhase == .idle
            && searchPeople.isEmpty
            && searchRooms.isEmpty
    }

    var showsDiscoveryEmpty: Bool {
        phase == .loaded
            && !isSearching
            && suggestedTraders.isEmpty
            && popularRooms.isEmpty
    }

    func loadIfNeeded() {
        if store.hasBootstrapped {
            phase = .loaded
            hydrateTask?.cancel()
            hydrateTask = Task { await rehydrateStoredTradersIfNeeded() }
            return
        }
        guard bootstrapTask == nil else { return }
        bootstrapTask = Task { await bootstrap() }
    }

    func resolvedProfile(for trader: ExploreTraderSuggestion) -> Profile {
        var merged = trader.profile
        if let cached = detailCache.profile(id: trader.id) {
            merged = merged.mergingCachedPresentation(with: cached)
        }
        return merged
    }

    func refresh() async {
        bootstrapTask?.cancel()
        store.invalidate()
        phase = .loading
        await bootstrap()
    }

    func searchChanged() {
        searchTask?.cancel()
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            searchPeople = []
            searchRooms = []
            searchPhase = .idle
            return
        }

        #if DEBUG
        let forceFixtures = ProcessInfo.processInfo.arguments.contains("-uitesting-explore-search")
            || ProcessInfo.processInfo.arguments.contains("-uitesting-explore-home")
        #else
        let forceFixtures = false
        #endif

        if forceFixtures || (viewerID.map(isLocalDevelopment) ?? false) {
            let lowered = query.lowercased()
            let exclude = viewerID ?? ExploreFixtures.viewerID
            searchPeople = ExploreFixtures.traders(excluding: exclude).filter {
                $0.profile.displayName.lowercased().contains(lowered)
                    || $0.profile.username.lowercased().contains(lowered)
            }
            searchRooms = ExploreFixtures.rooms().filter {
                $0.name.lowercased().contains(lowered) || $0.slug.lowercased().contains(lowered)
            }
            // Broaden screenshot/demo search so "alex" hits people while rooms stay discoverable.
            if searchRooms.isEmpty, forceFixtures {
                searchRooms = ExploreFixtures.rooms()
            }
            searchPhase = .idle
            return
        }

        searchPhase = .searching
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await performSearch(query: query)
        }
    }

    func loadMoreTradersIfNeeded() {
        guard canLoadMoreTraders, !isLoadingMoreTraders, !isSearching else { return }
        isLoadingMoreTraders = true
        Task {
            defer { isLoadingMoreTraders = false }
            await loadMoreTraders()
        }
    }

    func isFollowing(_ trader: ExploreTraderSuggestion) -> Bool {
        viewerFollowingIDs.contains(trader.id)
    }

    var pendingUnfollow: ExploreTraderSuggestion?

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
        patchSearchPersonFollowerCount(trader.id, delta: next ? 1 : -1)

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
                patchSearchPersonFollowerCount(trader.id, delta: currentlyFollowing ? 1 : -1)
            }
        }
    }

    private func patchSearchPersonFollowerCount(_ id: ProfileID, delta: Int) {
        guard let index = searchPeople.firstIndex(where: { $0.id == id }) else { return }
        var person = searchPeople[index]
        person.followerCount = max(0, person.followerCount + delta)
        searchPeople[index] = person
    }

    func openTrader(_ trader: ExploreTraderSuggestion) {
        ExperienceHaptics.play(.selection)
        detailCache.seed(trader.profile)
        if trader.id == viewerID {
            navigationCoordinator.open(.tab(.profile))
            navigationCoordinator.open(.popToRoot(.profile))
            return
        }
        navigationCoordinator.open(.feed(.profile(trader.id)))
    }

    func openRoom(_ room: ExploreRoomSuggestion) {
        ExperienceHaptics.play(.selection)
        navigationCoordinator.open(.feed(.room(room.id)))
    }

    func openLeaderboards() {
        ExperienceHaptics.play(.selection)
        navigationCoordinator.open(.feed(.leaderboard))
    }

    func openSuggestedTraders() {
        ExperienceHaptics.play(.selection)
        navigationCoordinator.open(.feed(.suggestedTraders))
    }

    // MARK: - Private

    private func bootstrap() async {
        #if DEBUG
        ExploreLoadProbe.beginBootstrap()
        #endif
        phase = store.hasBootstrapped ? .loaded : .loading

        if let raw = await session.currentUserID?.rawValue {
            viewerID = ProfileID(raw)
        }

        if let viewerID, isLocalDevelopment(viewerID) {
            let traders = ExploreFixtures.traders(excluding: viewerID)
            let rooms = ExploreFixtures.rooms()
            ExploreFixtures.seedDetailCache(detailCache, viewer: viewerID)
            store.applyBootstrap(
                traders: traders,
                rooms: rooms,
                following: [],
                tradersNextCursor: nil
            )
            phase = .loaded
            #if DEBUG
            ExploreLoadProbe.noteRequest("fixtures", blocking: true)
            lastProbe = ExploreLoadProbe.firstUsefulRender(sections: ["suggestedTraders", "popularRooms"])
            #endif
            bootstrapTask = nil
            return
        }

        if let viewerID, let rpc,
           let applied = try? await ExploreBootstrapLoader.load(
               viewerID: viewerID,
               rpc: rpc,
               detailCache: detailCache
           )
        {
            #if DEBUG
            ExploreLoadProbe.noteRequest("rpc_v1_explore_bootstrap", blocking: true)
            #endif
            var confirmedAbsent = store.avatarConfirmedAbsentIDs
            let (hydrated, _) = await ExploreProfileHydration.hydrateTraders(
                applied.traders,
                authoritativeProfiles: [:],
                detailCache: detailCache,
                repository: profiles,
                confirmedAbsent: &confirmedAbsent
            )
            store.updateAvatarConfirmedAbsent(confirmedAbsent)
            for trader in hydrated { detailCache.seed(trader.profile) }
            store.applyBootstrap(
                traders: hydrated,
                rooms: applied.rooms,
                following: applied.followingIDs,
                tradersNextCursor: applied.tradersNextCursor
            )
            phase = .loaded
            #if DEBUG
            lastProbe = ExploreLoadProbe.firstUsefulRender(
                sections: [
                    applied.traders.isEmpty ? nil : "suggestedTraders",
                    applied.rooms.isEmpty ? nil : "popularRooms",
                ].compactMap { $0 }
            )
            #endif
            bootstrapTask = nil
            return
        }

        // First useful paint: 2 parallel discovery calls. Following IDs hydrate after.
        async let profilesPage = fetchProfilesPage(cursor: nil)
        async let roomsResult = fetchRooms()

        let page = await profilesPage
        let rooms = await roomsResult

        #if DEBUG
        ExploreLoadProbe.noteRequest("discoverableProfiles")
        ExploreLoadProbe.noteRequest("popularRooms")
        #endif

        var exclude = Set<ProfileID>()
        if let viewerID { exclude.insert(viewerID) }
        if let cachedFollowing = detailCache.viewerFollowingIDs() {
            exclude.formUnion(cachedFollowing)
        }

        let apiProfiles = Dictionary(uniqueKeysWithValues: (page?.items ?? []).map { ($0.id, $0) })
        let ranked = ExploreTraderRanking.rank(
            profiles: page?.items ?? [],
            excluding: exclude,
            limit: 16,
            minScore: 3
        )
        var confirmedAbsent = store.avatarConfirmedAbsentIDs
        let (hydrated, _) = await ExploreProfileHydration.hydrateTraders(
            ranked,
            authoritativeProfiles: apiProfiles,
            detailCache: detailCache,
            repository: profiles,
            confirmedAbsent: &confirmedAbsent
        )
        store.updateAvatarConfirmedAbsent(confirmedAbsent)
        for trader in hydrated { detailCache.seed(trader.profile) }

        if page == nil && rooms == nil {
            phase = .failed("Couldn't load Explore")
            bootstrapTask = nil
            return
        }

        store.applyBootstrap(
            traders: hydrated,
            rooms: rooms ?? [],
            following: detailCache.viewerFollowingIDs() ?? [],
            tradersNextCursor: page?.nextCursor
        )
        if page == nil {
            store.setTradersFailed("Couldn't load suggested traders")
        }
        if rooms == nil {
            store.setRoomsFailed("Couldn't load Trade Rooms")
        }

        phase = .loaded
        #if DEBUG
        lastProbe = ExploreLoadProbe.firstUsefulRender(
            sections: [
                hydrated.isEmpty ? nil : "suggestedTraders",
                (rooms?.isEmpty == false) ? "popularRooms" : nil,
            ].compactMap { $0 }
        )
        #endif

        enrichTask?.cancel()
        enrichTask = Task {
            await hydrateFollowingAndFilter()
            await enrichTradersWithActivity()
        }
        bootstrapTask = nil
    }

    private func hydrateFollowingAndFilter() async {
        let following = await loadFollowingIDs()
        guard !Task.isCancelled else { return }
        store.updateFollowing(following)
    }

    private func enrichTradersWithActivity() async {
        guard !Task.isCancelled else { return }
        #if DEBUG
        ExploreLoadProbe.noteRequest("tradeActivitySummaries", blocking: false)
        ExploreLoadProbe.noteRequest("socialCounts", blocking: false)
        #endif
        let summaries = (try? await explore.tradeActivitySummaries(limit: 1500)) ?? [:]
        let ids = store.suggestedTraders.map(\.id)
        let counts = (try? await explore.socialCounts(for: ids)) ?? .empty
        guard !Task.isCancelled, !store.suggestedTraders.isEmpty else { return }

        let traderProfiles = store.suggestedTraders.map(\.profile)
        var exclude = store.viewerFollowingIDs
        if let viewerID { exclude.insert(viewerID) }
        let reranked = ExploreTraderRanking.rank(
            profiles: traderProfiles,
            tradeSummaries: summaries,
            followerCounts: counts.followers,
            excluding: exclude,
            limit: max(16, store.suggestedTraders.count),
            minScore: 1
        )
        var confirmedAbsent = store.avatarConfirmedAbsentIDs
        let (hydrated, _) = await ExploreProfileHydration.hydrateTraders(
            reranked,
            authoritativeProfiles: [:],
            detailCache: detailCache,
            repository: profiles,
            confirmedAbsent: &confirmedAbsent
        )
        store.updateAvatarConfirmedAbsent(confirmedAbsent)
        store.applyBootstrap(
            traders: hydrated,
            rooms: store.popularRooms,
            following: store.viewerFollowingIDs,
            tradersNextCursor: store.tradersNextCursor,
            clearFailures: false
        )
    }

    private func loadMoreTraders() async {
        guard let cursor = store.tradersNextCursor else { return }

        if let viewerID, let rpc,
           let offset = Int(cursor),
           let applied = try? await ExploreBootstrapLoader.load(
               viewerID: viewerID,
               rpc: rpc,
               detailCache: detailCache,
               traderOffset: offset
           )
        {
            var confirmedAbsent = store.avatarConfirmedAbsentIDs
            let (hydrated, _) = await ExploreProfileHydration.hydrateTraders(
                applied.traders,
                authoritativeProfiles: [:],
                detailCache: detailCache,
                repository: profiles,
                confirmedAbsent: &confirmedAbsent
            )
            store.updateAvatarConfirmedAbsent(confirmedAbsent)
            for trader in hydrated { detailCache.seed(trader.profile) }
            store.appendTraders(hydrated, nextCursor: applied.tradersNextCursor)
            return
        }

        guard let page = await fetchProfilesPage(cursor: cursor) else { return }
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
        let (hydrated, _) = await ExploreProfileHydration.hydrateTraders(
            ranked,
            authoritativeProfiles: apiProfiles,
            detailCache: detailCache,
            repository: profiles,
            confirmedAbsent: &confirmedAbsent
        )
        store.updateAvatarConfirmedAbsent(confirmedAbsent)
        for trader in hydrated { detailCache.seed(trader.profile) }
        store.appendTraders(hydrated, nextCursor: page.nextCursor)
    }

    private func rehydrateStoredTradersIfNeeded() async {
        guard !store.suggestedTraders.isEmpty else { return }
        var confirmedAbsent = store.avatarConfirmedAbsentIDs
        let (hydrated, _) = await ExploreProfileHydration.hydrateTraders(
            store.suggestedTraders,
            authoritativeProfiles: [:],
            detailCache: detailCache,
            repository: profiles,
            confirmedAbsent: &confirmedAbsent
        )
        guard !Task.isCancelled else { return }
        store.updateAvatarConfirmedAbsent(confirmedAbsent)
        store.replaceTraders(hydrated)
        hydrateTask = nil
    }

    private func performSearch(query: String) async {
        do {
            async let peoplePage = search.search(
                query: query,
                kinds: [.profile],
                page: PageRequest(limit: 12),
                excludingProfileID: viewerID
            )
            async let rooms = explore.searchRooms(query: query, limit: 12)
            let page = try await peoplePage
            let roomHits = (try? await rooms) ?? []
            guard !Task.isCancelled else { return }

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
            searchPeople = hydratedPeople
            searchRooms = roomHits
            searchPhase = .idle
        } catch {
            guard !Task.isCancelled else { return }
            searchPhase = .failed(UserFacingError.message(for: error))
        }
    }

    private func fetchProfilesPage(cursor: String?) async -> CursorPage<Profile>? {
        do {
            return try await explore.discoverableProfiles(
                page: PageRequest(cursor: cursor, limit: 24)
            )
        } catch {
            return nil
        }
    }

    private func fetchRooms() async -> [ExploreRoomSuggestion]? {
        do {
            return try await explore.popularRooms(limit: 12)
        } catch {
            return nil
        }
    }

    private func loadFollowingIDs() async -> Set<ProfileID> {
        if let cached = detailCache.viewerFollowingIDs() {
            return cached
        }
        guard let viewerID else { return [] }
        // Prefer shared following set (Feed/Stories warm this) — zero extra SELECTs.
        if let shared = await SessionFollowingStore.shared.cached(viewerID: viewerID.rawValue) {
            let ids = Set(shared.map { ProfileID($0) })
            detailCache.seedViewerFollowingIDs(ids)
            return ids
        }
        if let disk = SessionDiskCache.loadFollowing(for: viewerID) {
            let ids = Set(disk.map { ProfileID($0) })
            await SessionFollowingStore.shared.seed(viewerID: viewerID.rawValue, ids: Set(disk))
            detailCache.seedViewerFollowingIDs(ids)
            return ids
        }
        do {
            let page = try await profiles.following(of: viewerID, page: PageRequest(limit: 200))
            let ids = Set(page.items.map(\.id))
            await SessionFollowingStore.shared.seed(
                viewerID: viewerID.rawValue,
                ids: Set(ids.map(\.rawValue))
            )
            detailCache.seedViewerFollowingIDs(ids)
            SessionDiskCache.saveFollowing(ids: ids.map(\.rawValue), for: viewerID)
            return ids
        } catch {
            return []
        }
    }

    private func isLocalDevelopment(_ id: ProfileID) -> Bool {
        id.rawValue.hasPrefix("dev.")
    }
}
