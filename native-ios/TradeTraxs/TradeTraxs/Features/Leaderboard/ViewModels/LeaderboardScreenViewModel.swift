import Foundation
import Observation

/// Canonical Leaderboards screen owner — one bootstrap, one ``LeaderboardState``.
@Observable
@MainActor
final class LeaderboardScreenViewModel: ScreenLifecycle {
    typealias State = LeaderboardState

    private(set) var state = LeaderboardState()

    private let leaderboard: any LeaderboardRepository
    private let profiles: any ProfileRepository
    private let explore: any ExploreRepository
    private let session: any SessionProviding
    private let detailCache: DetailPresentationCache
    private let navigationCoordinator: NavigationCoordinator
    private let store: LeaderboardSessionStore

    private var bootstrapTask: Task<Void, Never>?
    private var filterGeneration: UInt64 = 0
    private var inFlightFollow: Set<ProfileID> = []

    init(
        leaderboard: any LeaderboardRepository,
        profiles: any ProfileRepository,
        explore: any ExploreRepository,
        session: any SessionProviding,
        detailCache: DetailPresentationCache,
        navigationCoordinator: NavigationCoordinator,
        store: LeaderboardSessionStore? = nil
    ) {
        self.leaderboard = leaderboard
        self.profiles = profiles
        self.explore = explore
        self.session = session
        self.detailCache = detailCache
        self.navigationCoordinator = navigationCoordinator
        self.store = store ?? .shared
    }

    // MARK: - Facades

    var phase: LeaderboardState.Phase { state.phase }
    var rows: [LeaderboardRow] { state.rows }
    var podium: [LeaderboardRow] { state.podium }
    var listRows: [LeaderboardRow] { state.listRows }
    var pinnedViewer: LeaderboardRow? { state.pinnedViewer }
    var isRefreshing: Bool { state.isRefreshing }
    var isLoadingMore: Bool { state.isLoadingMore }
    var showsEmpty: Bool { state.showsEmpty }
    var audience: LeaderboardAudience { state.audience }
    var timeframe: LeaderboardTimeframe { state.timeframe }
    var category: LeaderboardCategory { state.category }
    var timeframeFallbackMessage: String? { state.timeframeFallbackMessage }

    // MARK: - Lifecycle

    func bootstrapIfNeeded() async {
        if store.hasBootstrapped, !state.didBootstrap {
            state.audience = store.audience
            state.requestedTimeframe = store.timeframe
            state.timeframe = store.timeframe
            state.category = store.category
            applyStoreToState(didPlayPodiumEntrance: true)
            return
        }
        guard bootstrapTask == nil, !state.didBootstrap else { return }
        bootstrapTask = Task { await performBootstrap(forceNetwork: false, resetting: true) }
        await bootstrapTask?.value
    }

    func refresh() async {
        bootstrapTask?.cancel()
        state.isRefreshing = true
        await performBootstrap(forceNetwork: true, resetting: true)
        state.isRefreshing = false
    }

    func loadMore() async {
        guard state.hasMore, !state.isLoadingMore, state.phase == .loaded else { return }
        guard let cursor = state.nextCursor else { return }
        state.isLoadingMore = true
        defer { state.isLoadingMore = false }

        do {
            var context = makeContext(cursor: cursor, forceNetwork: false)
            context.cachedTrades = store.rawTrades
            context.timeframe = state.timeframe
            let result = try await LeaderboardBootstrap.loadPage(context)
            store.appendEntries(
                result.entries,
                profiles: result.profiles,
                verified: result.verified,
                followers: result.followers,
                nextCursor: result.nextCursor
            )
            applyStoreToState(didPlayPodiumEntrance: state.didPlayPodiumEntrance)
        } catch {
            // Keep existing rows; pagination errors are non-fatal.
        }
    }

    func loadMoreIfNeeded(currentID: ProfileID) async {
        guard state.listRows.last?.profileID == currentID else { return }
        await loadMore()
    }

    func subscribeRealtime() {}
    func unsubscribeRealtime() {}

    // MARK: - Filters

    func setAudience(_ next: LeaderboardAudience) {
        guard state.audience != next else { return }
        ExperienceHaptics.play(.selection)
        state.audience = next
        store.updateFilters(audience: next, timeframe: state.timeframe, category: state.category)
        applyResolvedPresentationFromCache()
    }

