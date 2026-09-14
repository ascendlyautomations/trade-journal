import Foundation
import Observation

@Observable
@MainActor
final class PostsContainerViewModel {
    private(set) var state: ProfileSectionLoadState = .idle
    private(set) var items: [Post] = []

    let profileOwnerID: ProfileID
    private(set) var isOwner: Bool
    private let profiles: any ProfileRepository
    private let rpc: (any RPCClient)?
    private let navigationCoordinator: NavigationCoordinator
    private let detailCache: DetailPresentationCache
    private let engagementStore: EngagementStore?
    private var loadTask: Task<Void, Never>?
    private var loadMoreTask: Task<Void, Never>?
    private var nextCursor: String?
    private var isLoadingMore = false
    private var paginationGeneration = 0
    private var hasLoaded = false
    private var isScreenOwned = false
    private var syncGeneration: UInt64 = 0

    /// True after an authoritative section fetch or complete bootstrap snapshot.
    var hasAuthoritativePayload: Bool { hasLoaded }

    init(
        profileID: ProfileID,
        profiles: any ProfileRepository,
        rpc: (any RPCClient)? = nil,
        navigationCoordinator: NavigationCoordinator,
        detailCache: DetailPresentationCache,
        engagementStore: EngagementStore? = nil,
        isOwner: Bool = true
    ) {
        self.profileOwnerID = profileID
        self.isOwner = isOwner
        self.profiles = profiles
        self.rpc = rpc
        self.navigationCoordinator = navigationCoordinator
        self.detailCache = detailCache
        self.engagementStore = engagementStore
    }

    func prefetchEngagement(for postIDs: [PostID]) {
        guard !postIDs.isEmpty else { return }
        engagementStore?.prefetch(postIDs.map { .profilePost($0) })
    }

    func applyBootstrap(_ snapshot: ProfileState) {
        if snapshot.didBootstrap || snapshot.phase == .loaded {
            isScreenOwned = true
        }
        let beforeCount = items.count
        guard snapshot.didLoadPosts || !snapshot.posts.isEmpty else {
            if (snapshot.phase == .loading || snapshot.didBootstrap), items.isEmpty {
                state = .loading
            }
            return
        }

        if hasLoaded {
            guard !snapshot.posts.isEmpty else { return }
            items = OwnerProfileOptimisticStore.merging(overlay: snapshot.posts, into: items)
            #if DEBUG
            ProfilePostsSync.logReconciled(
                beforeCount: beforeCount,
                snapshotCount: snapshot.posts.count,
                afterCount: items.count
            )
            ProfilePostsSync.logUIVisibleCount(items.count)
            #endif
            detailCache.seed(posts: items)
            state = items.isEmpty ? .empty : .loaded(itemCount: items.count)
            prefetchEngagement(for: items.map(\.id))
            return
        }

        let reconciled = ProfileSectionSupport.reconcileSectionItems(
            snapshotItems: snapshot.posts,
            loadedItems: items,
            hasLoaded: hasLoaded,
            didLoadAuthoritative: snapshot.didLoadPosts
        )
        items = reconciled.items
        hasLoaded = reconciled.hasLoaded
        #if DEBUG
        ProfilePostsSync.logReconciled(
            beforeCount: beforeCount,
            snapshotCount: snapshot.posts.count,
            afterCount: items.count
        )
        ProfilePostsSync.logUIVisibleCount(items.count)
        #endif
        detailCache.seed(posts: items)
        state = items.isEmpty ? .empty : .loaded(itemCount: items.count)
        prefetchEngagement(for: items.map(\.id))
    }

    /// Owner publish — upsert immediately, then refresh page 1 using the same path as manual reload.
    func notePublishSucceeded(_ post: Post, preservingExisting existingItems: [Post] = []) {
        guard post.authorProfileID == profileOwnerID else { return }
        let visibleBefore = items.count
        let baseline = items.isEmpty ? existingItems : items
        items = OwnerProfileOptimisticStore.upserting(post, into: baseline)
        hasLoaded = true
        detailCache.seed(posts: items)
        state = items.isEmpty ? .empty : .loaded(itemCount: items.count)
        prefetchEngagement(for: items.map(\.id))

        syncGeneration &+= 1
        let generation = syncGeneration
        #if DEBUG
        ProfilePostsSync.logPublishSucceeded(
            id: post.id.rawValue,
            visibleBefore: visibleBefore,
            optimisticAfter: items.count
        )
        ProfilePostsSync.logAuthoritativeRefreshStarted(generation: generation)
        ProfilePostsSync.logUIVisibleCount(items.count)
        #endif

        loadTask?.cancel()
        loadTask = Task { await performLoad(generation: generation) }
    }

    func loadIfNeeded() {
        guard !hasLoaded, loadTask == nil else { return }
        syncGeneration &+= 1
        let generation = syncGeneration
        loadTask = Task { await performLoad(generation: generation) }
    }

    func refresh() async {
        syncGeneration &+= 1
        let generation = syncGeneration
        loadTask?.cancel()
        await performLoad(generation: generation)
    }

