import Foundation
import Observation

@Observable
@MainActor
final class AchievementsContainerViewModel {
    private(set) var state: ProfileSectionLoadState = .idle
    private(set) var items: [Achievement] = []
    private(set) var nextCursor: String?

    private let profileID: ProfileID
    private let achievements: any AchievementRepository
    private let rpc: (any RPCClient)?
    private let navigationCoordinator: NavigationCoordinator
    private let detailCache: DetailPresentationCache
    private let engagementStore: EngagementStore?
    private let viewerIsOwner: Bool
    private var loadTask: Task<Void, Never>?
    private var loadMoreTask: Task<Void, Never>?
    private var hasLoaded = false
    private var isLoadingMore = false
    private var paginationGeneration = 0
    private var isScreenOwned = false
    private var awaitingScreenBootstrap = false
    private let initialLoadFailureGrace = ProfileSectionFailureGrace()

    var hasAuthoritativePayload: Bool { hasLoaded }

    var profileOwnerID: ProfileID { profileID }
    var isOwner: Bool { viewerIsOwner }

    init(
        profileID: ProfileID,
        achievements: any AchievementRepository,
        rpc: (any RPCClient)? = nil,
        navigationCoordinator: NavigationCoordinator,
        detailCache: DetailPresentationCache,
        engagementStore: EngagementStore? = nil,
        viewerIsOwner: Bool = true
    ) {
        self.profileID = profileID
        self.achievements = achievements
        self.rpc = rpc
        self.navigationCoordinator = navigationCoordinator
        self.detailCache = detailCache
        self.engagementStore = engagementStore
        self.viewerIsOwner = viewerIsOwner
    }

    func prefetchEngagement(for achievementIDs: [AchievementID]) {
        guard !achievementIDs.isEmpty else { return }
        engagementStore?.prefetch(achievementIDs.map { .achievement($0) })
    }

    func applyBootstrap(_ snapshot: ProfileState) {
        if snapshot.didBootstrap || snapshot.phase == .loaded {
            isScreenOwned = true
        }
        awaitingScreenBootstrap = ProfileSectionInitialLoad.awaitingScreenBootstrap(
            isScreenOwned: isScreenOwned,
            snapshot: snapshot,
            didLoadSection: snapshot.didLoadAchievements,
            sectionItemsEmpty: snapshot.achievements.isEmpty,
            localItemsEmpty: items.isEmpty
        )
        guard snapshot.didLoadAchievements || !snapshot.achievements.isEmpty else {
            if (snapshot.phase == .loading || snapshot.didBootstrap), items.isEmpty {
                state = .loading
            }
            return
        }

        awaitingScreenBootstrap = false
        initialLoadFailureGrace.cancel()
        let reconciled = ProfileSectionSupport.reconcileSectionItems(
            snapshotItems: snapshot.achievements,
            loadedItems: items,
            hasLoaded: hasLoaded,
            didLoadAuthoritative: snapshot.didLoadAchievements
        )
        items = reconciled.items
        hasLoaded = reconciled.hasLoaded
        detailCache.seed(achievements: items)
        state = items.isEmpty ? .empty : .loaded(itemCount: items.count)
        prefetchEngagement(for: items.map(\.id))
    }

    func loadIfNeeded() {
        guard !hasLoaded, loadTask == nil else { return }
        if awaitingScreenBootstrap {
            if items.isEmpty {
                state = .loading
            }
            return
        }
        loadTask = Task { await performLoad(reset: true) }
    }

    func refresh() async {
        loadTask?.cancel()
        cancelLoadMore(reason: "refresh")
        await performLoad(reset: true)
    }

    func loadMoreIfNeeded() async {
        guard hasLoaded, nextCursor != nil, loadMoreTask == nil, !isLoadingMore else { return }
        guard let lastID = items.last?.id else { return }
        await loadMoreIfNeeded(currentAchievementID: lastID)
    }

    func loadMoreIfNeeded(currentAchievementID: AchievementID?) async {
        guard hasLoaded, nextCursor != nil, loadMoreTask == nil, !isLoadingMore else { return }
        guard let currentAchievementID, items.last?.id == currentAchievementID else { return }
        let cursor = nextCursor
        let generation = paginationGeneration
        isLoadingMore = true
        loadMoreTask = Task { @MainActor in
            defer {
                isLoadingMore = false
                loadMoreTask = nil
            }
            await performLoadMore(cursor: cursor, generation: generation)
        }
    }