    func setTimeframe(_ next: LeaderboardTimeframe) {
        guard state.requestedTimeframe != next else { return }
        ExperienceHaptics.play(.selection)
        state.requestedTimeframe = next
        filterGeneration &+= 1
        let generation = filterGeneration
        store.updateFilters(
            audience: state.audience,
            timeframe: next,
            category: state.category
        )
        bootstrapTask?.cancel()
        bootstrapTask = Task { await refilterFromCachedTrades(generation: generation) }
    }

    func setCategory(_ next: LeaderboardCategory) {
        guard state.category != next else { return }
        ExperienceHaptics.play(.selection)
        state.category = next
        store.updateFilters(audience: state.audience, timeframe: state.timeframe, category: next)
        applyStoreToState(didPlayPodiumEntrance: true)
    }

    func markPodiumEntrancePlayed() {
        state.didPlayPodiumEntrance = true
    }

    func awaitPendingWork() async {
        await bootstrapTask?.value
    }

    // MARK: - Actions

    func openProfile(_ row: LeaderboardRow) {
        ExperienceHaptics.play(.selection)
        detailCache.seed(row.profile)
        if row.profileID == state.viewerID {
            navigationCoordinator.open(.tab(.profile))
            navigationCoordinator.open(.popToRoot(.profile))
            return
        }
        navigationCoordinator.open(.feed(.profile(row.profileID)))
    }

    func isFollowing(_ row: LeaderboardRow) -> Bool {
        state.followingIDs.contains(row.profileID)
    }

    func toggleFollow(_ row: LeaderboardRow) {
        guard let viewerID = state.viewerID, viewerID != row.profileID else { return }
        guard !inFlightFollow.contains(row.profileID) else { return }
        ExperienceHaptics.play(.selection)
        inFlightFollow.insert(row.profileID)
        let currentlyFollowing = isFollowing(row)
        FollowMutationCoordinator.shared.applyEdgeChange(
            viewer: viewerID,
            target: row.profileID,
            isFollowing: !currentlyFollowing
        )
        applyStoreToState(didPlayPodiumEntrance: true)

        Task {
            defer { inFlightFollow.remove(row.profileID) }
            do {
                if currentlyFollowing {
                    try await profiles.unfollow(from: viewerID, to: row.profileID)
                } else {
                    try await profiles.follow(from: viewerID, to: row.profileID)
                }
            } catch {
                FollowMutationCoordinator.shared.applyEdgeChange(
                    viewer: viewerID,
                    target: row.profileID,
                    isFollowing: currentlyFollowing
                )
                applyStoreToState(didPlayPodiumEntrance: true)
            }
        }
    }

    // MARK: - Private

    private func performBootstrap(forceNetwork: Bool, resetting: Bool) async {
        if resetting, !state.isRefreshing, !store.hasBootstrapped {
            state.phase = .loading
        } else if resetting, !state.isRefreshing {
            state.phase = state.rows.isEmpty ? .loading : .loaded
        }

        do {
            var context = makeContext(cursor: nil, forceNetwork: forceNetwork)
            context.timeframe = state.requestedTimeframe
            let result = try await LeaderboardBootstrap.loadPage(context)
            guard !Task.isCancelled else { return }

            let windowResolved = LeaderboardTimeframeFallback.resolveWindow(
                trades: result.trades,
                requested: state.requestedTimeframe
            )
            applyResolvedTimeframe(windowResolved.resolution)

            let presentationResult: LeaderboardBootstrap.Result
            if windowResolved.resolution.effective == state.requestedTimeframe {
                presentationResult = result
            } else {
                var hydratedContext = makeContext(cursor: nil, forceNetwork: false)
                hydratedContext.timeframe = state.timeframe
                hydratedContext.cachedTrades = result.trades
                presentationResult = try await LeaderboardBootstrap.loadPage(hydratedContext)
                guard !Task.isCancelled else { return }
            }

            store.applyBootstrap(
                trades: result.trades,
                entries: presentationResult.entries,
                profiles: presentationResult.profiles,
                verified: presentationResult.verified,
                followers: presentationResult.followers,
                following: presentationResult.following,
                friends: presentationResult.friends,
                viewerID: presentationResult.viewerID,
                nextCursor: presentationResult.nextCursor,
                audience: state.audience,
                timeframe: state.timeframe,
                category: state.category
            )
            applyStoreToState(didPlayPodiumEntrance: !resetting && state.didPlayPodiumEntrance)
        } catch {
            guard !Task.isCancelled else { return }
            if state.rows.isEmpty {
                state.phase = .failed(Self.userFacingMessage(for: error))
                state.didBootstrap = true
            }
        }
        bootstrapTask = nil
    }