    func loadMoreIfNeeded(currentPostID: PostID?) async {
        guard hasLoaded, nextCursor != nil, loadMoreTask == nil, !isLoadingMore else { return }
        guard let currentPostID, items.last?.id == currentPostID else { return }
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

    func openPost(_ post: Post) {
        ExperienceHaptics.play(.selection)
        detailCache.seed(post)
        navigationCoordinator.open(.profile(.post(post.id)))
    }

    private func performLoad(generation: UInt64) async {
        if ProfileSectionSupport.isLocalDevelopmentProfile(profileOwnerID) {
            guard generation == syncGeneration else {
                #if DEBUG
                ProfilePostsSync.logStaleResponseDropped(
                    generation: generation,
                    currentGeneration: syncGeneration
                )
                #endif
                loadTask = nil
                return
            }
            hasLoaded = true
            let overlay = OwnerProfileOptimisticStore.shared.posts.filter {
                $0.authorProfileID == profileOwnerID
            }
            let serverMerged = OwnerProfileOptimisticStore.merging(
                overlay: overlay,
                into: ProfilePostFixtures.samples(owner: profileOwnerID)
            )
            items = OwnerProfileOptimisticStore.merging(overlay: serverMerged, into: items)
            detailCache.seed(posts: items)
            state = items.isEmpty ? .empty : .loaded(itemCount: items.count)
            prefetchEngagement(for: items.map(\.id))
            #if DEBUG
            ProfilePostsSync.logAuthoritativeReturned(generation: generation, count: items.count)
            ProfilePostsSync.logUIVisibleCount(items.count)
            #endif
            OwnerProfileOptimisticStore.shared.syncOwnerPostsState(items)
            loadTask = nil
            return
        }

        state = items.isEmpty ? .loading : state
        paginationGeneration &+= 1
        do {
            let pageItems: [Post]
            let cursor: String?
            if BackendV2FeatureFlags.isEnabled(.profile), let rpc {
                let applied = try await ProfileTabBootstrapLoader.load(
                    tab: .posts,
                    profileID: profileOwnerID,
                    rpc: rpc,
                    cursor: nil
                )
                pageItems = applied.posts ?? []
                cursor = applied.nextCursor
            } else {
                let page = try await profiles.wallPosts(
                    for: profileOwnerID,
                    page: PageRequest(limit: ProfileTabBootstrapLoader.defaultPageSize)
                )
                pageItems = page.items
                cursor = page.nextCursor
            }
            guard !Task.isCancelled else { return }
            guard generation == syncGeneration else {
                #if DEBUG
                ProfilePostsSync.logStaleResponseDropped(
                    generation: generation,
                    currentGeneration: syncGeneration
                )
                #endif
                loadTask = nil
                return
            }
            let overlay = OwnerProfileOptimisticStore.shared.posts.filter {
                $0.authorProfileID == profileOwnerID
            }
            let beforeCount = items.count
            let serverMerged = OwnerProfileOptimisticStore.merging(overlay: overlay, into: pageItems)
            items = OwnerProfileOptimisticStore.merging(overlay: serverMerged, into: [])
            nextCursor = cursor
            detailCache.seed(posts: items)
            hasLoaded = true
            #if DEBUG
            ProfilePostsSync.logAuthoritativeReturned(generation: generation, count: pageItems.count)
            ProfilePostsSync.logReconciled(
                beforeCount: beforeCount,
                snapshotCount: pageItems.count,
                afterCount: items.count
            )
            ProfilePostsSync.logUIVisibleCount(items.count)
            #endif
            state = items.isEmpty ? .empty : .loaded(itemCount: items.count)
            prefetchEngagement(for: items.map(\.id))
            OwnerProfileOptimisticStore.shared.syncOwnerPostsState(items)
        } catch {
            guard !Task.isCancelled else { return }
            guard generation == syncGeneration else {
                #if DEBUG
                ProfilePostsSync.logStaleResponseDropped(
                    generation: generation,
                    currentGeneration: syncGeneration
                )
                #endif
                loadTask = nil
                return
            }
            if items.isEmpty {
                state = .failed(message: ProfileSectionSupport.message(for: error))
            }
        }
        loadTask = nil
    }

    private func performLoadMore(cursor: String?, generation: Int) async {
        do {
            let pageItems: [Post]
            let newCursor: String?
            if BackendV2FeatureFlags.isEnabled(.profile), let rpc {
                let applied = try await ProfileTabBootstrapLoader.load(
                    tab: .posts,
                    profileID: profileOwnerID,
                    rpc: rpc,
                    cursor: cursor
                )
                pageItems = applied.posts ?? []
                newCursor = applied.nextCursor
            } else {
                let page = try await profiles.wallPosts(
                    for: profileOwnerID,
                    page: PageRequest(cursor: cursor, limit: ProfileTabBootstrapLoader.defaultPageSize)
                )
                pageItems = page.items
                newCursor = page.nextCursor
            }
            guard generation == paginationGeneration, !Task.isCancelled else { return }
            if pageItems.isEmpty {
                nextCursor = nil
                return
            }
            appendUniquePosts(pageItems)
            nextCursor = newCursor
            state = items.isEmpty ? .empty : .loaded(itemCount: items.count)
            prefetchEngagement(for: pageItems.map(\.id))
        } catch {
            guard generation == paginationGeneration else { return }
        }
    }

    private func appendUniquePosts(_ pageItems: [Post]) {
        let existing = Set(items.map(\.id))
        let fresh = pageItems.filter { !existing.contains($0.id) }
        guard !fresh.isEmpty else {
            nextCursor = nil
            return
        }
        items.append(contentsOf: fresh)
        detailCache.seed(posts: items)
    }
}