    func openAchievement(_ achievement: Achievement) {
        ExperienceHaptics.play(.selection)
        detailCache.seed(achievement)
        navigationCoordinator.open(.profile(.achievement(achievement.id)))
    }

    private func cancelLoadMore(reason: String) {
        paginationGeneration &+= 1
        loadMoreTask?.cancel()
        loadMoreTask = nil
        isLoadingMore = false
        _ = reason
    }

    private func performLoad(reset: Bool) async {
        if reset {
            cancelLoadMore(reason: "reset")
        }

        if ProfileSectionSupport.isLocalDevelopmentProfile(profileID) {
            hasLoaded = true
            items = ProfileAchievementFixtures.samples(owner: profileID)
            nextCursor = nil
            detailCache.seed(achievements: items)
            state = items.isEmpty ? .empty : .loaded(itemCount: items.count)
            prefetchEngagement(for: items.map(\.id))
            loadTask = nil
            return
        }

        state = items.isEmpty ? .loading : state
        initialLoadFailureGrace.cancel()
        do {
            let pageItems: [Achievement]
            let cursor: String?
            if BackendV2FeatureFlags.isEnabled(.profile), let rpc {
                let applied = try await ProfileTabBootstrapLoader.load(
                    tab: .achievements,
                    profileID: profileID,
                    rpc: rpc,
                    cursor: nil
                )
                pageItems = applied.achievements ?? []
                cursor = applied.nextCursor
            } else {
                let page = try await achievements.achievements(
                    for: profileID,
                    page: PageRequest(limit: ProfileTabBootstrapLoader.defaultPageSize),
                    publicOnly: !viewerIsOwner
                )
                pageItems = page.items
                cursor = page.nextCursor
            }
            guard !Task.isCancelled else { return }
            let overlay = OwnerProfileOptimisticStore.shared.achievements.filter {
                $0.ownerProfileID == profileID
            }
            items = OwnerProfileOptimisticStore.merging(overlay: overlay, into: pageItems)
            nextCursor = cursor
            detailCache.seed(achievements: items)
            hasLoaded = true
            initialLoadFailureGrace.cancel()
            state = items.isEmpty ? .empty : .loaded(itemCount: items.count)
            prefetchEngagement(for: items.map(\.id))
        } catch {
            guard !Task.isCancelled else { return }
            if items.isEmpty {
                if awaitingScreenBootstrap {
                    state = .loading
                } else {
                    let message = ProfileSectionSupport.message(for: error)
                    initialLoadFailureGrace.scheduleIfNeeded(message: message) { [weak self] in
                        guard let self else { return false }
                        return !hasLoaded && items.isEmpty && !awaitingScreenBootstrap
                    } present: { [weak self] message in
                        self?.state = .failed(message: message)
                    }
                }
            }
        }
        loadTask = nil
    }

    private func performLoadMore(cursor: String?, generation: Int) async {
        guard generation == paginationGeneration else { return }
        do {
            let pageItems: [Achievement]
            let newCursor: String?
            if BackendV2FeatureFlags.isEnabled(.profile), let rpc {
                let applied = try await ProfileTabBootstrapLoader.load(
                    tab: .achievements,
                    profileID: profileID,
                    rpc: rpc,
                    cursor: cursor
                )
                pageItems = applied.achievements ?? []
                newCursor = applied.nextCursor
            } else {
                let page = try await achievements.achievements(
                    for: profileID,
                    page: PageRequest(cursor: cursor, limit: ProfileTabBootstrapLoader.defaultPageSize),
                    publicOnly: !viewerIsOwner
                )
                pageItems = page.items
                newCursor = page.nextCursor
            }
            guard generation == paginationGeneration, !Task.isCancelled else { return }
            if pageItems.isEmpty {
                nextCursor = nil
                return
            }
            appendUnique(pageItems)
            nextCursor = newCursor
            state = items.isEmpty ? .empty : .loaded(itemCount: items.count)
            prefetchEngagement(for: pageItems.map(\.id))
        } catch {
            guard generation == paginationGeneration else { return }
        }
    }

    private func appendUnique(_ pageItems: [Achievement]) {
        let existing = Set(items.map(\.id))
        let fresh = pageItems.filter { !existing.contains($0.id) }
        guard !fresh.isEmpty else {
            nextCursor = nil
            return
        }
        items.append(contentsOf: fresh)
        detailCache.seed(achievements: items)
    }
}