    private func refilterFromCachedTrades(generation: UInt64) async {
        guard !store.rawTrades.isEmpty else {
            await performBootstrap(forceNetwork: false, resetting: true)
            return
        }

        if state.rows.isEmpty {
            state.phase = .loading
        }

        let resolved = LeaderboardTimeframeFallback.resolvePage(
            trades: store.rawTrades,
            requested: state.requestedTimeframe,
            audience: state.audience,
            category: state.category,
            profiles: store.profilesByID,
            verified: store.verifiedIDs,
            followers: store.followerCounts,
            following: store.followingIDs,
            friends: store.friendIDs,
            viewerID: store.viewerID
        )
        guard generation == filterGeneration, !Task.isCancelled else { return }

        applyResolvedTimeframe(resolved.resolution)
        store.replaceEntries(
            resolved.entries,
            nextCursor: resolved.nextCursor,
            timeframe: state.timeframe
        )
        applyStoreToState(didPlayPodiumEntrance: true)
        bootstrapTask = nil
    }

    private func applyResolvedPresentationFromCache() {
        guard !store.rawTrades.isEmpty else {
            applyStoreToState(didPlayPodiumEntrance: true)
            return
        }
        let resolved = LeaderboardTimeframeFallback.resolvePage(
            trades: store.rawTrades,
            requested: state.requestedTimeframe,
            audience: state.audience,
            category: state.category,
            profiles: store.profilesByID,
            verified: store.verifiedIDs,
            followers: store.followerCounts,
            following: store.followingIDs,
            friends: store.friendIDs,
            viewerID: store.viewerID
        )
        applyResolvedTimeframe(resolved.resolution)
        store.replaceEntries(
            resolved.entries,
            nextCursor: resolved.nextCursor,
            timeframe: state.timeframe
        )
        applyStoreToState(didPlayPodiumEntrance: true)
    }

    private func applyResolvedTimeframe(_ resolution: LeaderboardTimeframeFallback.Resolution) {
        state.timeframe = resolution.effective
        state.timeframeFallbackMessage = LeaderboardTimeframeFallback.fallbackMessage(
            requested: resolution.requested,
            effective: resolution.effective
        )
    }

    private func applyStoreToState(didPlayPodiumEntrance: Bool) {
        var next = LeaderboardPresentation.buildState(
            entries: store.rawEntries,
            profiles: store.profilesByID,
            verified: store.verifiedIDs,
            followers: store.followerCounts,
            following: store.followingIDs,
            friends: store.friendIDs,
            viewerID: store.viewerID,
            audience: state.audience,
            category: state.category,
            nextCursor: store.nextCursor,
            didPlayPodiumEntrance: didPlayPodiumEntrance
        )
        next.requestedTimeframe = state.requestedTimeframe
        next.timeframe = state.timeframe
        next.timeframeFallbackMessage = state.timeframeFallbackMessage
        next.isRefreshing = state.isRefreshing
        next.isLoadingMore = state.isLoadingMore
        state = next
    }

    private func makeContext(cursor: String?, forceNetwork: Bool) -> LeaderboardBootstrap.Context {
        LeaderboardBootstrap.Context(
            leaderboard: leaderboard,
            profiles: profiles,
            explore: explore,
            session: session,
            detailCache: detailCache,
            audience: state.audience,
            timeframe: state.timeframe,
            category: state.category,
            cursor: cursor,
            forceNetwork: forceNetwork
        )
    }

    private static func userFacingMessage(for error: Error) -> String {
        if let app = error as? AppError {
            return UserFacingError.map(app).message
        }
        if let network = error as? NetworkError {
            return UserFacingError.map(network).message
        }
        return "Couldn't load Leaderboards"
    }
}
