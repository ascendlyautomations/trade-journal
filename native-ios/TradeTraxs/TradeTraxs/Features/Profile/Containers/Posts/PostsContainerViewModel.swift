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
    private let navigationCoordinator: NavigationCoordinator
    private let detailCache: DetailPresentationCache
    private let engagementStore: EngagementStore?
    private var loadTask: Task<Void, Never>?
    private var hasLoaded = false
    private var isScreenOwned = false
    private var syncGeneration: UInt64 = 0

    /// True after an authoritative section fetch or complete bootstrap snapshot.
    var hasAuthoritativePayload: Bool { hasLoaded }

    init(
        profileID: ProfileID,
        profiles: any ProfileRepository,
        navigationCoordinator: NavigationCoordinator,
        detailCache: DetailPresentationCache,
        engagementStore: EngagementStore? = nil,
        isOwner: Bool = true
    ) {
        self.profileOwnerID = profileID
        self.isOwner = isOwner
        self.profiles = profiles
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

    func loadMoreIfNeeded() async {
        // Web Profile Posts loads the full wall in one request.
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
            let beforeCount = items.count
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
        do {
            // Web: `profile_posts` select * / user_id / created_at desc (+ pinned client sort).
            let page = try await profiles.wallPosts(
                for: profileOwnerID,
                page: PageRequest(limit: 500)
            )
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
            let serverMerged = OwnerProfileOptimisticStore.merging(overlay: overlay, into: page.items)
            items = OwnerProfileOptimisticStore.merging(overlay: serverMerged, into: items)
            detailCache.seed(posts: items)
            hasLoaded = true
            #if DEBUG
            ProfilePostsSync.logAuthoritativeReturned(generation: generation, count: page.items.count)
            ProfilePostsSync.logReconciled(
                beforeCount: beforeCount,
                snapshotCount: page.items.count,
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
}
